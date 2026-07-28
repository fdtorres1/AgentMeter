import Foundation

/// Redacts sensitive details from error strings before they leave the app process.
enum ErrorRedaction {
    nonisolated static func redact(_ message: String) -> String {
        var result = message

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !home.isEmpty {
            result = result.replacingOccurrences(of: home, with: "~")
        }

        result = result.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "~",
            options: .regularExpression
        )

        result = result.replacingOccurrences(
            of: #"sk-[A-Za-z0-9_-]{8,}"#,
            with: "sk-…",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"Bearer\s+[A-Za-z0-9._-]+"#,
            with: "Bearer …",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"[A-Za-z0-9_-]{32,}"#,
            with: "…",
            options: .regularExpression
        )

        return result
    }
}
