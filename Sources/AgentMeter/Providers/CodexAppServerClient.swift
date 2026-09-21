import Foundation

struct CodexAccountReading: Equatable, Sendable {
    let email: String?
    let planType: String?
    let rateLimits: CodexRateLimits?
}

struct CodexRateLimits: Equatable, Sendable {
    let primary: CodexWindow?
    let secondary: CodexWindow?
    let limitId: String?
    let planType: String?
    let credits: CodexCredits?
}

struct CodexWindow: Equatable, Sendable {
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date?
}

struct CodexCredits: Equatable, Sendable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String
}

enum CodexPlan {
    nonisolated static func displayName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw.lowercased() {
        case "pro": return "Pro"
        case "plus": return "Plus"
        case "prolite": return "Pro Lite"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default:
            return raw.prefix(1).uppercased() + raw.dropFirst()
        }
    }
}

enum CodexAppServerError: LocalizedError, Equatable {
    case codexNotFound
    case notSignedIn
    case protocolError(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return L("Codex CLI not found")
        case .notSignedIn:
            return L("Not signed in — run the login command in Settings")
        case .protocolError(let detail):
            return detail
        case .timeout:
            return L("Codex app-server timed out")
        }
    }
}

/// Spawns the user's `codex app-server` CLI and reads account/rate-limit data
/// over newline-delimited JSON-RPC. Never persists credentials.
enum CodexAppServerClient {
    nonisolated static let pollInterval: TimeInterval = 300

    private nonisolated(unsafe) static var resolvedExecutableCache: URL??

    // MARK: - Public API

    nonisolated static func readAccount(
        codexHome: URL?,
        timeout: TimeInterval = 15
    ) async throws -> CodexAccountReading {
        guard let executable = resolveCodexExecutable() else {
            throw CodexAppServerError.codexNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server"]

        var environment = ProcessInfo.processInfo.environment
        if let codexHome {
            environment["CODEX_HOME"] = codexHome.path
        }
        process.environment = environment

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        try process.run()

        defer {
            terminate(process)
        }

        let writer = stdinPipe.fileHandleForWriting
        let reader = stdoutPipe.fileHandleForReading

        return try await withThrowingTaskGroup(of: CodexAccountReading.self) { group in
            group.addTask {
                try await readResponses(
                    from: reader,
                    writingTo: writer,
                    process: process,
                    appVersion: appVersion
                )
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeout))
                throw CodexAppServerError.timeout
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    nonisolated static func usage(from reading: CodexAccountReading, now: Date) -> ProviderUsage {
        var windows: [UsageWindow] = []
        if let primary = reading.rateLimits?.primary {
            windows.append(UsageWindow(
                label: CodexUsageReader.windowLabel(minutes: primary.windowMinutes),
                usedPercent: primary.usedPercent,
                resetsAt: primary.resetsAt
            ))
        }
        if let secondary = reading.rateLimits?.secondary {
            windows.append(UsageWindow(
                label: CodexUsageReader.windowLabel(minutes: secondary.windowMinutes),
                usedPercent: secondary.usedPercent,
                resetsAt: secondary.resetsAt
            ))
        }

        var balance: BalanceInfo?
        if let credits = reading.rateLimits?.credits, credits.hasCredits {
            let amount = Double(credits.balance) ?? 0
            balance = BalanceInfo(
                remaining: amount,
                used: nil,
                currencySymbol: "$",
                kind: .remaining
            )
        }

        let rawPlan = reading.planType ?? reading.rateLimits?.planType
        return ProviderUsage(
            planName: CodexPlan.displayName(rawPlan),
            windows: windows,
            asOf: now,
            balance: balance
        )
    }

    // MARK: - Parsing (pure)

    nonisolated static func parseAccount(_ json: [String: Any]) -> (email: String?, planType: String?)? {
        guard let result = json["result"] as? [String: Any] else { return nil }
        if result["account"] is NSNull { return (nil, nil) }
        guard let account = result["account"] as? [String: Any] else {
            return (nil, nil)
        }
        return (account["email"] as? String, account["planType"] as? String)
    }

    nonisolated static func parseRateLimits(_ json: [String: Any]) -> CodexRateLimits? {
        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? ""
            if message.contains("authentication required") {
                return nil
            }
            return nil
        }
        guard let result = json["result"] as? [String: Any],
              let rateLimits = result["rateLimits"] as? [String: Any] else {
            return nil
        }
        return rateLimitsFromDict(rateLimits)
    }

    nonisolated static func isAuthenticationRequiredError(_ json: [String: Any]) -> Bool {
        guard let error = json["error"] as? [String: Any] else { return false }
        let message = error["message"] as? String ?? ""
        return message.contains("authentication required")
    }

    nonisolated static func rateLimitsFromDict(_ dict: [String: Any]) -> CodexRateLimits {
        let primary = (dict["primary"] as? [String: Any]).flatMap(windowFromDict)
        let secondary = (dict["secondary"] as? [String: Any]).flatMap(windowFromDict)
        let limitId = dict["limitId"] as? String
        let planType = dict["planType"] as? String
        var credits: CodexCredits?
        if let creditsDict = dict["credits"] as? [String: Any] {
            credits = CodexCredits(
                hasCredits: creditsDict["hasCredits"] as? Bool ?? false,
                unlimited: creditsDict["unlimited"] as? Bool ?? false,
                balance: creditsDict["balance"] as? String ?? "0"
            )
        }
        return CodexRateLimits(
            primary: primary,
            secondary: secondary,
            limitId: limitId,
            planType: planType,
            credits: credits
        )
    }

    nonisolated static func windowFromDict(_ dict: [String: Any]) -> CodexWindow? {
        guard let usedPercent = dict["usedPercent"] as? Double else { return nil }
        let minutes = dict["windowDurationMins"] as? Int ?? 0
        var resetsAt: Date?
        if let epoch = dict["resetsAt"] as? Double {
            resetsAt = Date(timeIntervalSince1970: epoch)
        } else if let epoch = dict["resetsAt"] as? Int {
            resetsAt = Date(timeIntervalSince1970: TimeInterval(epoch))
        }
        return CodexWindow(usedPercent: usedPercent, windowMinutes: minutes, resetsAt: resetsAt)
    }

    // MARK: - Binary resolution

    nonisolated static func candidatePaths(home: String, pathEnv: String?) -> [String] {
        var paths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex",
        ]
        if let pathEnv {
            for entry in pathEnv.split(separator: ":") {
                let trimmed = entry.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                paths.append("\(trimmed)/codex")
            }
        }
        return paths
    }

