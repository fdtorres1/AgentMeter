import Foundation
import Combine

/// User preferences: per-provider visibility and refresh cadence.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    private let defaults: UserDefaults
    private var modeCache: [String: ProviderMode] = [:]

    static let refreshOptions: [(label: String, seconds: TimeInterval)] = [
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
    ]

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static func mode(_ id: String) -> String { "provider.\(id).mode" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = stored > 0 ? stored : 60
    }

    func mode(for providerID: String) -> ProviderMode {
        if let cached = modeCache[providerID] { return cached }
        let raw = defaults.string(forKey: Keys.mode(providerID))
        let mode = raw.flatMap(ProviderMode.init(rawValue:)) ?? .auto
        modeCache[providerID] = mode
        return mode
    }

    func setMode(_ mode: ProviderMode, for providerID: String) {
        modeCache[providerID] = mode
        defaults.set(mode.rawValue, forKey: Keys.mode(providerID))
        objectWillChange.send()
    }
}
