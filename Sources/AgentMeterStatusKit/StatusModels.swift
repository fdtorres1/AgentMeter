import Foundation

public let statusSnapshotSchemaVersion = 1

public struct StatusSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var generatedAt: Date
    public var appVersion: String
    public var providers: [ProviderStatus]

    public init(
        schemaVersion: Int = statusSnapshotSchemaVersion,
        generatedAt: Date,
        appVersion: String,
        providers: [ProviderStatus]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.providers = providers
    }
}

public struct ProviderStatus: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var state: String
    public var windows: [WindowStatus]
    public var balance: BalanceStatus?
    public var asOf: Date?
    public var staleSince: Date?
    public var error: String?
    /// Signed-in account email (Codex multi-account; added in 1.11.0).
    public var accountEmail: String?
    /// Raw plan type display name (Codex; added in 1.11.0).
    public var planType: String?
    /// User-tracked subscription renewal (Codex; added in 1.11.0).
    public var renewal: RenewalStatus?
    /// Organization API usage report (Claude; optional additive schema v1 field).
    public var apiUsage: APIUsageStatus?

    public init(
        id: String,
        displayName: String,
        state: String,
        windows: [WindowStatus] = [],
        balance: BalanceStatus? = nil,
        asOf: Date? = nil,
        staleSince: Date? = nil,
        error: String? = nil,
        accountEmail: String? = nil,
        planType: String? = nil,
        renewal: RenewalStatus? = nil,
        apiUsage: APIUsageStatus? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.windows = windows
        self.balance = balance
        self.asOf = asOf
        self.staleSince = staleSince
        self.error = error
        self.accountEmail = accountEmail
        self.planType = planType
        self.renewal = renewal
        self.apiUsage = apiUsage
    }
}

/// Claude organization API usage report. This is spend reporting, not available-credit data.
public struct APIUsageStatus: Codable, Equatable, Sendable {
    public var costUSD: Double
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheCreationTokens: Int
    public var periodStart: Date
    public var periodEnd: Date
    public var currency: String
    public var prepaidCreditsStatus: String
    public var costExcludesPriorityTier: Bool

    public init(
        costUSD: Double,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int,
        cacheCreationTokens: Int,
        periodStart: Date,
        periodEnd: Date,
        currency: String = "USD",
        prepaidCreditsStatus: String = "unavailable",
        costExcludesPriorityTier: Bool = true
    ) {
        self.costUSD = costUSD
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.currency = currency
        self.prepaidCreditsStatus = prepaidCreditsStatus
        self.costExcludesPriorityTier = costExcludesPriorityTier
    }
}

public struct RenewalStatus: Codable, Equatable, Sendable {
    public var expectedAt: Date
    public var platform: String
    public var confirmedAt: Date?

    public init(expectedAt: Date, platform: String, confirmedAt: Date? = nil) {
        self.expectedAt = expectedAt
        self.platform = platform
        self.confirmedAt = confirmedAt
    }
}

public struct WindowStatus: Codable, Equatable, Sendable {
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?

    public init(label: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
    }
}

public struct BalanceStatus: Codable, Equatable, Sendable {
    public var amount: Double
    public var currency: String
    public var kind: String

    public init(amount: Double, currency: String, kind: String) {
        self.amount = amount
        self.currency = currency
        self.kind = kind
    }
}
