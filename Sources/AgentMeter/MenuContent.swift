import SwiftUI
import ServiceManagement

struct MenuContent: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @State private var showingSettings = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var updateMessage: String?

    /// Buy Me a Coffee link. Replace the slug once you create the account.
    private let tipJarURL = URL(string: "https://www.buymeacoffee.com/felixtorres")!

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
                    ProviderSection(name: provider.displayName, state: store.state(for: provider.id))
                }
            }
            Divider()
            footer
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let updateMessage {
                Text(updateMessage).font(.caption).foregroundStyle(.secondary)
            } else if let refreshed = store.lastRefreshed {
                Text("Updated \(refreshed.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Refresh") { store.refresh() }
                Spacer()
                Button("Settings…") { showingSettings = true }
            }
            HStack {
                Button("Check for Updates…") { checkForUpdates() }
                Spacer()
                Link("Support ♥", destination: tipJarURL)
                    .font(.caption)
            }
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            Button("Quit AgentMeter") { NSApp.terminate(nil) }
                .foregroundStyle(.secondary)
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

private struct ProviderSection: View {
    let name: String
    let state: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.headline)
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
                if usage.windows.isEmpty {
                    Text("No usage data").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(usage.windows, id: \.label) { window in
                    WindowMeter(window: window)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label).font(.caption)
                Spacer()
                Text("\(window.usedPercent, specifier: "%.0f")%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(color)
            }
            ProgressView(value: window.usedPercent, total: 100)
                .tint(color)
            if let remaining = window.remainingDescription {
                Text(remaining)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { onDone() }
            }

            Text("Providers").font(.caption).foregroundStyle(.secondary)
            ForEach(store.providers, id: \.id) { provider in
                HStack {
                    Text(provider.displayName)
                    if !provider.isDetected {
                        Text("not detected")
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
            }

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
        }
    }
}
