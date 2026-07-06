import Foundation
import Security

/// Claude Code usage from Anthropic's OAuth usage endpoint, authenticated with
/// the token that the Claude CLI stores locally (credentials file or Keychain).
///
/// The token is read fresh on each fetch, refreshed in memory when expired, and
/// never written back to disk by this app.
struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    let shortCode = "Cl"

    var credentialsPath = NSHomeDirectory() + "/.claude/.credentials.json"
    var keychainService = "Claude Code-credentials"

    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let betaHeader = "oauth-2025-04-20"
    static let userAgent = "claude-code/2.1.0"

    var isDetected: Bool {
        FileManager.default.fileExists(atPath: credentialsPath)
            || Self.keychainItemExists(service: keychainService)
    }

    func fetch() async throws -> ProviderUsage {
        var creds = try loadCredentials()
        if creds.isExpired {
            creds = try await Self.refresh(refreshToken: creds.refreshToken, plan: creds.subscriptionType)
        }
        let response = try await Self.fetchUsage(accessToken: creds.accessToken)
        return Self.usage(from: response, plan: creds.subscriptionType, now: Date())
    }

    // MARK: - Credentials

    struct Credentials {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date?
        var subscriptionType: String?

        var isExpired: Bool {
            guard let expiresAt else { return false }
            // Refresh a minute early to avoid racing the expiry.
            return expiresAt.timeIntervalSinceNow < 60
        }
    }

    private struct CredentialsFile: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Double?
            let subscriptionType: String?
        }
        let claudeAiOauth: OAuth
    }

    func loadCredentials() throws -> Credentials {
        if let data = FileManager.default.contents(atPath: credentialsPath),
           let creds = Self.decodeCredentials(data) {
            return creds
        }
        if let data = Self.keychainSecret(service: keychainService),
           let creds = Self.decodeCredentials(data) {
            return creds
        }
        throw ClaudeError.notSignedIn
    }

    static func decodeCredentials(_ data: Data) -> Credentials? {
        guard let file = try? JSONDecoder().decode(CredentialsFile.self, from: data),
              let refresh = file.claudeAiOauth.refreshToken else {
            return nil
        }
        let expiresAt = file.claudeAiOauth.expiresAt.map {
            // Anthropic stores expiry in milliseconds since epoch.
            Date(timeIntervalSince1970: $0 / 1000)
        }
        return Credentials(
            accessToken: file.claudeAiOauth.accessToken,
            refreshToken: refresh,
            expiresAt: expiresAt,
            subscriptionType: file.claudeAiOauth.subscriptionType
        )
    }

    // MARK: - Networking

    static func refresh(refreshToken: String, plan: String?) async throws -> Credentials {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: oauthClientID),
        ]
        request.httpBody = (components.percentEncodedQuery ?? "").data(using: .utf8)

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 429 { throw ClaudeError.rateLimited }
            throw ClaudeError.refreshFailed(http.statusCode)
        }

        struct TokenResponse: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresIn: Double?
            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        return Credentials(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken ?? refreshToken,
            expiresAt: token.expiresIn.map { Date(timeIntervalSinceNow: $0) },
            subscriptionType: plan
        )
    }

    static func fetchUsage(accessToken: String) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
        if http.statusCode == 401 { throw ClaudeError.notSignedIn }
        if http.statusCode == 429 { throw ClaudeError.rateLimited }
        guard http.statusCode == 200 else { throw ClaudeError.httpStatus(http.statusCode) }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }

    // MARK: - Response mapping

    /// Windows are keyed dynamically; we pull the ones we display.
    struct UsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resetsAt: String?
            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
        }
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDayOpus: Window?

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDayOpus = "seven_day_opus"
        }
    }

    static func usage(from response: UsageResponse, plan: String?, now: Date) -> ProviderUsage {
        func window(_ w: UsageResponse.Window?, _ label: String) -> UsageWindow? {
            guard let w, let utilization = w.utilization else { return nil }
            let resetsAt = w.resetsAt.flatMap {
                ISO8601DateFormatter.flexible.date(from: $0) ?? ISO8601DateFormatter.plain.date(from: $0)
            }
            return UsageWindow(label: label, usedPercent: max(0, min(100, utilization)), resetsAt: resetsAt)
        }

        let windows = [
            window(response.fiveHour, "5h limit"),
            window(response.sevenDay, "Weekly limit"),
            window(response.sevenDayOpus, "Weekly (Opus)"),
        ].compactMap { $0 }

        return ProviderUsage(planName: plan?.capitalized, windows: windows, asOf: now)
    }

    // MARK: - Keychain

    static func keychainItemExists(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    static func keychainSecret(service: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

enum ClaudeError: LocalizedError {
    case notSignedIn
    case rateLimited
    case refreshFailed(Int)
    case badResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Not signed in to Claude Code"
        case .rateLimited: return "Anthropic rate-limited the usage request"
        case .refreshFailed(let code): return "Claude token refresh failed (HTTP \(code))"
        case .badResponse: return "Unexpected response from Anthropic"
        case .httpStatus(let code): return "Anthropic returned HTTP \(code)"
        }
    }
}
