import XCTest
@testable import AgentMeter

final class StatusSnapshotWriterTests: XCTestCase {
    func testMapsReadyProviderWithWindows() {
        let usage = ProviderUsage(
            planName: "Pro",
            windows: [
                UsageWindow(label: "5h", usedPercent: 42, resetsAt: Date(timeIntervalSince1970: 1_700_000_000)),
            ],
            asOf: Date(timeIntervalSince1970: 1_699_000_000)
        )
        let status = StatusSnapshotWriter.mapProvider(
            StatusSnapshotWriter.ProviderInput(
                id: "codex",
                displayName: "Codex",
                state: .ready(usage)
            )
        )

        XCTAssertEqual(status.state, "ready")
        XCTAssertEqual(status.windows.count, 1)
        XCTAssertEqual(status.windows[0].label, "5h")
        XCTAssertEqual(status.windows[0].usedPercent, 42)
        XCTAssertEqual(status.asOf, usage.asOf)
    }

    func testMapsStaleProviderWithRedactedError() {
        let usage = ProviderUsage(planName: nil, windows: [], asOf: nil)
        let since = Date(timeIntervalSince1970: 1_000_000)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let status = StatusSnapshotWriter.mapProvider(
            StatusSnapshotWriter.ProviderInput(
                id: "cursor",
                displayName: "Cursor",
                state: .stale(usage, error: "failed at \(home)/secret", since: since)
            )
        )

        XCTAssertEqual(status.state, "stale")
        XCTAssertEqual(status.staleSince, since)
        XCTAssertEqual(status.error, "failed at ~/secret")
        XCTAssertFalse(status.error?.contains(home) ?? true)
    }

    func testMapsBalanceOnlyProvider() {
        let usage = ProviderUsage(
            planName: nil,
            windows: [],
            asOf: nil,
            balance: BalanceInfo(remaining: 9.5, used: nil, currencySymbol: "$", kind: .remaining)
        )
        let status = StatusSnapshotWriter.mapProvider(
            StatusSnapshotWriter.ProviderInput(
                id: "openrouter",
                displayName: "OpenRouter",
                state: .ready(usage)
            )
        )

        XCTAssertEqual(status.windows.count, 0)
        XCTAssertEqual(status.balance?.amount, 9.5)
        XCTAssertEqual(status.balance?.currency, "$")
        XCTAssertEqual(status.balance?.kind, "remaining")
    }

    func testMapsErrorState() {
        let status = StatusSnapshotWriter.mapProvider(
            StatusSnapshotWriter.ProviderInput(
                id: "claude",
                displayName: "Claude",
                state: .error("token expired")
            )
        )

        XCTAssertEqual(status.state, "error")
        XCTAssertEqual(status.error, "token expired")
        XCTAssertTrue(status.windows.isEmpty)
    }
}
