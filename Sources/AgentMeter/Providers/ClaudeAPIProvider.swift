import Foundation
import CryptoKit

/// Organization-wide Claude Console API reporting. This is separate from the
/// Claude Code subscription provider and does not report prepaid credits.
struct ClaudeAPIProvider: UsageProvider {
    let id = "claude-api"
    let displayName = "Claude API"
    let shortCode = "ClA"

    static let keyURL = "https://platform.claude.com/settings/admin-keys"
    private static let sharedCache = ClaudeAPIReportCache()

    let keyReader: @Sendable () -> String?
    let clock: @Sendable () -> Date
    let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    let cache: ClaudeAPIReportCache

    init(
        keyReader: @escaping @Sendable () -> String? = { KeychainStore.get("apikey.claude-api") },
        clock: @escaping @Sendable () -> Date = { Date() },
        transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await HTTP.session.data(for: request, delegate: ClaudeAPINoRedirectDelegate.shared)
        },
        cache: ClaudeAPIReportCache = ClaudeAPIProvider.sharedCache
    ) {
        self.keyReader = keyReader
        self.clock = clock
        self.transport = transport
        self.cache = cache
    }

    var isDetected: Bool { KeychainStore.exists(keychainAccount) }
    var authKind: ProviderAuthKind { .apiKey(keyURL: Self.keyURL) }
    var dashboardURL: URL? { URL(string: "https://platform.claude.com/settings/usage") }
    var credentialHelpText: String? {
        L("Organization-wide API spend and tokens require a Claude Console Admin reporting key or an eligible unscoped personal or service key. Workspace-scoped keys and individual accounts cannot access these reports. Prepaid credit balance is unavailable through this API.")
    }

    func fetch() async throws -> ProviderUsage {
        guard let key = keyReader()?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            throw ProviderKeyError.missingKey(displayName)
        }
        let now = clock()
        let monthStart = Self.utcMonthStart(for: now)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let nextMidnight = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        return try await cache.fetch(key: key, monthStart: monthStart, now: now) {
            try await Self.load(key: key, start: monthStart, queryEnd: nextMidnight, observedAt: now, transport: transport)
        }
    }

    private static func utcMonthStart(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    private static func load(
        key: String,
        start: Date,
        queryEnd: Date,
        observedAt: Date,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> ProviderUsage {
        let costPages: [CostPage] = try await pages(
            path: "/v1/organizations/cost_report", key: key, start: start, end: queryEnd, transport: transport
        )
        let usagePages: [TokenPage] = try await pages(
            path: "/v1/organizations/usage_report/messages", key: key, start: start, end: queryEnd, transport: transport
        )

        var cents = Decimal.zero
        for page in costPages {
            for bucket in page.data {
                for result in bucket.results {
                    guard result.currency == "USD",
                          result.amount.range(of: #"^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                          let amount = Decimal(string: result.amount, locale: Locale(identifier: "en_US_POSIX")),
                          amount >= .zero else { throw ClaudeAPIError.malformedReport }
                    var left = cents
                    var right = amount
                    var sum = Decimal.zero
                    guard NSDecimalAdd(&sum, &left, &right, .plain) == .noError else {
                        throw ClaudeAPIError.malformedReport
                    }
                    cents = sum
                }
            }
        }
        let costUSD = NSDecimalNumber(decimal: cents / 100).doubleValue
        guard costUSD.isFinite else { throw ClaudeAPIError.malformedReport }

        var input = 0, output = 0, cacheRead = 0, cacheCreation = 0
        for page in usagePages {
            for bucket in page.data {
                for result in bucket.results {
                    try add(result.uncachedInputTokens, to: &input)
                    try add(result.outputTokens, to: &output)
                    try add(result.cacheReadInputTokens, to: &cacheRead)
                    try add(result.cacheCreation.ephemeral1hInputTokens, to: &cacheCreation)
                    try add(result.cacheCreation.ephemeral5mInputTokens, to: &cacheCreation)
                }
            }
        }

        let summary = APIUsageSummary(
            costUSD: costUSD, inputTokens: input, outputTokens: output,
            cacheReadTokens: cacheRead, cacheCreationTokens: cacheCreation,
            periodStart: start, periodEnd: observedAt
        )
        return ProviderUsage(
            planName: L("Organization"), windows: [], asOf: observedAt,
            balance: BalanceInfo(remaining: costUSD, used: nil, currencySymbol: "$", kind: .spent),
            apiUsage: summary
        )
    }

    private static func add(_ value: Int, to total: inout Int) throws {
        guard value >= 0 else { throw ClaudeAPIError.malformedReport }
        let (sum, overflow) = total.addingReportingOverflow(value)
        guard !overflow else { throw ClaudeAPIError.malformedReport }
        total = sum
    }

    private static func pages<Page: ClaudeAPIPage>(
        path: String,
        key: String,
        start: Date,
        end: Date,
        transport: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    ) async throws -> [Page] {
        var pages: [Page] = []
        var pageToken: String?
        var seen = Set<String>()
        repeat {
            guard pages.count < 100 else { throw ClaudeAPIError.malformedReport }
            var parts = URLComponents()
            parts.scheme = "https"
            parts.host = "api.anthropic.com"
            parts.path = path
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)!
            formatter.formatOptions = [.withInternetDateTime]
            parts.queryItems = [
                URLQueryItem(name: "starting_at", value: formatter.string(from: start)),
                URLQueryItem(name: "ending_at", value: formatter.string(from: end)),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "limit", value: "31")
            ]
            if let pageToken { parts.queryItems?.append(URLQueryItem(name: "page", value: pageToken)) }
            guard let url = parts.url else { throw ClaudeAPIError.malformedReport }
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("AgentMeter/1.0", forHTTPHeaderField: "User-Agent")

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await transport(request)
            } catch {
                // URLSession errors can embed request URLs and other details.
                throw ClaudeAPIError.connectionFailed
            }
            guard let http = response as? HTTPURLResponse else { throw ClaudeAPIError.badResponse }
            switch http.statusCode {
            case 200: break
            case 401: throw ClaudeAPIError.unauthorized
            case 403: throw ClaudeAPIError.forbidden
            case 429: throw ClaudeAPIError.rateLimited
            default: throw ClaudeAPIError.httpStatus(http.statusCode)
            }
            guard let decoded = try? JSONDecoder().decode(Page.self, from: data) else {
                throw ClaudeAPIError.malformedReport
            }
            pages.append(decoded)
            if decoded.hasMore {
                guard let next = decoded.nextPage, !next.isEmpty, seen.insert(next).inserted else {
                    throw ClaudeAPIError.malformedReport
                }
                pageToken = next
            } else {
                pageToken = nil
            }
        } while pageToken != nil
        return pages
    }

    struct CostPage: ClaudeAPIPage {
        let data: [CostBucket]
        let hasMore: Bool
        let nextPage: String?
        enum CodingKeys: String, CodingKey { case data, hasMore = "has_more", nextPage = "next_page" }
    }
    struct CostBucket: Decodable { let results: [CostResult] }
    struct CostResult: Decodable { let amount: String; let currency: String }

    struct TokenPage: ClaudeAPIPage {
        let data: [TokenBucket]
        let hasMore: Bool
        let nextPage: String?
        enum CodingKeys: String, CodingKey { case data, hasMore = "has_more", nextPage = "next_page" }
    }
    struct TokenBucket: Decodable { let results: [TokenResult] }
    struct TokenResult: Decodable {
        let uncachedInputTokens: Int
        let outputTokens: Int
        let cacheReadInputTokens: Int
        let cacheCreation: CacheCreation
        enum CodingKeys: String, CodingKey {
            case uncachedInputTokens = "uncached_input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
            case cacheCreation = "cache_creation"
        }
    }
    struct CacheCreation: Decodable {
        let ephemeral1hInputTokens: Int
        let ephemeral5mInputTokens: Int
        enum CodingKeys: String, CodingKey {
            case ephemeral1hInputTokens = "ephemeral_1h_input_tokens"
            case ephemeral5mInputTokens = "ephemeral_5m_input_tokens"
        }
    }
}

