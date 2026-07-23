import XCTest
@testable import AgentMeter

final class MenuBarEntriesTests: XCTestCase {
    private let usage = ProviderUsage(
        planName: nil,
        windows: [UsageWindow(label: "5h", usedPercent: 50, resetsAt: nil)],
        asOf: nil
    )

    func testSeverityBelowSixtyIsNormal() {
        let state = ProviderState.ready(ProviderUsage(
            planName: nil,
            windows: [UsageWindow(label: "5h", usedPercent: 59.9, resetsAt: nil)],
            asOf: nil
        ))
        XCTAssertEqual(MenuBarTitleRenderer.severity(for: state, balanceThreshold: 5), .normal)
    }

    func testSeverityAtSixtyIsWarning() {
        let state = ProviderState.ready(ProviderUsage(
            planName: nil,
            windows: [UsageWindow(label: "5h", usedPercent: 60, resetsAt: nil)],
            asOf: nil
        ))
        XCTAssertEqual(MenuBarTitleRenderer.severity(for: state, balanceThreshold: 5), .warning)
    }

    func testSeverityAtEightyFiveIsCritical() {
        let state = ProviderState.ready(ProviderUsage(
            planName: nil,
            windows: [UsageWindow(label: "5h", usedPercent: 85, resetsAt: nil)],
            asOf: nil
        ))
        XCTAssertEqual(MenuBarTitleRenderer.severity(for: state, balanceThreshold: 5), .critical)
    }

    func testStaleWinsOverHighPercent() {
        let state = ProviderState.stale(
            ProviderUsage(
                planName: nil,
                windows: [UsageWindow(label: "5h", usedPercent: 95, resetsAt: nil)],
                asOf: nil
            ),
            error: "offline",
            since: Date()
        )
        XCTAssertEqual(MenuBarTitleRenderer.severity(for: state, balanceThreshold: 5), .stale)
    }

    func testBalanceBelowThresholdIsWarning() {
        let state = ProviderState.ready(ProviderUsage(
            planName: nil,
            windows: [],
            asOf: nil,
            balance: BalanceInfo(remaining: 3, used: nil, currencySymbol: "$")
        ))
        XCTAssertEqual(MenuBarTitleRenderer.severity(for: state, balanceThreshold: 5), .warning)
    }

    func testLoadingIsNormalAndErrorIsCritical() {
        XCTAssertEqual(MenuBarTitleRenderer.severity(for: .loading, balanceThreshold: 5), .normal)
        XCTAssertEqual(MenuBarTitleRenderer.severity(for: .error("fail"), balanceThreshold: 5), .critical)
    }
}
