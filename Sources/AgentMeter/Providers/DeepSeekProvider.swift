import Foundation

/// DeepSeek prepaid balance, authenticated by a key stored in the app's Keychain.
struct DeepSeekProvider: UsageProvider {
    let id = "deepseek"
    let displayName = "DeepSeek"
    let shortCode = "DS"

    static let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!
    static let keyURL = "https://platform.deepseek.com/api_keys"

    var isDetected: Bool {
        KeychainStore.exists(keychainAccount)
    }

    var authKind: ProviderAuthKind { .apiKey(keyURL: Self.keyURL) }

    var dashboardURL: URL? {
        URL(string: "https://platform.deepseek.com/usage")
    }

    func fetch() async throws -> ProviderUsage {
        guard let key = KeychainStore.get(keychainAccount) else {
            throw ProviderKeyError.missingKey(displayName)
        }

        var request = URLRequest(url: Self.balanceURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DeepSeekError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw DeepSeekError.invalidKey
        }
        guard http.statusCode == 200 else { throw DeepSeekError.httpStatus(http.statusCode) }

        let balance = try JSONDecoder().decode(BalanceResponse.self, from: data)
        return Self.usage(from: balance, now: Date())
    }

    struct BalanceResponse: Decodable {
        let isAvailable: Bool?
        let balanceInfos: [BalanceInfoEntry]?

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    struct BalanceInfoEntry: Decodable {
        let currency: String?
        let totalBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
        }
    }

    nonisolated static func usage(from response: BalanceResponse, now: Date) -> ProviderUsage {
        let entry = response.balanceInfos?.first(where: { $0.currency == "USD" })
            ?? response.balanceInfos?.first
        let remaining = Double(entry?.totalBalance ?? "") ?? 0
        let currency = entry?.currency ?? "USD"
        return ProviderUsage(
            planName: nil,
            windows: [],
            asOf: now,
            balance: BalanceInfo(
                remaining: remaining,
                used: nil,
                currencySymbol: currencySymbol(for: currency)
            )
        )
    }

    nonisolated static func currencySymbol(for currency: String) -> String {
        switch currency {
        case "USD": return "$"
        case "CNY": return "¥"
        default: return "\(currency) "
        }
    }
}

enum DeepSeekError: LocalizedError {
    case badResponse
    case invalidKey
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return L("Unexpected response from DeepSeek")
        case .invalidKey: return L("DeepSeek key rejected — check the key in Settings")
        case .httpStatus(let code): return L("DeepSeek returned HTTP \(code))")
        }
    }
}
