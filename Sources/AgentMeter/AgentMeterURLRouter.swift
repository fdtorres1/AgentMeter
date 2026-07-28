import Foundation

extension Notification.Name {
    static let agentMeterRefreshRequested = Notification.Name("agentMeterRefreshRequested")
    static let agentMeterOpenUsageDetails = Notification.Name("agentMeterOpenUsageDetails")
}

enum AgentMeterURLRouter {
    /// Handles agentmeter:// URLs that are not OAuth callbacks.
    /// Returns true when the URL was consumed.
    @MainActor
    static func handle(_ url: URL, settings: SettingsStore) -> Bool {
        guard url.scheme == OpenRouterAuthFlow.callbackScheme else { return false }

        switch url.host {
        case "refresh":
            guard settings.agentAccessEnabled else { return true }
            NotificationCenter.default.post(name: .agentMeterRefreshRequested, object: nil)
            return true
        case "details":
            NotificationCenter.default.post(name: .agentMeterOpenUsageDetails, object: nil)
            return true
        default:
            return false
        }
    }
}
