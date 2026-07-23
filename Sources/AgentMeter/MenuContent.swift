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
            }
            HStack {
                SettingsLink {
                    Text(L("Settings…"))
                }
                .buttonStyle(.plain)
                .font(.caption)
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
                Spacer()
                Link(destination: tipJarURL) {
                    Text(L("Support ♥"))
                }
                    .font(.caption)
                Spacer()
                Button(L("Quit")) { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProviderBadge(provider: provider, size: 18)
                if let url = provider.dashboardURL {
                    Button(provider.displayName) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.plain)
                    .font(.headline)
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
                UsageMetersView(usage: usage, settings: settings)
            case .stale(let usage, let error, let since):
                UsageMetersView(usage: usage, settings: settings)
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
}

private struct UsageMetersView: View {
    let usage: ProviderUsage
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Group {
            if usage.windows.isEmpty && usage.balance == nil {
                Text(L("No usage data")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(usage.windows, id: \.label) { window in
                WindowMeter(window: window, settings: settings)
            }
            if let balance = usage.balance {
                HStack {
                    Text(balance.kind == .remaining ? L("Balance") : L("Usage")).font(.caption)
                    Spacer()
                    Text(balance.display)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(
                            balance.kind == .spent
                                ? Color.secondary
                                : (balance.remaining > 5 ? Color.green : Color.orange)
                        )
                }
                if balance.kind == .remaining, let used = balance.used {
                    Text(L("\(balance.currencySymbol)\(BalanceInfo.format(used)) used all-time"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let asOf = usage.asOf {
                Text(L("Data as of \(asOf.formatted(date: .omitted, time: .shortened))"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct WindowMeter: View {
    let window: UsageWindow
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label).font(.caption)
                Spacer()
                Text(settings.countDirection.percentLabel(window.usedPercent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressView(value: progressValue, total: 100)
                .tint(color)
            if let reset = window.resetDescription(style: settings.resetTimeStyle) {
                Text(reset)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressValue: Double {
        settings.countDirection.displayPercent(window.usedPercent)
    }

    private var color: Color {
        switch window.usedPercent {
        case ..<60: return .green
        case ..<85: return .yellow
        default: return .red
        }
    }
}
