import XCTest
@testable import AgentMeter

final class CredentialChangeTests: XCTestCase {
    @MainActor
    func testKeyChangeClearsReportAndIgnoresOldInFlightResult() async throws {
        let suite = "CredentialChangeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let requests = PendingReports()
        let provider = CredentialChangeProvider(requests: requests)
        let store = UsageStore(settings: SettingsStore(defaults: defaults), providers: [provider])
        try await waitUntil { await requests.count == 1 }
        await requests.complete(0, with: .success(report(10)))
        try await waitUntil { store.state(for: provider.id).usage != nil }

        store.refresh()
        try await waitUntil { await requests.count == 2 }
        store.credentialDidChange(for: provider.id)
        XCTAssertEqual(store.state(for: provider.id), .loading)
        try await waitUntil { await requests.count == 3 }
        await requests.complete(2, with: .failure(ClaudeAPIError.forbidden))
        try await waitUntil {
            if case .error = store.state(for: provider.id) { return true }
            return false
        }
        let newKeyState = store.state(for: provider.id)
        await requests.complete(1, with: .success(report(999)))
        // The old request is deliberately released after the new key fails.
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(store.state(for: provider.id), newKeyState)
        XCTAssertNil(store.state(for: provider.id).usage)
    }

    func testReportingGuidanceIsAvailableThroughProviderProtocol() {
        let provider: any UsageProvider = ClaudeAPIProvider()
        XCTAssertTrue(provider.credentialHelpText?.contains("Workspace-scoped") == true)
        XCTAssertEqual(provider.authKind, .apiKey(keyURL: ClaudeAPIProvider.keyURL))
    }

    private func report(_ amount: Double) -> ProviderUsage {
        ProviderUsage(planName: nil, windows: [], asOf: nil,
                      balance: BalanceInfo(remaining: amount, used: nil, currencySymbol: "$", kind: .spent))
    }

    @MainActor
    private func waitUntil(_ predicate: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !(await predicate()) {
            if Date() >= deadline { throw WaitError.timedOut }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private enum WaitError: Error { case timedOut }
}

private struct CredentialChangeProvider: UsageProvider {
    let requests: PendingReports
    let id = "credential-change-test"
    let displayName = "Fixture API"
    let shortCode = "F"
    var isDetected: Bool { true }
    func fetch() async throws -> ProviderUsage { try await requests.next() }
}

private actor PendingReports {
    private var continuations: [Int: CheckedContinuation<ProviderUsage, Error>] = [:]
    private(set) var count = 0

    func next() async throws -> ProviderUsage {
        try await withCheckedThrowingContinuation { continuation in
            continuations[count] = continuation
            count += 1
        }
    }

    func complete(_ index: Int, with result: Result<ProviderUsage, Error>) {
        continuations.removeValue(forKey: index)?.resume(with: result)
    }
}
