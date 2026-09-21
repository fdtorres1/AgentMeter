import Foundation

struct CodexAccountConfig: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var label: String
    var codexHomePath: String

    init(id: UUID = UUID(), label: String, codexHomePath: String) {
        self.id = id
        self.label = label
        self.codexHomePath = codexHomePath
    }

    /// Suggests `~/.codex-<slug>` from a human label.
    nonisolated static func suggestedHomePath(for label: String) -> String {
        let slug = label
            .lowercased()
            .map { character -> Character in
                if character.isLetter || character.isNumber { return character }
                return "-"
            }
            .reduce(into: "") { result, character in
                if character == "-", result.last == "-" { return }
                result.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let suffix = slug.isEmpty ? "account" : slug
        return "~/.codex-\(suffix)"
    }

    /// Terminal command that signs in a separate Codex account. Codex refuses
    /// a CODEX_HOME that does not exist yet, so the directory is created first.
    /// `~` is left unquoted so the shell expands it; other paths are quoted.
    nonisolated static func loginCommand(homePath: String) -> String {
        let path: String
        if homePath.hasPrefix("~/"), !homePath.contains(where: { $0.isWhitespace || $0 == "'" || $0 == "\"" }) {
            path = homePath
        } else {
            path = "'" + homePath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        }
        return "mkdir -p \(path) && CODEX_HOME=\(path) codex login"
    }

    nonisolated func expandedHomeURL() -> URL {
        CodexPath.expand(codexHomePath)
    }
}

enum CodexPath {
    nonisolated static func expand(_ path: String) -> URL {
        let expanded: String
        if path.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            expanded = home + path.dropFirst()
        } else if path == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else {
            expanded = path
        }
        return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    nonisolated static var defaultHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }
}

@MainActor
final class CodexAccountCache {
    static let shared = CodexAccountCache()

    private struct Entry {
        let reading: CodexAccountReading
        let timestamp: Date
    }

    private var entries: [String: Entry] = [:]

    func cachedReading(for providerID: String, maxAge: TimeInterval) -> (reading: CodexAccountReading, timestamp: Date)? {
        guard let entry = entries[providerID],
              Date().timeIntervalSince(entry.timestamp) < maxAge else {
            return nil
        }
        return (entry.reading, entry.timestamp)
    }

    func store(_ reading: CodexAccountReading, for providerID: String, at timestamp: Date = Date()) {
        entries[providerID] = Entry(reading: reading, timestamp: timestamp)
    }

    func lastEmail(for providerID: String) -> String? {
        entries[providerID]?.reading.email
    }

    func lastPlanType(for providerID: String) -> String? {
        let reading = entries[providerID]?.reading
        return reading?.planType ?? reading?.rateLimits?.planType
    }

    func clear(providerID: String) {
        entries.removeValue(forKey: providerID)
    }
}
