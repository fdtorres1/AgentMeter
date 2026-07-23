import Foundation
import Combine

enum CountDirection: String {
    case used, remaining

    nonisolated func displayPercent(_ usedPercent: Double) -> Double {
        switch self {
        case .used: return usedPercent
        case .remaining: return 100 - usedPercent
        }
    }

    nonisolated func percentLabel(_ usedPercent: Double, menuBar: Bool = false) -> String {
        let value = Int(displayPercent(usedPercent).rounded())
        switch self {
        case .used: return L("\(value)%")
        case .remaining: return menuBar ? L("\(value)%") : L("\(value)% left")
        }
    }
}

enum ResetTimeStyle: String {
    case relative, absolute
}

/// User preferences: per-provider visibility and refresh cadence.
@MainActor
final class SettingsStore: ObservableObject {
    @Published var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    @Published var notificationThreshold: Double {
        didSet { defaults.set(notificationThreshold, forKey: Keys.notificationThreshold) }
    }

    @Published var countDirection: CountDirection {
        didSet { defaults.set(countDirection.rawValue, forKey: Keys.countDirection) }
    }

    @Published var resetTimeStyle: ResetTimeStyle {
        didSet { defaults.set(resetTimeStyle.rawValue, forKey: Keys.resetTimeStyle) }
    }

    @Published var balanceNotificationThreshold: Double {
        didSet { defaults.set(balanceNotificationThreshold, forKey: Keys.balanceNotificationThreshold) }
    }

    @Published var compactMenuBar: Bool {
        didSet { defaults.set(compactMenuBar, forKey: Keys.compactMenuBar) }
    }

    private let defaults: UserDefaults
    private var modeCache: [String: ProviderMode] = [:]
    private var menuBarCache: [String: Bool] = [:]

    static let refreshOptions: [(label: String, seconds: TimeInterval)] = [
        (L("30 seconds"), 30),
        (L("1 minute"), 60),
        (L("5 minutes"), 300),
    ]

    static let notificationThresholdOptions: [Double] = [70, 80, 90]
    static let balanceThresholdOptions: [Double] = [1, 5, 10]

    private enum Keys {
        static let refreshInterval = "refreshInterval"
        static let notificationsEnabled = "notificationsEnabled"
        static let notificationThreshold = "notificationThreshold"
        static let countDirection = "countDirection"
        static let resetTimeStyle = "resetTimeStyle"
        static let balanceNotificationThreshold = "balanceNotificationThreshold"
        static let compactMenuBar = "compactMenuBar"
        static func mode(_ id: String) -> String { "provider.\(id).mode" }
        static func inMenuBar(_ id: String) -> String { "provider.\(id).inMenuBar" }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = stored > 0 ? stored : 60
        self.notificationsEnabled = defaults.bool(forKey: Keys.notificationsEnabled)
        let storedThreshold = defaults.double(forKey: Keys.notificationThreshold)
        self.notificationThreshold = Self.notificationThresholdOptions.contains(storedThreshold)
            ? storedThreshold
            : 80
        let storedDirection = defaults.string(forKey: Keys.countDirection)
        self.countDirection = storedDirection.flatMap(CountDirection.init(rawValue:)) ?? .used
        let storedResetStyle = defaults.string(forKey: Keys.resetTimeStyle)
        self.resetTimeStyle = storedResetStyle.flatMap(ResetTimeStyle.init(rawValue:)) ?? .relative
        let storedBalanceThreshold = defaults.double(forKey: Keys.balanceNotificationThreshold)
        self.balanceNotificationThreshold = Self.balanceThresholdOptions.contains(storedBalanceThreshold)
            ? storedBalanceThreshold
            : 5
        if defaults.object(forKey: Keys.compactMenuBar) == nil {
            self.compactMenuBar = false
        } else {
            self.compactMenuBar = defaults.bool(forKey: Keys.compactMenuBar)
        }
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

    func showsInMenuBar(_ providerID: String) -> Bool {
        if let cached = menuBarCache[providerID] { return cached }
        let shows: Bool
        if defaults.object(forKey: Keys.inMenuBar(providerID)) == nil {
            shows = true
        } else {
            shows = defaults.bool(forKey: Keys.inMenuBar(providerID))
        }
        menuBarCache[providerID] = shows
        return shows
    }

    func setShowsInMenuBar(_ shows: Bool, for providerID: String) {
        menuBarCache[providerID] = shows
        defaults.set(shows, forKey: Keys.inMenuBar(providerID))
        objectWillChange.send()
    }
}
