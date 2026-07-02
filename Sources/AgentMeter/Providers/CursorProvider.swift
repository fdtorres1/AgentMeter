import Foundation

/// Cursor plan usage via cursor.com, authenticated with the locally stored session token.
struct CursorProvider: UsageProvider {
    let id = "cursor"
    let displayName = "Cursor"
    let shortCode = "Cu"

    let fetcher = CursorUsageFetcher()

    var isDetected: Bool {
        FileManager.default.fileExists(atPath: fetcher.stateDBPath)
    }

    func fetch() async throws -> ProviderUsage {
        try await fetcher.fetchUsage()
    }
}
