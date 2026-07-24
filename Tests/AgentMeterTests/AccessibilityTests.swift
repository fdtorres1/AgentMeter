import XCTest
@testable import AgentMeter

final class AccessibilityTests: XCTestCase {
    private let usage = ProviderUsage(
        planName: nil,
        windows: [UsageWindow(label: "5h", usedPercent: 25, resetsAt: nil)],
        asOf: nil
    )

    func testMenuBarSummaryIncludesAppNameAndProviders() {
        let summary = MenuBarAccessibilitySummary.build(
            providers: [
                .init(displayName: "Codex", state: .ready(usage)),
                .init(
                    displayName: "Cursor",
                    state: .ready(ProviderUsage(
                        planName: nil,
                        windows: [UsageWindow(label: "Monthly", usedPercent: 82, resetsAt: nil)],
                        asOf: nil
                    ))
                ),
            ],
            countDirection: .used,
            balanceThreshold: 5
        )

        XCTAssertTrue(summary.contains("AgentMeter"))
        XCTAssertTrue(summary.contains("Codex"))
        XCTAssertTrue(summary.contains("25% used"))
        XCTAssertTrue(summary.contains("Cursor"))
        XCTAssertTrue(summary.contains("82% used"))
        XCTAssertTrue(summary.contains("high usage"))
    }

    func testMenuBarSummaryIncludesStaleQualifier() {
        let summary = MenuBarAccessibilitySummary.build(
            providers: [
                .init(
                    displayName: "Venice",
                    state: .stale(
                        ProviderUsage(
                            planName: nil,
                            windows: [],
                            asOf: nil,
                            balance: BalanceInfo(remaining: 12, used: nil, currencySymbol: "$")
                        ),
                        error: "offline",
                        since: Date()
                    )
                ),
            ],
            countDirection: .used,
            balanceThreshold: 5
        )

        XCTAssertTrue(summary.contains("Venice"))
        XCTAssertTrue(summary.contains("data is stale"))
    }

    func testMenuBarSummaryUsesRemainingDirection() {
        let summary = MenuBarAccessibilitySummary.build(
            providers: [
                .init(displayName: "Codex", state: .ready(usage)),
            ],
            countDirection: .remaining,
            balanceThreshold: 5
        )

        XCTAssertTrue(summary.contains("75% remaining"))
    }

    func testMenuBarSummaryIncludesLowBalanceQualifier() {
        let summary = MenuBarAccessibilitySummary.build(
            providers: [
                .init(
                    displayName: "OpenRouter",
                    state: .ready(ProviderUsage(
                        planName: nil,
                        windows: [],
                        asOf: nil,
                        balance: BalanceInfo(remaining: 3, used: nil, currencySymbol: "$")
                    ))
                ),
            ],
            countDirection: .used,
            balanceThreshold: 5
        )

        XCTAssertTrue(summary.contains("OpenRouter"))
        XCTAssertTrue(summary.contains("low balance"))
    }

    func testMenuBarSummaryErrorState() {
        let summary = MenuBarAccessibilitySummary.build(
            providers: [
                .init(displayName: "Claude", state: .error("network down")),
            ],
            countDirection: .used,
            balanceThreshold: 5
        )

        XCTAssertTrue(summary.contains("Claude"))
        XCTAssertTrue(summary.contains("error"))
    }

    func testMenuBarSummaryEmptyProvidersIsAppNameOnly() {
        let summary = MenuBarAccessibilitySummary.build(
            providers: [],
            countDirection: .used,
            balanceThreshold: 5
        )
        XCTAssertEqual(summary, "AgentMeter")
    }

    func testUsageMeterSeverityThresholds() {
        XCTAssertEqual(UsageMeterSeverity.forUsedPercent(59.9), .normal)
        XCTAssertEqual(UsageMeterSeverity.forUsedPercent(60), .warning)
        XCTAssertEqual(UsageMeterSeverity.forUsedPercent(84.9), .warning)
        XCTAssertEqual(UsageMeterSeverity.forUsedPercent(85), .critical)
    }

    func testUsageMeterSeverityQualifiers() {
        XCTAssertNil(UsageMeterSeverity.normal.qualifier)
        XCTAssertEqual(UsageMeterSeverity.warning.qualifier, "high usage")
        XCTAssertEqual(UsageMeterSeverity.critical.qualifier, "nearly used up")
    }

    func testUsageMeterSeveritySymbols() {
        XCTAssertNil(UsageMeterSeverity.normal.symbolName)
        XCTAssertEqual(UsageMeterSeverity.warning.symbolName, "exclamationmark.triangle.fill")
        XCTAssertEqual(UsageMeterSeverity.critical.symbolName, "exclamationmark.octagon.fill")
    }
}
