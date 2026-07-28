import Foundation
import AgentMeterStatusKit

enum StatusSnapshotWriter {
    struct ProviderInput: Sendable {
        let id: String
        let displayName: String
        let state: ProviderState
    }

    nonisolated static func makeSnapshot(
        providers: [ProviderInput],
        appVersion: String,
        generatedAt: Date = Date()
    ) -> StatusSnapshot {
        StatusSnapshot(
            generatedAt: generatedAt,
            appVersion: appVersion,
            providers: providers.map(mapProvider)
        )
    }

    nonisolated static func mapProvider(_ input: ProviderInput) -> ProviderStatus {
        switch input.state {
        case .loading:
            return ProviderStatus(
                id: input.id,
                displayName: input.displayName,
                state: "loading"
            )
        case .error(let message):
            return ProviderStatus(
                id: input.id,
                displayName: input.displayName,
                state: "error",
                error: ErrorRedaction.redact(message)
            )
        case .ready(let usage):
            return providerStatus(
                id: input.id,
                displayName: input.displayName,
                state: "ready",
                usage: usage
            )
        case .stale(let usage, let error, let since):
            var status = providerStatus(
                id: input.id,
                displayName: input.displayName,
                state: "stale",
                usage: usage
            )
            status.staleSince = since
            status.error = ErrorRedaction.redact(error)
            return status
        }
    }

    nonisolated private static func providerStatus(
        id: String,
        displayName: String,
        state: String,
        usage: ProviderUsage
    ) -> ProviderStatus {
        ProviderStatus(
            id: id,
            displayName: displayName,
            state: state,
            windows: usage.windows.map {
                WindowStatus(
                    label: $0.label,
                    usedPercent: $0.usedPercent,
                    resetsAt: $0.resetsAt
                )
            },
            balance: usage.balance.map(mapBalance),
            asOf: usage.asOf
        )
    }

    nonisolated private static func mapBalance(_ balance: BalanceInfo) -> BalanceStatus {
        BalanceStatus(
            amount: balance.remaining,
            currency: balance.currencySymbol,
            kind: balance.kind == .remaining ? "remaining" : "spent"
        )
    }

    @MainActor
    static func writeIfEnabled(store: UsageStore, settings: SettingsStore) {
        guard settings.agentAccessEnabled else { return }

        let providers = store.visibleProviders.map {
            ProviderInput(
                id: $0.id,
                displayName: $0.displayName,
                state: store.state(for: $0.id)
            )
        }
        let snapshot = makeSnapshot(
            providers: providers,
            appVersion: appVersion
        )

        do {
            try write(snapshot)
        } catch {
            // Snapshot failures must never affect the menu bar app.
        }
    }

    nonisolated static func write(_ snapshot: StatusSnapshot) throws {
        let url = StatusPaths.snapshotFileURL
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try StatusJSON.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    nonisolated static func deleteSnapshotFile() {
        try? FileManager.default.removeItem(at: StatusPaths.snapshotFileURL)
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
