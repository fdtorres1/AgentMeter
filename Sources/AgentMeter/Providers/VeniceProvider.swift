import Foundation

/// Venice prepaid balance, authenticated by a key stored in the app's Keychain.
struct VeniceProvider: UsageProvider {
    let id = "venice"
    let displayName = "Venice"
    let shortCode = "Ve"

    static let balanceURL = URL(string: "https://api.venice.ai/api/v1/billing/balance")!
    static let keyURL = "https://venice.ai/settings/api"

    var isDetected: Bool {
        KeychainStore.exists(keychainAccount)
    }

    var authKind: ProviderAuthKind { .apiKey(keyURL: Self.keyURL) }

    var dashboardURL: URL? {
        URL(string: "https://venice.ai/settings/api")
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
        guard let http = response as? HTTPURLResponse else { throw VeniceError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw VeniceError.invalidKey
        }
        guard http.statusCode == 200 else { throw VeniceError.httpStatus(http.statusCode) }

        let balance = try JSONDecoder().decode(BalanceResponse.self, from: data)
        return Self.usage(from: balance, now: Date())
    }

    struct BalanceResponse: Decodable {
        let canConsume: Bool?
        let consumptionCurrency: String?
        let balances: [String: Double]?
    }

    nonisolated static func usage(from response: BalanceResponse, now: Date) -> ProviderUsage {
        let (currency, amount) = chosenBalance(from: response)
        return ProviderUsage(
            planName: nil,
            windows: [],
            asOf: now,
            balance: BalanceInfo(
                remaining: amount,
                used: nil,
                currencySymbol: currencySymbol(for: currency)
            )
        )
    }

    nonisolated static func chosenBalance(from response: BalanceResponse) -> (String, Double) {
        let balances = response.balances ?? [:]
        let preferred = response.consumptionCurrency
        let fallbacks = [preferred, "USD", "DIEM"].compactMap { $0 }
        for currency in fallbacks {
            if let amount = balances[currency] {
                return (currency, amount)
            }
        }
        return ("USD", 0)
    }

    nonisolated static func currencySymbol(for currency: String) -> String {
        switch currency {
        case "USD": return "$"
        case "DIEM": return "DIEM "
        case "VCU": return "VCU "
        default: return "\(currency) "
        }
    }
}

enum VeniceError: LocalizedError {
    case badResponse
    case invalidKey
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return L("Unexpected response from Venice")
        case .invalidKey: return L("Venice key rejected — check the key in Settings")
        case .httpStatus(let code): return L("Venice returned HTTP \(code))")
        }
    }
}