private protocol ClaudeAPIPage: Decodable {
    var hasMore: Bool { get }
    var nextPage: String? { get }
}

/// Shared by production instances; injected separately by tests.
actor ClaudeAPIReportCache {
    private var cacheKey: Data?
    private var monthStart: Date?
    private var cached: ProviderUsage?
    private var updatedAt: Date?
    private var inFlight: Task<ProviderUsage, Error>?
    private var lastFailure: ClaudeAPIError?
    private var failedAt: Date?
    private var generation = 0

    func fetch(
        key: String,
        monthStart: Date,
        now: Date,
        load: @escaping @Sendable () async throws -> ProviderUsage
    ) async throws -> ProviderUsage {
        let keyDigest = Data(SHA256.hash(data: Data(key.utf8)))
        if cacheKey != keyDigest || self.monthStart != monthStart {
            generation += 1
            cacheKey = keyDigest
            self.monthStart = monthStart
            cached = nil
            updatedAt = nil
            inFlight = nil
            lastFailure = nil
            failedAt = nil
        }
        if let cached, let updatedAt, now.timeIntervalSince(updatedAt) < 300,
           now >= updatedAt { return cached }
        if let inFlight { return try await inFlight.value }
        if let lastFailure, let failedAt, now.timeIntervalSince(failedAt) < 60,
           now >= failedAt { throw lastFailure }

        let currentGeneration = generation
        let task = Task { try await load() }
        inFlight = task
        do {
            let usage = try await task.value
            if generation == currentGeneration {
                cached = usage
                updatedAt = now
                inFlight = nil
                lastFailure = nil
                failedAt = nil
            }
            return usage
        } catch {
            let safe = (error as? ClaudeAPIError) ?? .connectionFailed
            if generation == currentGeneration {
                inFlight = nil
                lastFailure = safe
                failedAt = now
            }
            throw safe
        }
    }
}

/// A redirect must never forward an Admin key to another origin.
private final class ClaudeAPINoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    static let shared = ClaudeAPINoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum ClaudeAPIError: LocalizedError, Sendable {
    case connectionFailed
    case badResponse
    case malformedReport
    case unauthorized
    case forbidden
    case rateLimited
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .connectionFailed: return L("Could not connect to Claude API reporting")
        case .badResponse, .malformedReport: return L("Unexpected Claude API report")
        case .unauthorized: return L("Claude API reporting key rejected (HTTP 401)")
        case .forbidden: return L("Claude API reporting access denied (HTTP 403); check key scope and account eligibility")
        case .rateLimited: return L("Claude API reporting rate limited (HTTP 429)")
        case .httpStatus(let code): return L("Claude API reporting returned HTTP \(code)")
        }
    }
}
