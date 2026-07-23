import Foundation

/// Shared cache-free HTTP session. Responses are tiny JSON blobs fetched once
/// a minute; URLCache would only hold memory for data we never reuse.
enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()
}

/// One rate-limit window (e.g. Codex 5h window, Cursor monthly plan usage).
struct UsageWindow: Equatable {
    let label: String
    let usedPercent: Double
    let resetsAt: Date?

    var remainingDescription: String? {
        resetDescription(style: .relative)
    }

    func resetDescription(style: ResetTimeStyle) -> String? {
        guard let resetsAt else { return nil }
        switch style {
        case .relative:
            let interval = resetsAt.timeIntervalSinceNow
            guard interval > 0 else { return "resets soon" }
            let days = Int(interval) / 86400
            let hours = (Int(interval) % 86400) / 3600
            let minutes = (Int(interval) % 3600) / 60
            if days > 0 { return "resets in \(days)d \(hours)h" }
            if hours > 0 { return "resets in \(hours)h \(minutes)m" }
            return "resets in \(minutes)m"
        case .absolute:
            let calendar = Calendar.current
            let includeYear = calendar.component(.year, from: resetsAt)
                != calendar.component(.year, from: Date())
            var format = Date.FormatStyle().month(.abbreviated).day().hour().minute()
            if includeYear { format = format.year() }
            return "resets \(resetsAt.formatted(format))"
        }
    }
}

/// Account balance for pay-as-you-go (API key) providers, where there is no
/// "percent of limit" to show — the meaningful number is money/credits left.
struct BalanceInfo: Equatable {
    let remaining: Double
    /// Lifetime or period spend, when the provider reports it.
    let used: Double?
    /// e.g. "$", "¥", or "VCU " — prefixed to amounts as-is.
    let currencySymbol: String

    var display: String {
        "\(currencySymbol)\(Self.format(remaining)) left"
    }

    /// Compact form for the menu bar, e.g. "$12".
    var shortDisplay: String {
        "\(currencySymbol)\(Self.format(remaining, compact: true))"
    }

    static func format(_ value: Double, compact: Bool = false) -> String {
        if compact, value >= 10 {
            return String(format: "%.0f", value)
        }
        return value == value.rounded() && value < 1000
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}

/// Normalized usage snapshot for one provider.
struct ProviderUsage: Equatable {
    let planName: String?
    let windows: [UsageWindow]
    /// When the underlying data was produced (not when we read it).
    let asOf: Date?
    /// Balance readout for pay-as-you-go providers (may coexist with windows).
    var balance: BalanceInfo?

    init(planName: String?, windows: [UsageWindow], asOf: Date?, balance: BalanceInfo? = nil) {
        self.planName = planName
        self.windows = windows
        self.asOf = asOf
        self.balance = balance
    }

    /// The most constrained window, used for the menu bar summary.
    var worstWindow: UsageWindow? {
        windows.max(by: { $0.usedPercent < $1.usedPercent })
    }

    /// Menu bar summary: percent when windows exist, balance otherwise.
    func menuSummary(direction: CountDirection) -> String? {
        if let worst = worstWindow {
            return direction.percentLabel(worst.usedPercent, menuBar: true)
        }
        return balance?.shortDisplay
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
