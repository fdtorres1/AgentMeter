import Foundation
import SQLite3

/// Fetches Cursor plan usage from cursor.com using the session token that the
/// Cursor app itself stores locally.
///
/// The access token lives in Cursor's state database
/// (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`,
/// key `cursorAuth/accessToken`). The dashboard API authenticates with a
/// `WorkosCursorSessionToken` cookie of the form `<jwt-sub>::<accessToken>`.
/// The token is read fresh on every refresh and never persisted by this app.
struct CursorUsageFetcher: Sendable {
    var stateDBPath = NSHomeDirectory()
        + "/Library/Application Support/Cursor/User/globalStorage/state.vscdb"
    var endpoint = URL(string: "https://cursor.com/api/usage-summary")!

    func fetchUsage() async throws -> ProviderUsage {
        let token = try readAccessToken()
        let sub = try Self.jwtSubject(from: token)
        let cookie = try Self.cookieHeader(sub: sub, token: token)

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorFetchError.badResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CursorFetchError.notAuthenticated
        }
        guard http.statusCode == 200 else {
            throw CursorFetchError.httpStatus(http.statusCode)
        }
        let summary = try JSONDecoder().decode(UsageSummary.self, from: data)
        return Self.usage(from: summary, now: Date())
    }

    // MARK: - Token access

    /// Reads the access token from Cursor's state database.
    /// The database is multi-GB, so it is queried in place, read-only.
    private func readAccessToken() throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(stateDBPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw CursorFetchError.tokenNotFound
        }
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        let sql = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CursorFetchError.tokenNotFound
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let text = sqlite3_column_text(statement, 0) else {
            throw CursorFetchError.tokenNotFound
        }
        let token = String(cString: text)
        guard !token.isEmpty else { throw CursorFetchError.tokenNotFound }
        return token
    }

    /// Extracts the `sub` claim from the JWT access token. The dashboard
    /// cookie requires it as the user identifier prefix.
    static func jwtSubject(from token: String) throws -> String {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { throw CursorFetchError.invalidToken }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = object["sub"] as? String, !sub.isEmpty else {
            throw CursorFetchError.invalidToken
        }
        return sub
    }

    static func cookieHeader(sub: String, token: String) throws -> String {
        let raw = "\(sub)::\(token)"
        guard let encoded = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw CursorFetchError.invalidToken
        }
        return "WorkosCursorSessionToken=\(encoded)"
    }

    // MARK: - Response mapping

    struct UsageSummary: Decodable {
        struct Plan: Decodable {
            var used: Double?
            var limit: Double?
            var autoPercentUsed: Double?
            var apiPercentUsed: Double?
            var totalPercentUsed: Double?
        }

        /// Used/limit cents pool used by enterprise/team personal caps and
        /// shared team pools, when no per-lane `plan` block is present.
        struct Pool: Decodable {
            var used: Double?
            var limit: Double?
        }

        struct IndividualUsage: Decodable {
            var plan: Plan?
            var overall: Pool?
        }

        struct TeamUsage: Decodable {
            var pooled: Pool?
        }

        var billingCycleEnd: String?
        var membershipType: String?
        var individualUsage: IndividualUsage?
        var teamUsage: TeamUsage?
    }

    static func usage(from summary: UsageSummary, now: Date) -> ProviderUsage {
        var resetsAt: Date?
        if let end = summary.billingCycleEnd {
            resetsAt = ISO8601DateFormatter.flexible.date(from: end)
                ?? ISO8601DateFormatter.plain.date(from: end)
        }

        func clamp(_ value: Double) -> Double { max(0, min(100, value)) }

        var windows: [UsageWindow] = []
        let plan = summary.individualUsage?.plan

        var totalPercent = plan?.totalPercentUsed
        if totalPercent == nil, let used = plan?.used, let limit = plan?.limit, limit > 0 {
            totalPercent = used / limit * 100
        }
        if let totalPercent {
            windows.append(UsageWindow(
                label: L("Included usage"),
                usedPercent: clamp(totalPercent),
                resetsAt: resetsAt
            ))
        }
        if let autoPercent = plan?.autoPercentUsed {
            windows.append(UsageWindow(
                label: L("Auto usage"),
                usedPercent: clamp(autoPercent),
                resetsAt: resetsAt
            ))
        }
        if let apiPercent = plan?.apiPercentUsed {
            windows.append(UsageWindow(
                label: L("API usage"),
                usedPercent: clamp(apiPercent),
                resetsAt: resetsAt
            ))
        }

        // Enterprise/team accounts often lack a `plan` block; fall back to the
        // personal cap, then the shared team pool, so they still get a meter.
        if windows.isEmpty {
            func poolPercent(_ pool: UsageSummary.Pool?) -> Double? {
                guard let used = pool?.used, let limit = pool?.limit, limit > 0 else { return nil }
                return used / limit * 100
            }
            if let overall = poolPercent(summary.individualUsage?.overall) {
                windows.append(UsageWindow(label: L("Personal cap"), usedPercent: clamp(overall), resetsAt: resetsAt))
            } else if let pooled = poolPercent(summary.teamUsage?.pooled) {
                windows.append(UsageWindow(label: L("Team pool"), usedPercent: clamp(pooled), resetsAt: resetsAt))
            }
        }

        return ProviderUsage(
            planName: summary.membershipType?.capitalized,
            windows: windows,
            asOf: now
        )
    }
}

enum CursorFetchError: LocalizedError {
    case tokenNotFound
    case invalidToken
    case notAuthenticated
    case badResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .tokenNotFound: return L("Cursor session token not found (is Cursor signed in?)")
        case .invalidToken: return L("Cursor session token has an unexpected format")
        case .notAuthenticated: return L("Cursor session expired — sign in to Cursor again")
        case .badResponse: return L("Unexpected response from cursor.com")
        case .httpStatus(let code): return L("cursor.com returned HTTP \(code))")
        }
    }
}
