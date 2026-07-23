import Foundation
import UserNotifications

/// Tracks which usage windows have crossed a notification threshold.
struct ThresholdTracker {
    private var lastSeenPercents: [String: Double] = [:]
    private var lastSeenResetsAt: [String: Date] = [:]
    private var lastNotifiedPercents: [String: Double]
    private let defaults: UserDefaults

    private static let stateKey = "thresholdTrackerState"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.lastNotifiedPercents = defaults.dictionary(forKey: Self.stateKey) as? [String: Double] ?? [:]
    }

    mutating func crossings(
        providerID: String,
        usage: ProviderUsage,
        threshold: Double
    ) -> [UsageWindow] {
        var result: [UsageWindow] = []

        for window in usage.windows {
            let key = "\(providerID)|\(window.label)"
            let reset = windowDidReset(
                key: key,
                newPercent: window.usedPercent,
                newResetsAt: window.resetsAt
            )
            // Any observation below the threshold re-arms, in addition to the
            // drop/reset heuristics. This covers windows that reset while the
            // app wasn't running, where the in-memory last-seen state is empty
            // but the fired-state persisted.
            if reset || window.usedPercent < threshold {
                lastNotifiedPercents.removeValue(forKey: key)
            }

            let wasBelow = lastNotifiedPercents[key].map { $0 < threshold } ?? true
            if window.usedPercent >= threshold, wasBelow {
                result.append(window)
                lastNotifiedPercents[key] = window.usedPercent
            }

            lastSeenPercents[key] = window.usedPercent
            if let resetsAt = window.resetsAt {
                lastSeenResetsAt[key] = resetsAt
            }
        }

        defaults.set(lastNotifiedPercents, forKey: Self.stateKey)
        return result
    }

    mutating func balanceCrossings(
        providerID: String,
        balance: BalanceInfo,
        threshold: Double
    ) -> Bool {
        let key = "balance.\(providerID)"
        let remaining = balance.remaining

        if remaining >= threshold {
            lastNotifiedPercents.removeValue(forKey: key)
        }

        let wasAbove = lastNotifiedPercents[key].map { $0 >= threshold } ?? true
        if remaining < threshold, wasAbove {
            lastNotifiedPercents[key] = remaining
            defaults.set(lastNotifiedPercents, forKey: Self.stateKey)
            return true
        }

        defaults.set(lastNotifiedPercents, forKey: Self.stateKey)
        return false
    }

    private func windowDidReset(
        key: String,
        newPercent: Double,
        newResetsAt: Date?
    ) -> Bool {
        if let lastSeen = lastSeenPercents[key], lastSeen - newPercent > 10 {
            return true
        }
        if let lastResets = lastSeenResetsAt[key],
           let newResets = newResetsAt,
           newResets > lastResets {
            return true
        }
        return false
    }
}

@MainActor
final class NotificationManager {
    private var tracker = ThresholdTracker()
    private var authorizationRequested = false

    func notifyIfNeeded(
        provider: any UsageProvider,
        usage: ProviderUsage,
        settings: SettingsStore
    ) {
        guard settings.notificationsEnabled else { return }

        let crossings = tracker.crossings(
            providerID: provider.id,
            usage: usage,
            threshold: settings.notificationThreshold
        )
        for window in crossings {
            postNotification(provider: provider, window: window)
        }

        if let balance = usage.balance,
           tracker.balanceCrossings(
               providerID: provider.id,
               balance: balance,
               threshold: settings.balanceNotificationThreshold
           ) {
            postBalanceNotification(provider: provider, balance: balance)
        }
    }

    func requestAuthorizationIfNeeded() {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(provider: any UsageProvider, window: UsageWindow) {
        let content = UNMutableNotificationContent()
        content.title = L("\(provider.displayName) usage alert")
        var body = L("\(window.label) at \(String(Int(window.usedPercent.rounded())))%")
        if let remaining = window.remainingDescription {
            body += " — \(remaining)"
        }
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(provider.id)-\(window.label)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func postBalanceNotification(provider: any UsageProvider, balance: BalanceInfo) {
        let content = UNMutableNotificationContent()
        content.title = L("\(provider.displayName) balance alert")
        content.body = L("\(balance.currencySymbol)\(BalanceInfo.format(balance.remaining)) remaining")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(provider.id)-balance-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
