import SwiftUI

@main
struct AgentMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var store: UsageStore

    init() {
        let settings = SettingsStore()
        let store = UsageStore(settings: settings)
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: store)
        appDelegate.configure(settings: settings)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store, settings: settings)
        } label: {
            MenuBarLabel(store: store, settings: settings)
        }
        .menuBarExtraStyle(.window)

        Window(L("Usage Details"), id: "usage-details") {
            UsageDetailsView(store: store, settings: settings)
        }
        .defaultSize(width: 360, height: 500)

        Window("About AgentMeter", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsRootView(store: store, settings: settings)
        }
    }
}

/// The menu bar label is the only view guaranteed to exist for the app's whole
/// lifetime, so it also hosts the observer that opens the Usage Details window
/// for agentmeter://details (MenuContent only exists while the dropdown is open).
private struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if settings.menuBarStyle == .icon {
                Image(nsImage: MenuBarTitleRenderer.iconImage(
                    severity: store.worstMenuBarSeverity,
                    accessibilityDescription: store.menuBarAccessibilityDescription
                ))
            } else {
                Image(nsImage: MenuBarTitleRenderer.image(
                    entries: store.menuBarEntries,
                    accessibilityDescription: store.menuBarAccessibilityDescription
                ))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .agentMeterOpenUsageDetails)) { _ in
            openWindow(id: "usage-details")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

extension Notification.Name {
    /// Posted when a provider credential changes (e.g. OAuth connect finished),
    /// so usage refreshes without waiting for the next timer tick.
    static let providerCredentialsChanged = Notification.Name("providerCredentialsChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var settings: SettingsStore?

    func configure(settings: SettingsStore) {
        self.settings = settings
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon even when run unbundled via swift run.
        NSApp.setActivationPolicy(.accessory)
    }

    /// URL-scheme callbacks (agentmeter://...) arrive here; MenuBarExtra views
    /// may not exist at that moment, so this cannot live in onOpenURL.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for url in urls {
                if OpenRouterAuthFlow.shared.handleCallback(url, onComplete: { result in
                    if case .success = result {
                        NotificationCenter.default.post(name: .providerCredentialsChanged, object: nil)
                    }
                }) {
                    continue
                }
                if let settings, AgentMeterURLRouter.handle(url, settings: settings) {
                    continue
                }
            }
        }
    }
}
