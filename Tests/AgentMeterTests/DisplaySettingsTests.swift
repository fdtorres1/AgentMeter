import XCTest
@testable import AgentMeter

final class DisplaySettingsTests: XCTestCase {
    func testCountDirectionDisplayPercent() {
        XCTAssertEqual(CountDirection.used.displayPercent(84), 84, accuracy: 0.001)
        XCTAssertEqual(CountDirection.remaining.displayPercent(84), 16, accuracy: 0.001)
    }

    func testCountDirectionPercentLabel() {
        XCTAssertEqual(CountDirection.used.percentLabel(84), "84%")
        XCTAssertEqual(CountDirection.used.percentLabel(84, menuBar: true), "84%")
        XCTAssertEqual(CountDirection.remaining.percentLabel(84), "16% left")
        XCTAssertEqual(CountDirection.remaining.percentLabel(84, menuBar: true), "16%")
    }

    func testResetDescriptionRelativeMatchesRemainingDescription() {
        let resetsAt = Date().addingTimeInterval(7200)
        let window = UsageWindow(label: "Weekly", usedPercent: 50, resetsAt: resetsAt)
        XCTAssertEqual(window.resetDescription(style: .relative), window.remainingDescription)
    }

    func testResetDescriptionAbsoluteContainsMonthDayAndTime() {
        let resetsAt = Date().addingTimeInterval(86400 * 5)
        let window = UsageWindow(label: "Weekly", usedPercent: 50, resetsAt: resetsAt)
        guard let description = window.resetDescription(style: .absolute) else {
            return XCTFail("expected absolute reset description")
        }
        XCTAssertTrue(description.hasPrefix("resets "))
        XCTAssertTrue(description.contains(":"))
    }

    func testMenuSummaryUsedMode() {
        let usage = ProviderUsage(
            planName: nil,
            windows: [UsageWindow(label: "5h", usedPercent: 84, resetsAt: nil)],
            asOf: nil
        )
        XCTAssertEqual(usage.menuSummary(direction: .used), "84%")
        XCTAssertEqual(usage.menuSummary(direction: .remaining), "16%")
    }

    func testMenuSummaryBalanceProvider() {
        let usage = ProviderUsage(
            planName: nil,
            windows: [],
            asOf: nil,
            balance: BalanceInfo(remaining: 12.5, used: nil, currencySymbol: "$")
        )
        XCTAssertEqual(usage.menuSummary(direction: .used), "$12")
        XCTAssertEqual(usage.menuSummary(direction: .remaining), "$12")
    }
}
