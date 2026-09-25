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

    func resetDescription(style: ResetTimeStyle, now: Date = Date()) -> String? {
        guard let resetsAt else { return nil }
        switch style {
        case .relative:
            let interval = resetsAt.timeIntervalSince(now)
            guard interval > 0 else { return L("resets soon") }
            let days = Int(interval) / 86400
            let hours = (Int(interval) % 86400) / 3600
            let minutes = (Int(interval) % 3600) / 60
            if days > 0 { return L("resets in \(String(days))d \(String(hours))h") }
            if hours > 0 { return L("resets in \(String(hours))h \(String(minutes))m") }
            return L("resets in \(String(minutes))m")
        case .absolute:
            let calendar = Calendar.current
            let includeYear = calendar.component(.year, from: resetsAt)
                != calendar.component(.year, from: now)
            var format = Date.FormatStyle().month(.abbreviated).day().hour().minute()
            if includeYear { format = format.year() }
            let date = resetsAt.formatted(format)
            let interval = resetsAt.timeIntervalSince(now)
            guard interval > 0 else { return L("resets soon") }
            let duration: String
            if interval < 60 {
                duration = L("less than a minute")
            } else if interval >= 86_400 {
                var days = Int(interval) / 86_400
                var hours = Int(((interval - Double(days * 86_400)) / 3_600).rounded())
                if hours == 24 { days += 1; hours = 0 }
                duration = "\(days) \(L(days == 1 ? "day" : "days")) \(hours) \(L(hours == 1 ? "hour" : "hours"))"
            } else if interval >= 3_600 {
                var hours = Int(interval) / 3_600
                var minutes = Int(((interval - Double(hours * 3_600)) / 60).rounded())
                if minutes == 60 { hours += 1; minutes = 0 }
                if hours == 24 {
                    duration = "1 \(L("day")) 0 \(L("hours"))"
                } else {
                    duration = "\(hours) \(L(hours == 1 ? "hour" : "hours")) \(minutes) \(L(minutes == 1 ? "minute" : "minutes"))"
                }
            } else {
                let minutes = Int((interval / 60).rounded())
                if minutes == 60 {
                    duration = "1 \(L("hour")) 0 \(L("minutes"))"
                } else {
                    duration = "\(max(1, minutes)) \(L(minutes == 1 ? "minute" : "minutes"))"
                }
            }
            return L("resets \(date) (\(duration))")
        }
    }
}

enum BalanceKind: Equatable {
    case remaining
    case spent
}

/// Monetary usage for pay-as-you-go providers. Most report a remaining
/// balance; key-scoped APIs may only report spend.
struct BalanceInfo: Equatable {
    let remaining: Double
    /// Lifetime or period spend, when the provider reports it.
    let used: Double?
    /// e.g. "$", "¥", or "VCU " — prefixed to amounts as-is.
    let currencySymbol: String
    let kind: BalanceKind

    init(
        remaining: Double,
        used: Double?,
        currencySymbol: String,
        kind: BalanceKind = .remaining
    ) {
        self.remaining = remaining
        self.used = used
        self.currencySymbol = currencySymbol
        self.kind = kind
    }

    var display: String {
        switch kind {
        case .remaining:
            L("\(currencySymbol)\(Self.format(remaining)) left")
        case .spent:
            L("\(currencySymbol)\(Self.format(remaining)) used")
        }
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

/// Organization API reporting for a UTC calendar-month interval. Token
/// categories are disjoint; prepaid credits are not available in this report.
struct APIUsageSummary: Equatable, Sendable {
    let costUSD: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheCreationTokens: Int
    let periodStart: Date
    let periodEnd: Date

    func isAwaitingCurrentDay(now: Date = Date()) -> Bool {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        return periodEnd <= utc.startOfDay(for: now)
    }
}

/// Normalized usage snapshot for one provider.
struct ProviderUsage: Equatable {
    let planName: String?
    let windows: [UsageWindow]
    /// When the underlying data was produced. For API reports without a source
    /// freshness timestamp, this is the last check; apiUsage.periodEnd is coverage.
    let asOf: Date?
    /// Balance readout for pay-as-you-go providers (may coexist with windows).
    var balance: BalanceInfo?
    var apiUsage: APIUsageSummary?

    init(planName: String?, windows: [UsageWindow], asOf: Date?, balance: BalanceInfo? = nil, apiUsage: APIUsageSummary? = nil) {
        self.planName = planName
        self.windows = windows
        self.asOf = asOf
        self.balance = balance
        self.apiUsage = apiUsage
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
    /// Last-known data shown dimmed after a fetch failure.
    case stale(ProviderUsage, error: String, since: Date)
    case error(String)

    var usage: ProviderUsage? {
        switch self {
        case .ready(let usage), .stale(let usage, _, _):
            return usage
        case .loading, .error:
            return nil
        }
    }

    /// Pure transition when a provider fetch fails.
    nonisolated static func nextState(
        after previous: ProviderState,
        failure message: String,
        at date: Date
    ) -> ProviderState {
        switch previous {
        case .ready(let usage):
            return .stale(usage, error: message, since: date)
        case .stale(let usage, _, let since):
            return .stale(usage, error: message, since: since)
        case .loading, .error:
            return .error(message)
        }
    }
}
