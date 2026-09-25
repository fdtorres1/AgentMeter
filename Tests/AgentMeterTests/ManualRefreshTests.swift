import XCTest
@testable import AgentMeter

final class ManualRefreshTests: XCTestCase {
    func testCurrentDayWarningUsesUTCReportCoverage() {
        let now = ISO8601DateFormatter().date(from: "2026-09-25T18:00:00Z")!
        let midnight = ISO8601DateFormatter().date(from: "2026-09-25T00:00:00Z")!
        func report(endingAt end: Date) -> APIUsageSummary {
            APIUsageSummary(costUSD: 1, inputTokens: 0, outputTokens: 0,
                            cacheReadTokens: 0, cacheCreationTokens: 0,
                            periodStart: midnight.addingTimeInterval(-86_400), periodEnd: end)
        }
        XCTAssertTrue(report(endingAt: midnight).isAwaitingCurrentDay(now: now))
        XCTAssertFalse(report(endingAt: now).isAwaitingCurrentDay(now: now))
    }

    @MainActor
    func testExplicitRefreshAndCLIRequestBypassProviderCache() async throws {
        let suite = "ManualRefreshTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recorder = RefreshRecorder()
        let store = UsageStore(settings: SettingsStore(defaults: defaults),
                               providers: [RefreshProvider(recorder: recorder)])
        try await waitForCount(1, recorder: recorder)
        store.refresh(forceRefresh: true)
        try await waitForCount(2, recorder: recorder)
        NotificationCenter.default.post(name: .agentMeterRefreshRequested, object: nil)
        try await waitForCount(3, recorder: recorder)
        let flags = await recorder.flags
        XCTAssertEqual(flags, [false, true, true])
    }

    @MainActor
    private func waitForCount(_ count: Int, recorder: RefreshRecorder) async throws {
        let deadline = Date().addingTimeInterval(3)
        while await recorder.flags.count < count {
            guard Date() < deadline else { throw WaitError.timeout }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private enum WaitError: Error { case timeout }
}

private struct RefreshProvider: UsageProvider {
    let recorder: RefreshRecorder
    let id = "manual-refresh-fixture"
    let displayName = "Fixture"
    let shortCode = "F"
    var isDetected: Bool { true }

    func fetch() async throws -> ProviderUsage {
        XCTFail("UsageStore must forward refresh intent through the protocol")
        return ProviderUsage(planName: nil, windows: [], asOf: nil)
    }

    func fetch(forceRefresh: Bool) async throws -> ProviderUsage {
        await recorder.record(forceRefresh)
        return ProviderUsage(planName: nil, windows: [], asOf: nil)
    }
}

private actor RefreshRecorder {
    private(set) var flags: [Bool] = []
    func record(_ force: Bool) { flags.append(force) }
}
