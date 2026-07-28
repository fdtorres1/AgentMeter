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

    public init(
        id: String,
        displayName: String,
        state: String,
        windows: [WindowStatus] = [],
        balance: BalanceStatus? = nil,
        asOf: Date? = nil,
        staleSince: Date? = nil,
        error: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.state = state
        self.windows = windows
        self.balance = balance
        self.asOf = asOf
        self.staleSince = staleSince
        self.error = error
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
