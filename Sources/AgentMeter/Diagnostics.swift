import Foundation

@MainActor
enum Diagnostics {
    static func report(store: UsageStore, settings: SettingsStore) -> String {
        var lines: [String] = []
        lines.append("# AgentMeter Diagnostics")
        lines.append("")
        lines.append("## Environment")
        lines.append("- Version: \(appVersion)")
        lines.append("- macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("- Locale: \(Locale.current.identifier)")
        lines.append("- Menu bar style: \(settings.menuBarStyle.rawValue)")
        lines.append("- Refresh interval: \(Int(settings.refreshInterval))s")
        lines.append("- Count direction: \(settings.countDirection.rawValue)")
        lines.append("- Notifications: \(settings.notificationsEnabled ? "on" : "off")")
        lines.append("- Usage threshold: \(Int(settings.notificationThreshold))%")
        lines.append("- Balance threshold: $\(BalanceInfo.format(settings.balanceNotificationThreshold))")
        lines.append("")
        lines.append("## Providers")
        for provider in store.providers {
            lines.append(formatProvider(
                id: provider.id,
                displayName: provider.displayName,
                detected: provider.isDetected,
                authKindName: authKindCaseName(provider.authKind),
                mode: settings.mode(for: provider.id),
                showsInMenuBar: settings.showsInMenuBar(provider.id),
                state: store.state(for: provider.id)
            ))
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    nonisolated static func formatProvider(
        id: String,
        displayName: String,
        detected: Bool,
        authKindName: String,
        mode: ProviderMode,
        showsInMenuBar: Bool,
        state: ProviderState
    ) -> String {
        var lines: [String] = []
        lines.append("### \(displayName) (\(id))")
        lines.append("- Mode: \(mode.rawValue)")
        lines.append("- Detected: \(detected ? "yes" : "no")")
        lines.append("- Auth: \(authKindName)")
        lines.append("- Shows in menu bar: \(showsInMenuBar ? "yes" : "no")")
        lines.append("- State: \(stateSummary(state))")
        return lines.joined(separator: "\n")
    }

    nonisolated private static func authKindCaseName(_ kind: ProviderAuthKind) -> String {
        switch kind {
        case .localCredentials: return "localCredentials"
        case .apiKey: return "apiKey"
        case .oauth: return "oauth"
        }
    }

    nonisolated private static func stateSummary(_ state: ProviderState) -> String {
        switch state {
        case .loading:
            return "loading"
        case .error(let message):
            return "error — \(message)"
        case .ready(let usage), .stale(let usage, _, _):
            var parts: [String] = []
            for window in usage.windows {
                parts.append("\(window.label): \(Int(window.usedPercent.rounded()))% used")
            }
            if let balance = usage.balance {
                parts.append("balance: \(balance.currencySymbol)\(BalanceInfo.format(balance.remaining)) left")
            }
            if let asOf = usage.asOf {
                let formatter = Date.FormatStyle().hour().minute().second()
                parts.append("as of \(asOf.formatted(formatter))")
            }
            if parts.isEmpty {
                parts.append("no usage data")
            }
            var summary = parts.joined(separator: "; ")
            if case .stale(_, let error, let since) = state {
                let timeFormatter = Date.FormatStyle().hour().minute()
                summary += "; stale since \(since.formatted(timeFormatter)); error: \(error)"
            }
            return summary
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
