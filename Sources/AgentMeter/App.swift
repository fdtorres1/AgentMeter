import SwiftUI

@main
struct AgentMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsStore
    @StateObject private var store: UsageStore

    init() {
        let settings = SettingsStore()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: UsageStore(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store, settings: settings)
        } label: {
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
        }
        .menuBarExtraStyle(.window)

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

extension Notification.Name {
    /// Posted when a provider credential changes (e.g. OAuth connect finished),
    /// so usage refreshes without waiting for the next timer tick.
    static let providerCredentialsChanged = Notification.Name("providerCredentialsChanged")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon even when run unbundled via swift run.
        NSApp.setActivationPolicy(.accessory)
    }

    /// URL-scheme callbacks (agentmeter://...) arrive here; MenuBarExtra views
    /// may not exist at that moment, so this cannot live in onOpenURL.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            _ = OpenRouterAuthFlow.shared.handleCallback(url) { result in
                if case .success = result {
                    NotificationCenter.default.post(name: .providerCredentialsChanged, object: nil)
                }
            }
        }
    }
}
