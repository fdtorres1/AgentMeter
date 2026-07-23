import SwiftUI
import ServiceManagement

struct SettingsRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store, settings: settings)
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
            ProvidersSettingsTab(store: store, settings: settings)
                .tabItem {
                    Label("Providers", systemImage: "list.bullet")
                }
            DisplaySettingsTab(settings: settings)
                .tabItem {
                    Label("Display", systemImage: "eye")
                }
            AlertsSettingsTab(store: store, settings: settings)
                .tabItem {
                    Label("Alerts", systemImage: "bell")
                }
        }
        .frame(width: 500, height: 420)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
            Section {
                Picker("Refresh interval", selection: Binding(
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
                .pickerStyle(.menu)
            }
        }
        .formStyle(.grouped)
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
}

private struct ProvidersSettingsTab: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            ForEach(store.providers, id: \.id) { provider in
                Section {
                    Picker("Mode", selection: Binding(
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

                    if settings.mode(for: provider.id) != .off {
                        Toggle("Show in menu bar", isOn: Binding(
                            get: { settings.showsInMenuBar(provider.id) },
                            set: { settings.setShowsInMenuBar($0, for: provider.id) }
                        ))
                    }

                    ProviderCredentialSection(provider: provider, store: store)
                } header: {
                    HStack(spacing: 6) {
                        ProviderBadge(provider: provider, size: 18)
                        Text(provider.displayName)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderCredentialSection: View {
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
            LabeledContent("Status", value: provider.isDetected ? "Detected" : "Not detected")
        case .apiKey(let keyURL):
            if hasKey {
                LabeledContent("API key") {
                    HStack {
                        Text("Saved")
                        Button("Remove") { removeKey() }
                    }
                }
            } else {
                SecureField("API key", text: $draftKey)
                HStack {
                    Button("Save") { saveKey() }
                        .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    if let url = URL(string: keyURL) {
                        Link("Get key", destination: url)
                    }
                }
            }
        case .oauth:
            Group {
                if hasKey {
                    LabeledContent("Status") {
                        HStack {
                            Text("Connected")
                            Button("Disconnect") { removeKey() }
                        }
                    }
                } else {
                    Button("Connect…") { OpenRouterAuthFlow.shared.start() }
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

private struct DisplaySettingsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker("Count direction", selection: $settings.countDirection) {
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
            }
        }
        .formStyle(.grouped)
    }
}

private struct AlertsSettingsTab: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    private var countsDown: Bool { settings.countDirection == .remaining }

    var body: some View {
        Form {
            Section {
                Toggle("Alert when usage crosses threshold", isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            store.notificationManager.requestAuthorizationIfNeeded()
                        }
                    }

                // Thresholds are stored as used-percent; only the labels adapt
                // to the count direction, so the alert fires at the same real
                // usage level in either display mode.
                Picker(
                    countsDown ? "Alert when remaining falls below" : "Alert when usage reaches",
                    selection: $settings.notificationThreshold
                ) {
                    ForEach(SettingsStore.notificationThresholdOptions, id: \.self) { value in
                        Text(countsDown ? "\(Int(100 - value))% left" : "\(Int(value))%").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.notificationsEnabled)

                Picker("Balance alert below", selection: $settings.balanceNotificationThreshold) {
                    ForEach(SettingsStore.balanceThresholdOptions, id: \.self) { value in
                        Text("$\(Int(value))").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.notificationsEnabled)
            } footer: {
                Text(countsDown
                    ? "One notification per limit window, re-armed when the window resets. \"20% left\" is the same alert as \"80% used\" — it follows your Display setting."
                    : "One notification per limit window, re-armed when the window resets. Balance alerts apply to pay-as-you-go providers.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
