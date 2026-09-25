import SwiftUI

struct ProviderUsageSections: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        let visible = store.visibleProviders
        if visible.isEmpty {
            Text(L("No providers enabled. Open Settings to turn some on."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, provider in
                if index > 0 { Divider() }
                ProviderSection(
                    provider: provider,
                    state: store.state(for: provider.id),
                    settings: settings
                )
            }
        }
    }
}

struct ProviderSection: View {
    let provider: any UsageProvider
    let state: ProviderState
    @ObservedObject var settings: SettingsStore

    var body: some View {
        sectionContent
            .accessibilityElement(children: .contain)
            .accessibilityLabel(provider.displayName)
            .modifier(ProviderSectionAccessibilityValue(value: sectionAccessibilityValue))
    }

    @ViewBuilder
    private var sectionContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        ProviderBadge(provider: provider, size: 18)
                        if let url = provider.dashboardURL {
                            Link(destination: url) {
                                Text(provider.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }
                        } else {
                            Text(provider.displayName).font(.headline)
                        }
                    }
                    if let codex = provider as? CodexProvider,
                       !codex.isPrimary,
                       let email = codex.accountEmail {
                        Text(email)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let usage = state.usage, let plan = usage.planName {
                    Text(plan)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            switch state {
            case .loading:
                Text(L("Loading…")).font(.caption).foregroundStyle(.secondary)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .ready(let usage):
                UsageMetersView(
                    providerName: provider.displayName,
                    usage: usage,
                    settings: settings
                )
                subscriptionRenewalRow
            case .stale(let usage, let error, let since):
                UsageMetersView(
                    providerName: provider.displayName,
                    usage: usage,
                    settings: settings
                )
                .opacity(0.55)
                subscriptionRenewalRow
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Stale since \(since.formatted(date: .omitted, time: .shortened))"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var subscriptionRenewalRow: some View {
        if provider.id == "codex" || provider.id.hasPrefix("codex:"),
           let renewal = settings.renewal(for: provider.id) {
            SubscriptionRenewalRow(renewal: renewal)
        }
    }

    private var sectionAccessibilityValue: String? {
        switch state {
        case .stale:
            return L("data is stale")
        case .error:
            return L("error")
        case .loading, .ready:
            return nil
        }
    }
}

struct SubscriptionRenewalRow: View {
    let renewal: SubscriptionRenewal

    var body: some View {
        let next = renewal.nextRenewal(after: Date())
        let dateText = next.formatted(date: .abbreviated, time: .omitted)
        let statusText = renewal.needsReconfirmation ? L("(expected)") : L("(confirmed)")

        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "calendar")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(format: L("Renews %@"), dateText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(renewal.platform.displayName) \(statusText)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("Subscription renewal"))
        .accessibilityValue("\(dateText), \(renewal.platform.displayName), \(statusText)")
    }
}

private struct ProviderSectionAccessibilityValue: ViewModifier {
    let value: String?

    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

struct UsageMetersView: View {
    let providerName: String
    let usage: ProviderUsage
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Group {
            if usage.windows.isEmpty && usage.balance == nil && usage.apiUsage == nil {
                Text(L("No usage data")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(usage.windows, id: \.label) { window in
                WindowMeter(
                    providerName: providerName,
                    window: window,
                    settings: settings
                )
            }
            if let apiUsage = usage.apiUsage {
                APIUsageRows(summary: apiUsage)
            } else if let balance = usage.balance {
                BalanceRow(
                    providerName: providerName,
                    balance: balance,
                    settings: settings
                )
            }
            if let asOf = usage.asOf {
                Text(L("Data as of \(asOf.formatted(date: .omitted, time: .shortened))"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Usage reported by the Claude Console Admin API. These values are kept
/// separate from prepaid credits because the API does not report credit balance.
private struct APIUsageRows: View {
    let summary: APIUsageSummary

    private static let prepaidCreditsURL = URL(string: "https://platform.claude.com/settings/billing")!

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Month to date (UTC)"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            valueRow(label: L("API spending"), value: summary.costUSD.formatted(.currency(code: "USD")))
            valueRow(label: L("Input tokens"), value: summary.inputTokens.formatted())
            valueRow(label: L("Output tokens"), value: summary.outputTokens.formatted())
            valueRow(label: L("Cache read tokens"), value: summary.cacheReadTokens.formatted())
            valueRow(label: L("Cache creation tokens"), value: summary.cacheCreationTokens.formatted())
            valueRow(label: L("Prepaid credits"), value: L("Unavailable via API"))
            Link(L("View prepaid credits"), destination: Self.prepaidCreditsURL)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Text(L("Reporting may be delayed. Priority Tier costs excluded."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func valueRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(value)
                .font(.caption.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct BalanceRow: View {
    let providerName: String
    let balance: BalanceInfo
    @ObservedObject var settings: SettingsStore

    private var isLowBalance: Bool {
        balance.kind == .remaining && balance.remaining < settings.balanceNotificationThreshold
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(balance.kind == .remaining ? L("Balance") : L("Usage")).font(.caption)
                Spacer()
                HStack(spacing: 4) {
                    Text(balance.display)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(balanceColor)
                    if isLowBalance {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                    }
                }
            }
            if balance.kind == .remaining, let used = balance.used {
                Text(L("\(balance.currencySymbol)\(BalanceInfo.format(used)) used all-time"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(balanceAccessibilityLabel)
        .accessibilityValue(balanceAccessibilityValue)
    }

    private var balanceColor: Color {
        switch balance.kind {
        case .spent:
            return .secondary
        case .remaining:
            return isLowBalance ? .orange : .green
        }
    }

    private var balanceAccessibilityLabel: String {
        String(format: L("%@ balance"), providerName)
    }

    private var balanceAccessibilityValue: String {
        var value = balance.accessibilityPhrase
        if isLowBalance {
            value = MenuBarAccessibilitySummary.appendQualifier(value, L("low balance"))
        }
        return value
    }
}

private struct WindowMeter: View {
    let providerName: String
    let window: UsageWindow
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            meter(at: context.date)
        }
    }

    private func meter(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label).font(.caption)
                Spacer()
                HStack(spacing: 4) {
                    Text(settings.countDirection.percentLabel(window.usedPercent))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(color)
                    if let symbol = severity.symbolName {
                        Image(systemName: symbol)
                            .font(.caption2)
                            .foregroundStyle(color)
                            .accessibilityHidden(true)
                    }
                }
            }
            ProgressView(value: progressValue, total: 100)
                .tint(color)
                .accessibilityHidden(true)
            if let reset = window.resetDescription(style: settings.resetTimeStyle, now: now) {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(meterAccessibilityLabel)
        .accessibilityValue(meterAccessibilityValue(at: now))
    }

    private var progressValue: Double {
        settings.countDirection.displayPercent(window.usedPercent)
    }

    private var severity: UsageMeterSeverity {
        UsageMeterSeverity.forUsedPercent(window.usedPercent)
    }

    private var color: Color {
        switch severity {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }

    private var meterAccessibilityLabel: String {
        String(format: L("%@, %@"), providerName, window.label)
    }

    private func meterAccessibilityValue(at now: Date) -> String {
        var value = settings.countDirection.accessibilityPercentPhrase(window.usedPercent)
        if let reset = window.resetDescription(style: settings.resetTimeStyle, now: now) {
            value = "\(value), \(reset)"
        }
        if let qualifier = severity.qualifier {
            value = MenuBarAccessibilitySummary.appendQualifier(value, qualifier)
        }
        return value
    }
}
