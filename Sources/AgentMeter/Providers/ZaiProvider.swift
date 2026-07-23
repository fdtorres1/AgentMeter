import Foundation

/// Z.ai subscription quota, authenticated by a key stored in the app's Keychain.
struct ZaiProvider: UsageProvider {
    let id = "zai"
    let displayName = "Z.ai"
    let shortCode = "Zg"

    static let quotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
    static let keyURL = "https://z.ai/manage-apikey/apikey-list"

    var isDetected: Bool {
        KeychainStore.exists(keychainAccount)
    }

    var authKind: ProviderAuthKind { .apiKey(keyURL: Self.keyURL) }

    func fetch() async throws -> ProviderUsage {
        guard let key = KeychainStore.get(keychainAccount) else {
            throw ProviderKeyError.missingKey(displayName)
        }

        var request = URLRequest(url: Self.quotaURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ZaiError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ZaiError.invalidKey
        }
        guard http.statusCode == 200 else { throw ZaiError.httpStatus(http.statusCode) }

        let quota = try JSONDecoder().decode(QuotaResponse.self, from: data)
        // Reject only an explicit non-200 body code; a missing code field on an
        // otherwise-valid response should not read as an auth failure.
        if let code = quota.code, code != 200 {
            throw ZaiError.invalidKey
        }
        return Self.usage(from: quota, now: Date())
    }

    struct QuotaResponse: Decodable {
        let code: Int?
        let data: QuotaData?
        let success: Bool?

        struct QuotaData: Decodable {
            let limits: [LimitEntry]?
            let planName: String?
        }

        struct LimitEntry: Decodable {
            let type: String?
            let percentage: Double?
            let nextResetTime: Int64?
        }
    }

    nonisolated static func usage(from response: QuotaResponse, now: Date) -> ProviderUsage {
        let windows = (response.data?.limits ?? []).compactMap { entry -> UsageWindow? in
            guard let type = entry.type, let label = label(for: type) else { return nil }
            let used = min(100, max(0, entry.percentage ?? 0))
            let resetsAt = entry.nextResetTime.map {
                Date(timeIntervalSince1970: TimeInterval($0) / 1000)
            }
            return UsageWindow(label: label, usedPercent: used, resetsAt: resetsAt)
        }
        return ProviderUsage(
            planName: response.data?.planName,
            windows: windows,
            asOf: now,
            balance: nil
        )
    }

    nonisolated static func label(for type: String) -> String? {
        switch type {
        case "TIME_LIMIT": return "Time quota"
        case "TOKENS_LIMIT": return "Token quota"
        default: return nil
        }
    }
}

enum ZaiError: LocalizedError {
    case badResponse
    case invalidKey
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from Z.ai"
        case .invalidKey: return "Z.ai key rejected — check the key in Settings"
        case .httpStatus(let code): return "Z.ai returned HTTP \(code)"
        }
    }
}