    nonisolated static func resolveCodexExecutable() -> URL? {
        if let cached = resolvedExecutableCache {
            return cached
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pathEnv = ProcessInfo.processInfo.environment["PATH"]
        for candidate in candidatePaths(home: home, pathEnv: pathEnv) {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                let url = URL(fileURLWithPath: candidate)
                resolvedExecutableCache = url
                return url
            }
        }

        let resolved = resolveCodexViaShell()
        resolvedExecutableCache = resolved
        return resolved
    }

    /// Resets the shell-resolution cache (testing only).
    nonisolated static func resetExecutableCache() {
        resolvedExecutableCache = nil
    }

    nonisolated private static func resolveCodexViaShell() -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v codex"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty,
                  FileManager.default.isExecutableFile(atPath: path) else {
                return nil
            }
            return URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }

    // MARK: - Protocol I/O

    nonisolated private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    nonisolated private static func readResponses(
        from stdout: FileHandle,
        writingTo stdin: FileHandle,
        process: Process,
        appVersion: String
    ) async throws -> CodexAccountReading {
        let initialize = """
        {"id":1,"method":"initialize","params":{"clientInfo":{"name":"AgentMeter","version":"\(appVersion)"}}}
        """
        let initialized = #"{"method":"initialized"}"#
        let accountRead = #"{"id":2,"method":"account/read","params":{}}"#
        let rateLimitsRead = #"{"id":3,"method":"account/rateLimits/read","params":{}}"#

        try writeLine(initialize, to: stdin)
        try writeLine(initialized, to: stdin)
        try writeLine(accountRead, to: stdin)
        try writeLine(rateLimitsRead, to: stdin)

        var accountInfo: (email: String?, planType: String?)?
        var rateLimits: CodexRateLimits?
        var rateLimitsAuthRequired = false
        var pendingIDs: Set<Int> = [2, 3]
        var buffer = ""

        while !pendingIDs.isEmpty {
            let chunk = stdout.availableData
            if !chunk.isEmpty {
                if let text = String(data: chunk, encoding: .utf8) {
                    buffer += text
                }
            }

            while let newlineRange = buffer.range(of: "\n") {
                let line = String(buffer[buffer.startIndex..<newlineRange.lowerBound])
                buffer = String(buffer[newlineRange.upperBound...])
                guard !line.isEmpty,
                      let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let id = object["id"] as? Int else {
                    continue
                }

                pendingIDs.remove(id)
                switch id {
                case 2:
                    accountInfo = parseAccount(object)
                case 3:
                    if isAuthenticationRequiredError(object) {
                        rateLimitsAuthRequired = true
                    } else if let limits = parseRateLimits(object) {
                        rateLimits = limits
                    } else if let error = object["error"] as? [String: Any] {
                        let message = error["message"] as? String ?? L("Codex protocol error")
                        throw CodexAppServerError.protocolError(message)
                    }
                default:
                    break
                }
            }

            if pendingIDs.isEmpty { break }
            if chunk.isEmpty {
                // Empty read means EOF; if the server is gone, fail fast
                // instead of spinning until the overall timeout.
                if !process.isRunning {
                    throw CodexAppServerError.protocolError(L("Codex app-server exited unexpectedly"))
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        let email = accountInfo?.email
        let planType = accountInfo?.planType ?? rateLimits?.planType

        if email == nil && rateLimits == nil {
            throw CodexAppServerError.notSignedIn
        }
        if email == nil && rateLimitsAuthRequired && rateLimits == nil {
            throw CodexAppServerError.notSignedIn
        }

        return CodexAccountReading(
            email: email,
            planType: planType,
            rateLimits: rateLimits
        )
    }

    nonisolated private static func writeLine(_ line: String, to handle: FileHandle) throws {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
    }

    nonisolated private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.interrupt()
        }
    }
}
