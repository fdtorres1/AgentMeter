import SwiftUI
import ServiceManagement

struct MenuContent: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @State private var showingSettings = false
    @State private var updateMessage: String?

    private let tipJarURL = URL(string: "https://www.buymeacoffee.com/fdtorres")!

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showingSettings {
                SettingsView(store: store, settings: settings, onDone: { showingSettings = false })
            } else {
                usageView
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private var usageView: some View {
        VStack(alignment: .leading, spacing: 12) {
            let visible = store.visibleProviders
            if visible.isEmpty {
                Text("No providers enabled. Open Settings to turn some on.")
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
                if let updateMessage {
                    Text(updateMessage).font(.caption).foregroundStyle(.secondary)
                } else if let refreshed = store.lastRefreshed {
                    Text("Updated \(refreshed.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") { store.refresh() }
                    .font(.caption)
            }
            HStack {
                Button("Settings…") { showingSettings = true }
                    .buttonStyle(.plain)
                    .font(.caption)
                Spacer()
                Button("Check for Updates…") { checkForUpdates() }
                    .buttonStyle(.plain)
                    .font(.caption)
                Spacer()
                Link("Support ♥", destination: tipJarURL)
                    .font(.caption)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.caption)
            }
        }
    }

    private func checkForUpdates() {
        updateMessage = "Checking for updates…"
        Task {
            do {
                let result = try await UpdateChecker.check()
                if result.isNewer {
                    updateMessage = "Version \(result.latestVersion) available"
                    NSWorkspace.shared.open(result.url)
                } else {
                    updateMessage = "You're up to date (\(UpdateChecker.currentVersion))"
                }
            } catch {
                updateMessage = "Update check failed"
            }
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
                if case .ready(let usage) = state, let plan = usage.planName {
                    Text(plan)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            switch state {
            case .loading:
                Text("Loading…").font(.caption).foregroundStyle(.secondary)
            case .error(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .ready(let usage):
                if usage.windows.isEmpty && usage.balance == nil {
                    Text("No usage data").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(usage.windows, id: \.label) { window in
                    WindowMeter(window: window, settings: settings)
                }
                if let balance = usage.balance {
                    HStack {
                        Text("Balance").font(.caption)
                        Spacer()
                        Text(balance.display)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(balance.remaining > 5 ? Color.green : Color.orange)
                    }
                    if let used = balance.used {
                        Text("\(balance.currencySymbol)\(BalanceInfo.format(used)) used all-time")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                if let asOf = usage.asOf {
                    Text("Data as of \(asOf.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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

private struct SettingsView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    let onDone: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { onDone() }
            }

            Text("General").font(.caption).foregroundStyle(.secondary)
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }

            Divider()
            Text("Providers").font(.caption).foregroundStyle(.secondary)
            ForEach(store.providers, id: \.id) { provider in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(provider.displayName)
                        if !provider.isDetected {
                            Text(providerHint(provider))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Picker("", selection: Binding(
                            get: { settings.mode(for: provider.id) },
                            set: { newValue in
                                settings.setMode(newValue, for: provider.id)
                                store.refresh()
                            }
                        )) {
                            ForEach(ProviderMode.allCases) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                        .labelsHidden()
                    }
                    if settings.mode(for: provider.id) != .off {
                        Toggle("Show in menu bar", isOn: Binding(
                            get: { settings.showsInMenuBar(provider.id) },
                            set: { settings.setShowsInMenuBar($0, for: provider.id) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption2)
                    }
                    ProviderCredentialRow(provider: provider, store: store)
                }
            }

            Divider()
            Text("Display").font(.caption).foregroundStyle(.secondary)
            Picker("Count", selection: $settings.countDirection) {
                Text("% used").tag(CountDirection.used)
                Text("% left").tag(CountDirection.remaining)
            }
            .pickerStyle(.segmented)
            Picker("Reset times", selection: $settings.resetTimeStyle) {
                Text("Relative").tag(ResetTimeStyle.relative)
                Text("Exact").tag(ResetTimeStyle.absolute)
            }
            .pickerStyle(.segmented)
            Toggle("Compact menu bar (worst only)", isOn: $settings.compactMenuBar)
                .toggleStyle(.checkbox)
                .font(.caption)

            Divider()
            Text("Refresh interval").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { settings.refreshInterval },
                set: { newValue in
                    settings.refreshInterval = newValue
                    store.rescheduleTimer()
                }
            )) {
                ForEach(SettingsStore.refreshOptions, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()
            Text("Notifications").font(.caption).foregroundStyle(.secondary)
            Toggle("Alert when usage crosses threshold", isOn: $settings.notificationsEnabled)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: settings.notificationsEnabled) { _, enabled in
                    if enabled {
                        store.notificationManager.requestAuthorizationIfNeeded()
                    }
                }
            Picker("", selection: $settings.notificationThreshold) {
                ForEach(SettingsStore.notificationThresholdOptions, id: \.self) { value in
                    Text("\(Int(value))%").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!settings.notificationsEnabled)
            Picker("Balance alert below", selection: $settings.balanceNotificationThreshold) {
                ForEach(SettingsStore.balanceThresholdOptions, id: \.self) { value in
                    Text("$\(Int(value))").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!settings.notificationsEnabled)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func providerHint(_ provider: any UsageProvider) -> String {
        switch provider.authKind {
        case .localCredentials: return "not detected"
        case .apiKey: return "no key set"
        case .oauth: return "not connected"
        }
    }
}

/// Credential management for API-key and OAuth providers; empty for
/// local-credential providers.
private struct ProviderCredentialRow: View {
    let provider: any UsageProvider
    @ObservedObject var store: UsageStore
    @State private var draftKey = ""
    @State private var hasKey: Bool

    init(provider: any UsageProvider, store: UsageStore) {
        self.provider = provider
        self.store = store
        _hasKey = State(initialValue: KeychainStore.exists(provider.keychainAccount))
    }

    var body: some View {
        switch provider.authKind {
        case .localCredentials:
            EmptyView()
        case .apiKey(let keyURL):
            HStack(spacing: 6) {
                if hasKey {
                    Text("Key saved").font(.caption2).foregroundStyle(.secondary)
                    Button("Remove") { removeKey() }
                        .font(.caption2)
                } else {
                    SecureField("Paste API key", text: $draftKey)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    Button("Save") { saveKey() }
                        .font(.caption2)
                        .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let url = URL(string: keyURL) {
                        Link("Get key", destination: url).font(.caption2)
                    }
                }
            }
        case .oauth:
            HStack(spacing: 6) {
                if hasKey {
                    Text("Connected").font(.caption2).foregroundStyle(.secondary)
                    Button("Disconnect") { removeKey() }
                        .font(.caption2)
                } else {
                    Button("Connect…") { OpenRouterAuthFlow.shared.start() }
                        .font(.caption2)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .providerCredentialsChanged)) { _ in
                hasKey = KeychainStore.exists(provider.keychainAccount)
            }
        }
    }

    private func saveKey() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        KeychainStore.set(key, account: provider.keychainAccount)
        draftKey = ""
        hasKey = true
        store.refresh()
    }

    private func removeKey() {
        KeychainStore.delete(provider.keychainAccount)
        hasKey = false
        store.refresh()
    }
}
