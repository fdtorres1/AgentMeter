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

    func testMapsClaudeAPIUsageForReadyAndStaleStatesWithoutInventingCredits() {
        let periodStart = Date(timeIntervalSince1970: 1_800_000_000)
        let periodEnd = Date(timeIntervalSince1970: 1_800_086_400)
        let apiUsage = APIUsageSummary(
            costUSD: 12.34,
            inputTokens: 1_200,
            outputTokens: 340,
            cacheReadTokens: 500,
            cacheCreationTokens: 60,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
        let balance = BalanceInfo(remaining: 12.34, used: nil, currencySymbol: "$", kind: .spent)
        let usage = ProviderUsage(planName: nil, windows: [], asOf: periodEnd, balance: balance, apiUsage: apiUsage)
        let ready = StatusSnapshotWriter.mapProvider(
            StatusSnapshotWriter.ProviderInput(id: "claude-api", displayName: "Claude API", state: .ready(usage))
        )
        let stale = StatusSnapshotWriter.mapProvider(
            StatusSnapshotWriter.ProviderInput(
                id: "claude-api",
                displayName: "Claude API",
                state: .stale(usage, error: "temporary API failure", since: periodEnd)
            )
        )

        for status in [ready, stale] {
            XCTAssertEqual(status.apiUsage?.costUSD, 12.34)
            XCTAssertEqual(status.apiUsage?.inputTokens, 1_200)
            XCTAssertEqual(status.apiUsage?.outputTokens, 340)
            XCTAssertEqual(status.apiUsage?.cacheReadTokens, 500)
            XCTAssertEqual(status.apiUsage?.cacheCreationTokens, 60)
            XCTAssertEqual(status.apiUsage?.periodStart, periodStart)
            XCTAssertEqual(status.apiUsage?.periodEnd, periodEnd)
            XCTAssertEqual(status.apiUsage?.currency, "USD")
            XCTAssertEqual(status.apiUsage?.prepaidCreditsStatus, "unavailable")
            XCTAssertTrue(status.apiUsage?.costExcludesPriorityTier ?? false)
            XCTAssertEqual(status.balance?.kind, "spent")
            XCTAssertEqual(status.balance?.amount, 12.34)
        }
        XCTAssertEqual(ready.state, "ready")
        XCTAssertEqual(stale.state, "stale")
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
