import SwiftUI

struct MenuContent: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    private let tipJarURL = URL(string: "https://www.buymeacoffee.com/fdtorres")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            usageView
        }
        .padding(14)
        .frame(width: 320)
    }

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Divider()
            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let refreshed = store.lastRefreshed {
                    Text(L("Updated \(refreshed.formatted(date: .omitted, time: .shortened))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    store.refresh()
                } label: {
                    Label(L("Refresh"), systemImage: "arrow.clockwise")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .help(L("Refresh"))
                .accessibilityLabel(L("Refresh"))
            }
            HStack {
                SettingsLink {
                    Text(L("Settings…"))
                }
                .buttonStyle(.plain)
                .font(.caption)
                .help(L("Settings…"))
                .accessibilityLabel(L("Settings…"))
                .simultaneousGesture(TapGesture().onEnded {
                    NSApp.activate(ignoringOtherApps: true)
                    Self.closeMenuBarWindow()
                })
                Spacer()
                Button(L("Check for Updates…")) {
                    Self.closeMenuBarWindow()
                    Updater.shared.checkForUpdates()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .help(L("Check for Updates…"))
                .accessibilityLabel(L("Check for Updates…"))
                Spacer()
                Link(destination: tipJarURL) {
                    Text(L("Support ♥"))
                }
                .font(.caption)
                .help(L("Support ♥"))
                .accessibilityLabel(L("Support ♥"))
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .help(L("Quit"))
                    .accessibilityLabel(L("Quit"))
            }
        }
    }

    /// MenuBarExtra's window doesn't auto-dismiss when another window opens;
    /// close it explicitly so Settings doesn't appear behind the dropdown.
    private static func closeMenuBarWindow() {
        for window in NSApp.windows where window.className.contains("MenuBarExtraWindow") {
            window.close()
        }
    }

}

private struct ProviderSection: View {
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
            HStack {
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
            case .stale(let usage, let error, let since):
                UsageMetersView(
                    providerName: provider.displayName,
                    usage: usage,
                    settings: settings
                )
                .opacity(0.55)
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

private struct UsageMetersView: View {
    let providerName: String
    let usage: ProviderUsage
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Group {
            if usage.windows.isEmpty && usage.balance == nil {
                Text(L("No usage data")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(usage.windows, id: \.label) { window in
                WindowMeter(
                    providerName: providerName,
                    window: window,
                    settings: settings
                )
            }
            if let balance = usage.balance {
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
            if let reset = window.resetDescription(style: settings.resetTimeStyle) {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(meterAccessibilityLabel)
        .accessibilityValue(meterAccessibilityValue)
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

    private var meterAccessibilityValue: String {
        var value = settings.countDirection.accessibilityPercentPhrase(window.usedPercent)
        if let reset = window.resetDescription(style: settings.resetTimeStyle) {
            value = "\(value), \(reset)"
        }
        if let qualifier = severity.qualifier {
            value = MenuBarAccessibilitySummary.appendQualifier(value, qualifier)
        }
        return value
    }
}
