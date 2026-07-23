import XCTest
@testable import AgentMeter

final class ThresholdTrackerTests: XCTestCase {
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    private let providerID = "codex"
    private let windowLabel = "Weekly limit"

    override func setUp() {
        super.setUp()
        suiteName = "test-threshold-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testFiresWhenCrossingThresholdFromBelow() {
        var tracker = ThresholdTracker(defaults: testDefaults)

        let below = usage(percent: 75)
        XCTAssertTrue(tracker.crossings(providerID: providerID, usage: below, threshold: 80).isEmpty)

        let above = usage(percent: 82)
        let crossings = tracker.crossings(providerID: providerID, usage: above, threshold: 80)
        XCTAssertEqual(crossings.count, 1)
        XCTAssertEqual(crossings[0].usedPercent, 82)
    }

    func testDoesNotFireAgainWhileAboveThresholdIncludingAfterRestart() {
        var tracker = ThresholdTracker(defaults: testDefaults)

        let high = usage(percent: 85)
        XCTAssertEqual(tracker.crossings(providerID: providerID, usage: high, threshold: 80).count, 1)
        XCTAssertTrue(tracker.crossings(providerID: providerID, usage: high, threshold: 80).isEmpty)

        var restarted = ThresholdTracker(defaults: testDefaults)
        XCTAssertTrue(restarted.crossings(providerID: providerID, usage: high, threshold: 80).isEmpty)
    }

    func testRearmsAfterDropAndClimbsBack() {
        var tracker = ThresholdTracker(defaults: testDefaults)

        XCTAssertEqual(tracker.crossings(providerID: providerID, usage: usage(percent: 85), threshold: 80).count, 1)
        XCTAssertTrue(tracker.crossings(providerID: providerID, usage: usage(percent: 74), threshold: 80).isEmpty)

        let crossings = tracker.crossings(providerID: providerID, usage: usage(percent: 82), threshold: 80)
        XCTAssertEqual(crossings.count, 1)
    }

    func testRearmsWhenResetsAtMovesLater() {
        var tracker = ThresholdTracker(defaults: testDefaults)
        let early = Date().addingTimeInterval(3600)
        let later = Date().addingTimeInterval(86400)

        XCTAssertEqual(
            tracker.crossings(providerID: providerID, usage: usage(percent: 85, resetsAt: early), threshold: 80).count,
            1
        )
        XCTAssertTrue(
            tracker.crossings(providerID: providerID, usage: usage(percent: 85, resetsAt: early), threshold: 80).isEmpty
        )

        let crossings = tracker.crossings(
            providerID: providerID,
            usage: usage(percent: 85, resetsAt: later),
            threshold: 80
        )
        XCTAssertEqual(crossings.count, 1)
    }

    /// Window resets while the app is not running: fired-state persisted, but
    /// the fresh tracker has no in-memory last-seen values to detect the drop.
    /// An observation below threshold must still re-arm.
    func testRearmsWhenWindowResetWhileAppWasClosed() {
        var tracker = ThresholdTracker(defaults: testDefaults)
        XCTAssertEqual(tracker.crossings(providerID: providerID, usage: usage(percent: 85), threshold: 80).count, 1)

        // Simulate restart after the provider's window reset overnight.
        var restarted = ThresholdTracker(defaults: testDefaults)
        XCTAssertTrue(restarted.crossings(providerID: providerID, usage: usage(percent: 5), threshold: 80).isEmpty)

        let crossings = restarted.crossings(providerID: providerID, usage: usage(percent: 81), threshold: 80)
        XCTAssertEqual(crossings.count, 1)
    }

    func testRespectsDifferentThresholds() {
        var tracker = ThresholdTracker(defaults: testDefaults)
        let usage = usage(percent: 75)

        XCTAssertTrue(tracker.crossings(providerID: providerID, usage: usage, threshold: 80).isEmpty)
        XCTAssertEqual(tracker.crossings(providerID: providerID, usage: usage, threshold: 70).count, 1)
        XCTAssertTrue(tracker.crossings(providerID: providerID, usage: usage, threshold: 80).isEmpty)
    }

    func testRearmsWhenBalanceRisesToThreshold() {
        var tracker = ThresholdTracker(defaults: testDefaults)
        let low = BalanceInfo(remaining: 3, used: nil, currencySymbol: "$")
        let high = BalanceInfo(remaining: 8, used: nil, currencySymbol: "$")

        XCTAssertTrue(tracker.balanceCrossings(providerID: "openrouter", balance: low, threshold: 5))
        XCTAssertFalse(tracker.balanceCrossings(providerID: "openrouter", balance: low, threshold: 5))
        XCTAssertFalse(tracker.balanceCrossings(providerID: "openrouter", balance: high, threshold: 5))
        XCTAssertTrue(tracker.balanceCrossings(providerID: "openrouter", balance: low, threshold: 5))
    }

    func testBalanceCrossingsPersistsAcrossRestart() {
        var tracker = ThresholdTracker(defaults: testDefaults)
        let low = BalanceInfo(remaining: 2, used: nil, currencySymbol: "$")
        XCTAssertTrue(tracker.balanceCrossings(providerID: "deepseek", balance: low, threshold: 5))

        var restarted = ThresholdTracker(defaults: testDefaults)
        XCTAssertFalse(restarted.balanceCrossings(providerID: "deepseek", balance: low, threshold: 5))
    }

    func testBalanceCrossingsFiresWhenDroppingBelowThreshold() {
        var tracker = ThresholdTracker(defaults: testDefaults)
        let above = BalanceInfo(remaining: 10, used: nil, currencySymbol: "$")
        let below = BalanceInfo(remaining: 4, used: nil, currencySymbol: "$")

        XCTAssertFalse(tracker.balanceCrossings(providerID: "venice", balance: above, threshold: 5))
        XCTAssertTrue(tracker.balanceCrossings(providerID: "venice", balance: below, threshold: 5))
    }

    private func usage(percent: Double, resetsAt: Date? = nil) -> ProviderUsage {
        ProviderUsage(
            planName: nil,
            windows: [UsageWindow(label: windowLabel, usedPercent: percent, resetsAt: resetsAt)],
            asOf: nil
        )
    }
}
