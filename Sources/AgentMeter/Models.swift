import Foundation

/// One rate-limit window (e.g. Codex 5h window, Cursor monthly plan usage).
struct UsageWindow: Equatable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingDescription: String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSinceNow
        guard interval > 0 else { return "resets soon" }
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if days > 0 { return "resets in \(days)d \(hours)h" }
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }
}

/// Normalized usage snapshot for one provider.
struct ProviderUsage: Equatable {
    let planName: String?
    let windows: [UsageWindow]
    /// When the underlying data was produced (not when we read it).
    let asOf: Date?

    /// The most constrained window, used for the menu bar summary.
    var worstWindow: UsageWindow? {
        windows.max(by: { $0.usedPercent < $1.usedPercent })
    }
}

enum ProviderState: Equatable {
    case loading
    case ready(ProviderUsage)
    case error(String)

    var usage: ProviderUsage? {
        if case .ready(let usage) = self { return usage }
        return nil
    }
}
