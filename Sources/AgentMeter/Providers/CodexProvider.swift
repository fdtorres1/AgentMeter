import Foundation

/// Codex/ChatGPT usage via the Codex CLI app-server protocol, with session-log
/// fallback for the primary account.
struct CodexProvider: UsageProvider {
    let accountConfig: CodexAccountConfig?
    let id: String
    let displayName: String
    let shortCode: String
    let codexHome: URL

    init(accountConfig: CodexAccountConfig? = nil) {
        self.accountConfig = accountConfig
        if let config = accountConfig {
            self.id = "codex:\(config.id.uuidString)"
            self.displayName = "Codex — \(config.label)"
            let initial = config.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
            self.shortCode = initial.isEmpty ? "Cx" : "Cx\(initial)"
            self.codexHome = config.expandedHomeURL()
        } else {
            self.id = "codex"
            self.displayName = "Codex"
            self.shortCode = "Cx"
            self.codexHome = CodexPath.defaultHome
        }
    }

    var isPrimary: Bool { accountConfig == nil }

    @MainActor var accountEmail: String? {
        CodexAccountCache.shared.lastEmail(for: id)
    }

    var isDetected: Bool {
        let fm = FileManager.default
        if isPrimary {
            let sessionsRoot = codexHome.appendingPathComponent("sessions")
            let authFile = codexHome.appendingPathComponent("auth.json")
            return fm.fileExists(atPath: sessionsRoot.path)
                || fm.fileExists(atPath: authFile.path)
        }
        let authFile = codexHome.appendingPathComponent("auth.json")
        return fm.fileExists(atPath: authFile.path)
    }

    var dashboardURL: URL? {
        URL(string: "https://chatgpt.com/codex/settings/usage")
    }

    func fetch() async throws -> ProviderUsage {
        let now = Date()
        let providerID = id
        let primary = isPrimary
        let home = codexHome
        let sessionsRoot = home.appendingPathComponent("sessions")
        let logReader = CodexUsageReader(sessionsRoot: sessionsRoot)

        let cached = await MainActor.run {
            CodexAccountCache.shared.cachedReading(
                for: providerID,
                maxAge: CodexAppServerClient.pollInterval
            )
        }
        if let cached {
            if primary, let logUsage = try? logReader.readUsage(),
               let logAsOf = logUsage.asOf,
               logAsOf > cached.timestamp {
                return logUsage
            }
            return CodexAppServerClient.usage(from: cached.reading, now: now)
        }

        do {
            let reading = try await CodexAppServerClient.readAccount(codexHome: home)
            DebugLog.write("codex app-server \(providerID): ok (email present: \(reading.email != nil), limits: \(reading.rateLimits != nil))")
            await MainActor.run {
                CodexAccountCache.shared.store(reading, for: providerID, at: now)
            }
            let usage = CodexAppServerClient.usage(from: reading, now: now)

            if primary, let logUsage = try? logReader.readUsage(),
               let logAsOf = logUsage.asOf,
               logAsOf > now {
                return logUsage
            }
            return usage
        } catch {
            DebugLog.write("codex app-server \(providerID): failed: \(error)")
            if primary {
                return try logReader.readUsage()
            }
            if case CodexAppServerError.notSignedIn = error {
                throw CodexAppServerError.notSignedIn
            }
            throw error
        }
    }
}
