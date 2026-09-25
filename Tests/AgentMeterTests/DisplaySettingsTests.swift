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
        // Stay away from a minute boundary: the two convenience calls each
        // sample the clock independently.
        let resetsAt = Date().addingTimeInterval(7230)
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

    func testAbsoluteResetIncludesRoundedDurationAndLocalizedUnits() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func duration(_ seconds: TimeInterval) -> String? {
            UsageWindow(label: "Weekly", usedPercent: 50, resetsAt: now.addingTimeInterval(seconds))
                .resetDescription(style: .absolute, now: now)?.components(separatedBy: "(").last
        }
        XCTAssertEqual(duration(6 * 86_400 + 18 * 3_600), "6 days 18 hours)")
        XCTAssertEqual(duration(2 * 86_400 + 4 * 3_600), "2 days 4 hours)")
        XCTAssertEqual(duration(4 * 3_600 + 36 * 60), "4 hours 36 minutes)")
        XCTAssertEqual(duration(36 * 60), "36 minutes)")
    }

    func testAbsoluteResetDurationRoundingAndRollover() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func description(_ seconds: TimeInterval) -> String? {
            UsageWindow(label: "Weekly", usedPercent: 50, resetsAt: now.addingTimeInterval(seconds))
                .resetDescription(style: .absolute, now: now)
        }
        XCTAssertTrue(description(86_400 + 1.49 * 3_600)?.hasSuffix("(1 day 1 hour)") == true)
        XCTAssertTrue(description(86_400 + 1.51 * 3_600)?.hasSuffix("(1 day 2 hours)") == true)
        XCTAssertTrue(description(86_400 + 23.6 * 3_600)?.hasSuffix("(2 days 0 hours)") == true)
        XCTAssertTrue(description(23 * 3_600 + 59.6 * 60)?.hasSuffix("(1 day 0 hours)") == true)
        XCTAssertTrue(description(59.6 * 60)?.hasSuffix("(1 hour 0 minutes)") == true)
        XCTAssertTrue(description(4 * 3_600 + 36.4 * 60)?.hasSuffix("(4 hours 36 minutes)") == true)
        XCTAssertTrue(description(4 * 3_600 + 36.6 * 60)?.hasSuffix("(4 hours 37 minutes)") == true)
        XCTAssertTrue(description(59)?.hasSuffix("(less than a minute)") == true)
        XCTAssertEqual(description(-1), "resets soon")
    }

    func testAbsoluteResetWithoutResetDateIsNil() {
        XCTAssertNil(UsageWindow(label: "Weekly", usedPercent: 50, resetsAt: nil)
            .resetDescription(style: .absolute, now: Date(timeIntervalSince1970: 0)))
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
