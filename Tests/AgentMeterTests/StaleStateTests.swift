import XCTest
@testable import AgentMeter

final class StaleStateTests: XCTestCase {
    private let usage = ProviderUsage(
        planName: "Pro",
        windows: [UsageWindow(label: "5h", usedPercent: 42, resetsAt: nil)],
        asOf: nil
    )

    func testReadyFailureBecomesStalePreservingUsage() {
        let previous: ProviderState = .ready(usage)
        let date = Date(timeIntervalSince1970: 1_000_000)
        let next = ProviderState.nextState(after: previous, failure: "network down", at: date)

        guard case .stale(let preserved, let error, let since) = next else {
            return XCTFail("expected stale state")
        }
        XCTAssertEqual(preserved, usage)
        XCTAssertEqual(error, "network down")
        XCTAssertEqual(since, date)
    }

    func testStaleFailurePreservesOriginalSinceAndUpdatesError() {
        let originalSince = Date(timeIntervalSince1970: 500_000)
        let previous: ProviderState = .stale(usage, error: "old error", since: originalSince)
        let newDate = Date(timeIntervalSince1970: 900_000)
        let next = ProviderState.nextState(after: previous, failure: "new error", at: newDate)

        guard case .stale(let preserved, let error, let since) = next else {
            return XCTFail("expected stale state")
        }
        XCTAssertEqual(preserved, usage)
        XCTAssertEqual(error, "new error")
        XCTAssertEqual(since, originalSince)
        XCTAssertNotEqual(since, newDate)
    }

    func testLoadingFailureBecomesError() {
        let next = ProviderState.nextState(after: .loading, failure: "failed", at: Date())
        guard case .error(let message) = next else {
            return XCTFail("expected error state")
        }
        XCTAssertEqual(message, "failed")
    }

    func testErrorFailureStaysError() {
        let next = ProviderState.nextState(after: .error("first"), failure: "second", at: Date())
        guard case .error(let message) = next else {
            return XCTFail("expected error state")
        }
        XCTAssertEqual(message, "second")
    }

    func testUsageReturnsDataForStale() {
        let since = Date()
        let state: ProviderState = .stale(usage, error: "timeout", since: since)
        XCTAssertEqual(state.usage, usage)
    }
}
