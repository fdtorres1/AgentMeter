import Foundation
import AgentMeterStatusKit

enum StatusSnapshotWriter {
    struct ProviderInput: Sendable {
        let id: String
        let displayName: String
        let state: ProviderState
        let accountEmail: String?
        let planType: String?
        let renewal: SubscriptionRenewal?

        init(
            id: String,
            displayName: String,
            state: ProviderState,
            accountEmail: String? = nil,
            planType: String? = nil,
            renewal: SubscriptionRenewal? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.state = state
            self.accountEmail = accountEmail
            self.planType = planType
            self.renewal = renewal
        }
    }

    nonisolated static func makeSnapshot(
        providers: [ProviderInput],
        appVersion: String,
        generatedAt: Date = Date()
    ) -> StatusSnapshot {
        StatusSnapshot(
            generatedAt: generatedAt,
            appVersion: appVersion,
            providers: providers.map { mapProvider($0, now: generatedAt) }
        )
    }

    nonisolated static func mapProvider(_ input: ProviderInput, now: Date = Date()) -> ProviderStatus {
        switch input.state {
        case .loading:
            return ProviderStatus(
                id: input.id,
                displayName: input.displayName,
                state: "loading",
                accountEmail: input.accountEmail,
                planType: input.planType,
                renewal: mapRenewal(input.renewal, now: now)
            )
        case .error(let message):
            return ProviderStatus(
                id: input.id,
                displayName: input.displayName,
                state: "error",
                error: ErrorRedaction.redact(message),
                accountEmail: input.accountEmail,
                planType: input.planType,
                renewal: mapRenewal(input.renewal, now: now)
            )
        case .ready(let usage):
            return providerStatus(
                id: input.id,
                displayName: input.displayName,
                state: "ready",
                usage: usage,
                accountEmail: input.accountEmail,
                planType: input.planType ?? usage.planName,
                renewal: input.renewal,
                now: now
            )
        case .stale(let usage, let error, let since):
            var status = providerStatus(
                id: input.id,
                displayName: input.displayName,
                state: "stale",
                usage: usage,
                accountEmail: input.accountEmail,
                planType: input.planType ?? usage.planName,
                renewal: input.renewal,
                now: now
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
        usage: ProviderUsage,
        accountEmail: String?,
        planType: String?,
        renewal: SubscriptionRenewal?,
        now: Date
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
            asOf: usage.asOf,
            accountEmail: accountEmail,
            planType: planType,
            renewal: mapRenewal(renewal, now: now),
            apiUsage: usage.apiUsage.map(mapAPIUsage)
        )
    }

    nonisolated private static func mapAPIUsage(_ usage: APIUsageSummary) -> APIUsageStatus {
        APIUsageStatus(
            costUSD: usage.costUSD,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            cacheReadTokens: usage.cacheReadTokens,
            cacheCreationTokens: usage.cacheCreationTokens,
            periodStart: usage.periodStart,
            periodEnd: usage.periodEnd
        )
    }

    nonisolated private static func mapRenewal(
        _ renewal: SubscriptionRenewal?,
        now: Date
    ) -> RenewalStatus? {
        guard let renewal else { return nil }
        return RenewalStatus(
            expectedAt: renewal.nextRenewal(after: now),
            platform: renewal.platform.rawValue,
            confirmedAt: renewal.confirmedAt
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

        let providers = store.visibleProviders.map { provider in
            let codexMeta = codexSnapshotMetadata(for: provider)
            return ProviderInput(
                id: provider.id,
                displayName: provider.displayName,
                state: store.state(for: provider.id),
                accountEmail: codexMeta.accountEmail,
                planType: codexMeta.planType,
                renewal: settings.renewal(for: provider.id)
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

    @MainActor
    private static func codexSnapshotMetadata(for provider: any UsageProvider) -> (accountEmail: String?, planType: String?) {
        guard provider.id == "codex" || provider.id.hasPrefix("codex:") else {
            return (nil, nil)
        }
        let email = CodexAccountCache.shared.lastEmail(for: provider.id)
        let rawPlan = CodexAccountCache.shared.lastPlanType(for: provider.id)
        return (email, CodexPlan.displayName(rawPlan))
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
