import Foundation
import AppKit
import AgentMeterStatusKit

enum AgentMeterCLI {
    /// The CLI ships inside AgentMeter.app/Contents/Helpers, where Bundle.main
    /// does not resolve to the app bundle; walk up from the executable to the
    /// enclosing .app to report the app's version. "dev" for bare builds.
    static let version: String = {
        var url = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        while url.path != "/" {
            if url.pathExtension == "app" {
                return Bundle(url: url)?
                    .infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
            }
            url.deleteLastPathComponent()
        }
        return "dev"
    }()

    static func run(arguments: [String] = Array(CommandLine.arguments.dropFirst())) -> Int32 {
        switch CLIArgumentParser.parse(arguments) {
        case .failure(.usage):
            if arguments.isEmpty {
                fputs(CLIHelp.text + "\n", stdout)
            } else {
                fputs("error: unknown command or option\n\n", stderr)
                fputs(CLIHelp.text + "\n", stderr)
            }
            return 1
        case .success(.help):
            fputs(CLIHelp.text + "\n", stdout)
            return 0
        case .success(.version):
            print("agentmeter \(version)")
            return 0
        case .success(.status(let json)):
            return runStatus(json: json)
        case .success(.refresh(let waitSeconds)):
            return runRefresh(waitSeconds: waitSeconds)
        case .success(.doctor):
            return runDoctor()
        case .success(.skill):
            print(AgentSkill.markdown, terminator: "")
            return 0
        }
    }

    private static func runStatus(json: Bool) -> Int32 {
        let url = StatusPaths.snapshotFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            fputs(
                "error: no snapshot at \(url.path)\n" +
                "AgentMeter must be running with \"Enable agent & CLI access\" " +
                "turned on in Settings → General.\n",
                stderr
            )
            return 2
        }

        guard let data = try? Data(contentsOf: url) else {
            fputs("error: could not read snapshot file\n", stderr)
            return 2
        }

        if json {
            if let string = String(data: data, encoding: .utf8) {
                print(string.trimmingCharacters(in: .newlines))
            }
            return 0
        }

        do {
            let snapshot = try StatusJSON.decode(data)
            print(StatusTable.renderStatusTable(snapshot))
        } catch {
            fputs("error: invalid snapshot JSON\n", stderr)
            return 2
        }
        return 0
    }

    private static func runRefresh(waitSeconds: Int) -> Int32 {
        guard isAppRunning() else {
            fputs("error: AgentMeter is not running\n", stderr)
            return 3
        }

        let previousGeneratedAt = currentSnapshotGeneratedAt()
        openURL("agentmeter://refresh")

        guard waitSeconds > 0 else { return 0 }

        let deadline = Date().addingTimeInterval(TimeInterval(waitSeconds))
        while Date() < deadline {
            if let generatedAt = currentSnapshotGeneratedAt(),
               generatedAt != previousGeneratedAt {
                return 0
            }
            Thread.sleep(forTimeInterval: 0.25)
        }

        fputs("error: timed out waiting for snapshot update\n", stderr)
        return 4
    }

    private static func runDoctor() -> Int32 {
        var lines: [String] = []
        lines.append("agentmeter CLI version: \(version)")

        let running = isAppRunning()
        lines.append("AgentMeter running: \(running ? "yes" : "no")")
        if let appVersion = runningAppVersion() {
            lines.append("AgentMeter app version: \(appVersion)")
        }

        let url = StatusPaths.snapshotFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let modified = attrs[.modificationDate] as? Date,
               let size = attrs[.size] as? Int64 {
                let age = Int(Date().timeIntervalSince(modified))
                lines.append("Snapshot: present (\(size) bytes, age \(age)s)")
            } else {
                lines.append("Snapshot: present")
            }

            if let data = try? Data(contentsOf: url),
               let snapshot = try? StatusJSON.decode(data) {
                lines.append("Snapshot schemaVersion: \(snapshot.schemaVersion)")
                lines.append("Snapshot generatedAt: \(iso8601(snapshot.generatedAt))")
                lines.append("Snapshot appVersion: \(snapshot.appVersion)")
                for provider in snapshot.providers {
                    var summary = "\(provider.displayName) (\(provider.id)): \(provider.state)"
                    if !provider.windows.isEmpty {
                        let windows = provider.windows.map {
                            "\($0.label) \(Int($0.usedPercent.rounded()))% used"
                        }.joined(separator: ", ")
                        summary += "; \(windows)"
                    }
                    if let balance = provider.balance {
                        summary += "; balance \(balance.currency)\(StatusTable.formatAmount(balance.amount)) \(balance.kind)"
                    }
                    if let error = provider.error {
                        summary += "; error: \(error)"
                    }
                    lines.append("  \(summary)")
                }
            } else {
                lines.append("Snapshot: unreadable or invalid JSON")
            }
        } else {
            lines.append("Snapshot: missing (agent access may be disabled)")
        }

        print(lines.joined(separator: "\n"))
        return 0
    }

    private static func isAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: StatusPaths.appBundleIdentifier).isEmpty
    }

    private static func runningAppVersion() -> String? {
        guard let app = NSRunningApplication.runningApplications(
            withBundleIdentifier: StatusPaths.appBundleIdentifier
        ).first,
              let bundleURL = app.bundleURL,
              let bundle = Bundle(url: bundleURL) else {
            return nil
        }
        return bundle.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    private static func currentSnapshotGeneratedAt() -> Date? {
        let url = StatusPaths.snapshotFileURL
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? StatusJSON.decode(data) else {
            return nil
        }
        return snapshot.generatedAt
    }

    private static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        if !NSWorkspace.shared.open(url) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [string]
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

@main
struct AgentMeterCLIEntrypoint {
    static func main() {
        let code = AgentMeterCLI.run()
        exit(code)
    }
}
