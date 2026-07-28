import XCTest
import AgentMeterStatusKit

final class StatusTableTests: XCTestCase {
    func testRenderReadyStaleErrorAndBalanceProviders() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let staleSince = Date(timeIntervalSince1970: 1_999_000_000)
        let reset = Date(timeIntervalSince1970: 2_001_000_000)

        let snapshot = StatusSnapshot(
            generatedAt: now.addingTimeInterval(-120),
            appVersion: "1.0",
            providers: [
                ProviderStatus(
                    id: "codex",
                    displayName: "Codex",
                    state: "ready",
                    windows: [
                        WindowStatus(label: "5h", usedPercent: 42, resetsAt: reset),
                        WindowStatus(label: "Weekly", usedPercent: 17, resetsAt: nil),
                    ]
                ),
                ProviderStatus(
                    id: "cursor",
                    displayName: "Cursor",
                    state: "stale",
                    windows: [
                        WindowStatus(label: "Plan", usedPercent: 55, resetsAt: nil),
                    ],
                    staleSince: staleSince,
                    error: "HTTP 503"
                ),
                ProviderStatus(
                    id: "claude",
                    displayName: "Claude",
                    state: "error",
                    error: "token expired"
                ),
                ProviderStatus(
                    id: "openrouter",
                    displayName: "OpenRouter",
                    state: "ready",
                    balance: BalanceStatus(amount: 12.5, currency: "$", kind: "remaining")
                ),
            ]
        )

        let table = StatusTable.renderStatusTable(snapshot, now: now)

        XCTAssertTrue(table.contains("Codex"))
        XCTAssertTrue(table.contains("5h: 42% used"))
        XCTAssertTrue(table.contains("Weekly: 17% used"))
        XCTAssertTrue(table.contains("state: stale"))
        XCTAssertTrue(table.contains("stale since"))
        XCTAssertTrue(table.contains("error: HTTP 503"))
        XCTAssertTrue(table.contains("Claude"))
        XCTAssertTrue(table.contains("error: token expired"))
        XCTAssertTrue(table.contains("balance: $12.50 remaining"))
    }

    func testStalenessWarningWhenOlderThanTenMinutes() {
        let now = Date(timeIntervalSince1970: 3_000_000_000)
        let snapshot = StatusSnapshot(
            generatedAt: now.addingTimeInterval(-(StatusTable.defaultStalenessThreshold + 30)),
            appVersion: "1.0",
            providers: []
        )

        XCTAssertTrue(StatusTable.isSnapshotStale(snapshot, now: now))
        let table = StatusTable.renderStatusTable(snapshot, now: now)
        XCTAssertTrue(table.contains("Warning: snapshot is older than 10 minutes"))
    }

    func testFreshSnapshotHasNoStalenessWarning() {
        let now = Date(timeIntervalSince1970: 3_000_000_000)
        let snapshot = StatusSnapshot(
            generatedAt: now.addingTimeInterval(-60),
            appVersion: "1.0",
            providers: []
        )

        XCTAssertFalse(StatusTable.isSnapshotStale(snapshot, now: now))
        let table = StatusTable.renderStatusTable(snapshot, now: now)
        XCTAssertFalse(table.contains("Warning:"))
    }
}
