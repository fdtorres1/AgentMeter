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
            Text(store.menuBarTitle)
                .font(.system(size: 12).monospacedDigit())
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no Dock icon even when run unbundled via swift run.
        NSApp.setActivationPolicy(.accessory)
    }
}
