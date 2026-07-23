import Foundation

/// Codex/ChatGPT usage from local Codex CLI session logs.
struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let shortCode = "Cx"

    let reader = CodexUsageReader()

    var isDetected: Bool {
        FileManager.default.fileExists(atPath: reader.sessionsRoot.path)
    }

    var dashboardURL: URL? {
        URL(string: "https://chatgpt.com/codex/settings/usage")
    }

    func fetch() async throws -> ProviderUsage {
        try reader.readUsage()
    }
}
