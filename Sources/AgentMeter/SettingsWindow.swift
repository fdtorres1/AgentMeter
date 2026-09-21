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
    @State private var cliInstallPath: String?
    @State private var cliInstallResultMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle(L("Launch at Login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }
            Section {
                Toggle(L("Enable agent & CLI access"), isOn: $settings.agentAccessEnabled)
                    .onChange(of: settings.agentAccessEnabled) { _, enabled in
                        if enabled {
                            StatusSnapshotWriter.writeIfEnabled(store: store, settings: settings)
                        }
                    }

                cliToolInstallSection
            } footer: {
                Text(L("Writes a machine-readable usage snapshot (never credentials) to Application Support for the agentmeter command-line tool and other local agents."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .onAppear {
            refreshCLIInstallStatus()
        }
    }

    @ViewBuilder
    private var cliToolInstallSection: some View {
        if CLIToolInstaller.isBundledApp {
            Group {
                if let path = cliInstallPath {
                    Text(String(format: L("Command-line tool installed at %@"), path))
                } else {
                    Text(L("Command-line tool not on your PATH."))
                }

                if let cliInstallResultMessage {
                    Text(cliInstallResultMessage)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Button(CLIToolInstaller.isInstalledAtLocalPath()
                ? L("Reinstall Command-Line Tool…")
                : L("Install Command-Line Tool…")) {
                installCLITool()
            }
        } else {
            Text(L("Run from AgentMeter.app to install the command-line tool."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshCLIInstallStatus() {
        cliInstallPath = CLIToolInstaller.detectedInstallPath()
    }

    private func installCLITool() {
        cliInstallResultMessage = nil

        switch CLIToolInstaller.install() {
        case .success:
            refreshCLIInstallStatus()
            let message = L("Installed. Open a new terminal and run agentmeter --help.")
            cliInstallResultMessage = message
            AccessibilityNotification.Announcement(message).post()
        case .failure(_ as CancellationError):
            break
        case .failure(let error):
            let message = String(format: L("Couldn't install the command-line tool: %@"), error.localizedDescription)
            cliInstallResultMessage = message
            AccessibilityNotification.Announcement(message).post()
        }
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

                    if provider.id == "codex" {
                        CodexAccountsSection(store: store, settings: settings)
                    }
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

private struct CodexAccountsSection: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @State private var showingAddForm = false
    @State private var draftLabel = ""
    @State private var draftHomePath = ""
    @State private var addFormError: String?

    var body: some View {
        Group {
            Text(L("Codex accounts"))
                .font(.caption)
                .foregroundStyle(.secondary)

            primaryAccountRow

            ForEach(settings.codexExtraAccounts) { account in
                extraAccountRow(account)
            }

            if showingAddForm {
                addAccountForm
            } else {
                Button(L("Add account…")) {
                    draftLabel = ""
                    draftHomePath = CodexAccountConfig.suggestedHomePath(for: "")
                    showingAddForm = true
                    addFormError = nil
                }
            }

            Text(L("OpenAI doesn't publish subscription renewal dates, so confirm yours on the platform that bills you — ChatGPT, Apple, or Google Play. Renewal dates are separate from usage-limit resets."))
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(L("Removing only forgets the path; it does not sign out."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var primaryAccountRow: some View {
        let status = codexAccountStatus(providerID: "codex")
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Default (~/.codex)"))
                        .font(.caption)
                    Text("~/.codex")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(format: L("Default Codex account, %@"), status))

            CodexSubscriptionSettings(providerID: "codex", settings: settings)
        }
    }

    private func extraAccountRow(_ account: CodexAccountConfig) -> some View {
        let providerID = "codex:\(account.id.uuidString)"
        let status = codexAccountStatus(providerID: providerID)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.label)
                        .font(.caption)
                    Text(account.codexHomePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                Button(L("Remove")) {
                    settings.removeCodexAccount(id: account.id)
                }
                .font(.caption)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(format: L("%@, %@, %@"), account.label, account.codexHomePath, status))

            CodexSubscriptionSettings(providerID: providerID, settings: settings)
        }
    }

    private func codexAccountStatus(providerID: String) -> String {
        if let state = store.states[providerID] {
            switch state {
            case .error(let message):
                return message
            case .loading:
                return L("Loading…")
            case .ready(let usage), .stale(let usage, _, _):
                if let email = CodexAccountCache.shared.lastEmail(for: providerID) {
                    let plan = usage.planName ?? CodexPlan.displayName(
                        CodexAccountCache.shared.lastPlanType(for: providerID)
                    )
                    if let plan {
                        return "\(email) · \(plan)"
                    }
                    return email
                }
                return L("Not signed in")
            }
        }
        if let email = CodexAccountCache.shared.lastEmail(for: providerID) {
            let plan = CodexPlan.displayName(CodexAccountCache.shared.lastPlanType(for: providerID))
            if let plan { return "\(email) · \(plan)" }
            return email
        }
        return L("Not signed in")
    }

    private var addAccountForm: some View {
        let loginCommand = CodexAccountConfig.loginCommand(homePath: draftHomePath)
        return VStack(alignment: .leading, spacing: 8) {
            TextField(L("Label"), text: $draftLabel)
                .onChange(of: draftLabel) { _, newValue in
                    if draftHomePath.isEmpty || draftHomePath.hasPrefix("~/.codex-") {
                        draftHomePath = CodexAccountConfig.suggestedHomePath(for: newValue)
                    }
                }
            TextField(L("Home path"), text: $draftHomePath)
                .font(.caption.monospaced())

            Text(loginCommand)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))

            Button(L("Copy login command")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(loginCommand, forType: .string)
                AccessibilityNotification.Announcement(L("Login command copied")).post()
            }
            .font(.caption)
            .accessibilityLabel(L("Copy login command"))
            .accessibilityHint(L("Copies the Terminal command to sign in this Codex account"))

            Text(L("Run this in Terminal to sign in that account. AgentMeter never handles your login or tokens — the Codex CLI does."))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let addFormError {
                Text(addFormError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            HStack {
                Button(L("Save")) { saveAccount() }
                    .disabled(!isAddFormValid)
                Button(L("Cancel"), role: .cancel) {
                    showingAddForm = false
                    addFormError = nil
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var isAddFormValid: Bool {
        let label = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = draftHomePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !label.isEmpty && !path.isEmpty && path != "~/.codex"
    }

    private func saveAccount() {
        let label = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = draftHomePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else {
            addFormError = L("Label is required")
            return
        }
        guard !path.isEmpty else {
            addFormError = L("Home path is required")
            return
        }
        guard path != "~/.codex" else {
            addFormError = L("Choose a path other than ~/.codex")
            return
        }
        settings.addCodexAccount(CodexAccountConfig(label: label, codexHomePath: path))
        showingAddForm = false
        addFormError = nil
    }
}

private struct CodexSubscriptionSettings: View {
    let providerID: String
    @ObservedObject var settings: SettingsStore

    private var isTracking: Bool {
        settings.renewal(for: providerID) != nil
    }

    var body: some View {
        DisclosureGroup(L("Subscription")) {
            Toggle(L("Track renewal date"), isOn: Binding(
                get: { isTracking },
                set: { enabled in
                    if enabled {
                        let today = Calendar.current.startOfDay(for: Date())
                        settings.setRenewal(
                            SubscriptionRenewal(
                                anchorDate: today,
                                platform: .chatgpt,
                                confirmedAt: nil,
                                remindDaysBefore: 3
                            ),
                            for: providerID
                        )
                    } else {
                        settings.removeRenewal(for: providerID)
                    }
                }
            ))

            if let renewal = settings.renewal(for: providerID) {
                subscriptionForm(renewal)
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func subscriptionForm(_ renewal: SubscriptionRenewal) -> some View {
        DatePicker(
            L("Renews on"),
            selection: anchorDateBinding,
            displayedComponents: .date
        )
        Picker(L("Billed through"), selection: platformBinding) {
            ForEach(SubscriptionRenewal.Platform.allCases, id: \.self) { platform in
                Text(platform.displayName).tag(platform)
            }
        }
        Picker(L("Remind me"), selection: remindDaysBinding) {
            Text(L("Off")).tag(0)
            Text(L("1 day before")).tag(1)
            Text(L("3 days before")).tag(3)
            Text(L("7 days before")).tag(7)
        }
        Button(L("I confirmed this date today")) {
            guard var updated = settings.renewal(for: providerID) else { return }
            updated.confirmedAt = Date()
            settings.setRenewal(updated, for: providerID)
        }
        .help(L("Marks today as the date you verified this renewal on your billing platform."))

        if let confirmedAt = renewal.confirmedAt {
            Text(String(
                format: L("Last confirmed %@"),
                confirmedAt.formatted(date: .abbreviated, time: .omitted)
            ))
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else {
            Text(L("Not confirmed yet — check the platform that bills you."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var anchorDateBinding: Binding<Date> {
        Binding(
            get: { settings.renewal(for: providerID)?.anchorDate ?? Date() },
            set: { newValue in
                guard var renewal = settings.renewal(for: providerID) else { return }
                renewal.anchorDate = newValue
                settings.setRenewal(renewal, for: providerID)
            }
        )
    }

    private var platformBinding: Binding<SubscriptionRenewal.Platform> {
        Binding(
            get: { settings.renewal(for: providerID)?.platform ?? .chatgpt },
            set: { newValue in
                guard var renewal = settings.renewal(for: providerID) else { return }
                renewal.platform = newValue
                settings.setRenewal(renewal, for: providerID)
            }
        )
    }

    private var remindDaysBinding: Binding<Int> {
        Binding(
            get: { settings.renewal(for: providerID)?.remindDaysBefore ?? 0 },
            set: { newValue in
                guard var renewal = settings.renewal(for: providerID) else { return }
                renewal.remindDaysBefore = newValue
                settings.setRenewal(renewal, for: providerID)
            }
        )
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
