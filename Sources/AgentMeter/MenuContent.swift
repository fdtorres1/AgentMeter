import SwiftUI

struct MenuContent: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

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
            ProviderUsageSections(store: store, settings: settings)
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
                Button {
                    openUsageDetails()
                } label: {
                    Text(L("Usage Details"))
                }
                .buttonStyle(.plain)
                .font(.caption)
                .keyboardShortcut("d", modifiers: [.command])
                .help(L("Usage Details"))
                .accessibilityLabel(L("Usage Details"))
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

    private func openUsageDetails() {
        Self.closeMenuBarWindow()
        openWindow(id: "usage-details")
        NSApp.activate(ignoringOtherApps: true)
    }

    /// MenuBarExtra's window doesn't auto-dismiss when another window opens;
    /// close it explicitly so Settings doesn't appear behind the dropdown.
    private static func closeMenuBarWindow() {
        for window in NSApp.windows where window.className.contains("MenuBarExtraWindow") {
            window.close()
        }
    }
}
