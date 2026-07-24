import SwiftUI
import ServiceManagement

struct SettingsRootView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store, settings: settings)
                .tabItem {
                    Label(L("General"), systemImage: "gearshape")
                }
            ProvidersSettingsTab(store: store, settings: settings)
                .tabItem {
                    Label(L("Providers"), systemImage: "list.bullet")
                }
            DisplaySettingsTab(settings: settings)
                .tabItem {
                    Label(L("Display"), systemImage: "eye")
                }
            AlertsSettingsTab(store: store, settings: settings)
                .tabItem {
                    Label(L("Alerts"), systemImage: "bell")
                }
        }
        .frame(width: 500, height: 420)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var diagnosticsCopied = false

    var body: some View {
        Form {
            Section {
                Toggle(L("Launch at Login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
            Section {
                Picker(L("Refresh interval"), selection: Binding(
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
            Section {
                Button {
                    copyDiagnostics()
                } label: {
                    if diagnosticsCopied {
                        Label(L("Copied"), systemImage: "checkmark")
                    } else {
                        Text(L("Copy Diagnostics"))
                    }
                }
            } footer: {
                Text(L("Copies redacted troubleshooting info to the clipboard — never includes keys or tokens."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button(L("About AgentMeter")) {
                    openWindow(id: "about")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func copyDiagnostics() {
        let report = Diagnostics.report(store: store, settings: settings)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        diagnosticsCopied = true
        AccessibilityNotification.Announcement(L("Diagnostics copied")).post()
        Task {
            try? await Task.sleep(for: .seconds(2))
            diagnosticsCopied = false
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
}

private struct ProvidersSettingsTab: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            ForEach(store.providers, id: \.id) { provider in
                Section {
                    Picker(L("Mode"), selection: Binding(
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
                        Toggle(L("Show in menu bar"), isOn: Binding(
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
    @ObservedObject private var openRouterAuth = OpenRouterAuthFlow.shared
    @State private var draftKey = ""
    @State private var hasKey: Bool
    @State private var assessmentGeneration = 0

    init(provider: any UsageProvider, store: UsageStore) {
        self.provider = provider
        self.store = store
        _hasKey = State(initialValue: KeychainStore.exists(provider.keychainAccount))
    }

    var body: some View {
        switch provider.authKind {
        case .localCredentials:
            LabeledContent(L("Status"), value: provider.isDetected ? L("Detected") : L("Not detected"))
        case .apiKey(let keyURL):
            Group {
                if let help = provider.credentialHelpText {
                    Text(help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if hasKey {
                    LabeledContent(provider.apiKeyPlaceholder) {
                        HStack {
                            Text(L("Saved"))
                            Button(L("Remove")) { removeKey() }
                        }
                    }
                    CredentialAssessmentView(
                        provider: provider,
                        assessmentGeneration: assessmentGeneration
                    )
                } else {
                    SecureField(provider.apiKeyPlaceholder, text: $draftKey)
                    HStack {
                        Button(L("Save")) { saveKey() }
                            .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let url = URL(string: keyURL) {
                            Link(L("Get key"), destination: url)
                        }
                    }
                }
            }
        case .oauth:
            Group {
                if hasKey {
                    LabeledContent(L("Status")) {
                        HStack {
                            Text(L("Connected"))
                            Button(L("Disconnect")) { removeKey() }
                        }
                    }
                    CredentialAssessmentView(
                        provider: provider,
                        assessmentGeneration: assessmentGeneration
                    )
                } else {
                    HStack {
                        Button(L("Connect…")) { OpenRouterAuthFlow.shared.start() }
                            .disabled(openRouterAuth.status == .connecting)
                        if openRouterAuth.status == .connecting {
                            ProgressView().controlSize(.small)
                            Text(L("Waiting for browser authorization…"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if case .failed(let message) = openRouterAuth.status {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    SecureField(L("Or paste an API key"), text: $draftKey)
                    HStack {
                        Button(L("Save")) { saveKey() }
                            .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let url = provider.dashboardURL {
                            Link(L("Get key"), destination: url)
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .providerCredentialsChanged)) { _ in
                let connected = KeychainStore.exists(provider.keychainAccount)
                if connected && !hasKey {
                    assessmentGeneration += 1
                }
                hasKey = connected
            }
            .onChange(of: openRouterAuth.status) { _, newStatus in
                switch newStatus {
                case .connected:
                    AccessibilityNotification.Announcement(L("OpenRouter connected")).post()
                case .failed:
                    AccessibilityNotification.Announcement(L("Connection failed")).post()
                case .idle, .connecting:
                    break
                }
            }
        }
    }

    private func saveKey() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        KeychainStore.set(key, account: provider.keychainAccount)
        draftKey = ""
        hasKey = true
        assessmentGeneration += 1
        store.refresh()
        AccessibilityNotification.Announcement(L("API key saved")).post()
    }

    private func removeKey() {
        KeychainStore.delete(provider.keychainAccount)
        hasKey = false
        store.refresh()
        AccessibilityNotification.Announcement(L("API key removed")).post()
    }
}

private struct CredentialAssessmentView: View {
    let provider: any UsageProvider
    let assessmentGeneration: Int
    @State private var assessment: CredentialAssessment?
    @State private var isAssessing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isAssessing {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(L("Checking key…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let assessment {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(assessment.keyTypeLabel)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .help(assessment.summary)
                    Text(assessment.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    String(
                        format: L("Key type: %@. %@"),
                        assessment.keyTypeLabel,
                        assessment.summary
                    )
                )

                DisclosureGroup(L("About this key")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(assessment.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let hint = assessment.upgradeHint {
                            Text(hint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if let url = assessment.manageURL {
                            Link(L("Manage keys"), destination: url)
                                .font(.caption)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .font(.caption)
            }
        }
        .task(id: assessmentGeneration) {
            isAssessing = true
            assessment = await provider.assessCredential()
            isAssessing = false
        }
    }
}

private struct DisplaySettingsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Picker(L("Count direction"), selection: $settings.countDirection) {
                    Text(L("% used")).tag(CountDirection.used)
                    Text(L("% left")).tag(CountDirection.remaining)
                }
                .pickerStyle(.segmented)

                Picker(L("Reset times"), selection: $settings.resetTimeStyle) {
                    Text(L("Relative")).tag(ResetTimeStyle.relative)
                    Text(L("Exact")).tag(ResetTimeStyle.absolute)
                }
                .pickerStyle(.segmented)

                Picker(L("Menu bar style"), selection: $settings.menuBarStyle) {
                    Text(L("Full")).tag(MenuBarStyle.full)
                    Text(L("Compact (worst only)")).tag(MenuBarStyle.compact)
                    Text(L("Icon only")).tag(MenuBarStyle.icon)
                }
                .pickerStyle(.segmented)
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
                Toggle(L("Alert when usage crosses threshold"), isOn: $settings.notificationsEnabled)
                    .onChange(of: settings.notificationsEnabled) { _, enabled in
                        if enabled {
                            store.notificationManager.requestAuthorizationIfNeeded()
                        }
                    }

                // Thresholds are stored as used-percent; only the labels adapt
                // to the count direction, so the alert fires at the same real
                // usage level in either display mode.
                Picker(
                    countsDown ? L("Alert when remaining falls below") : L("Alert when usage reaches"),
                    selection: $settings.notificationThreshold
                ) {
                    ForEach(SettingsStore.notificationThresholdOptions, id: \.self) { value in
                        Text(countsDown
                            ? L("\(Int(100 - value))% left")
                            : L("\(Int(value))%")
                        ).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.notificationsEnabled)
                .modifier(DisabledControlAccessibilityHint(
                    isDisabled: !settings.notificationsEnabled,
                    hint: L("Enable notifications to change this.")
                ))

                Picker(L("Balance alert below"), selection: $settings.balanceNotificationThreshold) {
                    ForEach(SettingsStore.balanceThresholdOptions, id: \.self) { value in
                        Text("$\(Int(value))").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!settings.notificationsEnabled)
                .modifier(DisabledControlAccessibilityHint(
                    isDisabled: !settings.notificationsEnabled,
                    hint: L("Enable notifications to change this.")
                ))
            } footer: {
                Text(countsDown
                    ? L("One notification per limit window, re-armed when the window resets. \"20% left\" is the same alert as \"80% used\" — it follows your Display setting.")
                    : L("One notification per limit window, re-armed when the window resets. Balance alerts apply to pay-as-you-go providers.")
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DisabledControlAccessibilityHint: ViewModifier {
    let isDisabled: Bool
    let hint: String

    func body(content: Content) -> some View {
        if isDisabled {
            content.accessibilityHint(hint)
        } else {
            content
        }
    }
}
