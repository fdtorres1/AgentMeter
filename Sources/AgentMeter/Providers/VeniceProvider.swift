import Foundation

/// Venice balance from either the Admin billing endpoint or the
/// inference-key-safe rate-limits endpoint.
struct VeniceProvider: UsageProvider {
    let id = "venice"
    let displayName = "Venice"
    let shortCode = "Ve"

    static let balanceURL = URL(string: "https://api.venice.ai/api/v1/billing/balance")!
    static let rateLimitsURL = URL(string: "https://api.venice.ai/api/v1/api_keys/rate_limits")!
    static let keyURL = "https://venice.ai/settings/api"

    var isDetected: Bool {
        KeychainStore.exists(keychainAccount)
    }

    var authKind: ProviderAuthKind { .apiKey(keyURL: Self.keyURL) }

    var credentialHelpText: String? {
        L("Inference and Admin Venice API keys are supported. x402 wallet balances are not supported.")
    }

    var apiKeyPlaceholder: String { L("Venice API key") }

    var dashboardURL: URL? {
        URL(string: Self.keyURL)
    }

    func fetch() async throws -> ProviderUsage {
        guard let storedKey = KeychainStore.get(keychainAccount) else {
            throw ProviderKeyError.missingKey(displayName)
        }
        let key = storedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw VeniceError.invalidKey }

        let billing = try await Self.get(Self.balanceURL, key: key)
        if billing.statusCode == 200 {
            do {
                let response = try JSONDecoder().decode(BalanceResponse.self, from: billing.data)
                return Self.usage(from: response, now: Date())
            } catch {
                throw VeniceError.parseFailed(error.localizedDescription)
            }
        }

        // /billing/balance requires an Admin key. The rate-limits endpoint
        // exposes USD/DIEM balances to safer Inference keys.
        if billing.statusCode == 401 || billing.statusCode == 403 {
            let fallback = try await Self.get(Self.rateLimitsURL, key: key)
            if fallback.statusCode == 200 {
                do {
                    let response = try JSONDecoder().decode(RateLimitsResponse.self, from: fallback.data)
                    return Self.usage(from: response, now: Date())
                } catch {
                    throw VeniceError.parseFailed(error.localizedDescription)
                }
            }
            if fallback.statusCode == 401 || fallback.statusCode == 403 {
                throw VeniceError.invalidKey
            }
            throw VeniceError.httpStatus(fallback.statusCode)
        }

        throw VeniceError.apiError(Self.errorMessage(from: billing.data)
            ?? "HTTP \(billing.statusCode)")
    }

    private static func get(_ url: URL, key: String) async throws
        -> (data: Data, statusCode: Int)
    {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VeniceError.badResponse }
        return (data, http.statusCode)
    }

    struct BalanceResponse: Decodable {
        let canConsume: Bool?
        let consumptionCurrency: String?
        let balances: VeniceBalances
        let diemEpochAllocation: Double?

        enum CodingKeys: String, CodingKey {
            case canConsume
            case consumptionCurrency
            case balances
            case diemEpochAllocation
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            canConsume = try container.decodeIfPresent(Bool.self, forKey: .canConsume)
            consumptionCurrency = try container.decodeIfPresent(String.self, forKey: .consumptionCurrency)
            balances = try container.decodeIfPresent(VeniceBalances.self, forKey: .balances) ?? VeniceBalances()
            diemEpochAllocation = try container.decodeFlexibleDoubleIfPresent(forKey: .diemEpochAllocation)
        }
    }

    struct VeniceBalances: Decodable {
        let diem: Double?
        let usd: Double?

        init(diem: Double? = nil, usd: Double? = nil) {
            self.diem = diem
            self.usd = usd
        }

        private enum CodingKeys: String, CodingKey {
            case diem
            case usd
            case DIEM
            case USD
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            diem = try container.decodeFlexibleDoubleIfPresent(forKeys: [.diem, .DIEM])
            usd = try container.decodeFlexibleDoubleIfPresent(forKeys: [.usd, .USD])
        }
    }

    struct RateLimitsResponse: Decodable {
        struct Payload: Decodable {
            let balances: [String: Double]?
            let nextEpochBegins: String?
        }
        let data: Payload
    }

    nonisolated static func usage(from response: BalanceResponse, now: Date) -> ProviderUsage {
        let values = ["DIEM": response.balances.diem, "USD": response.balances.usd]
        let (currency, amount) = chosenBalance(
            values: values,
            preferred: response.consumptionCurrency
        )
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

    nonisolated static func usage(from response: RateLimitsResponse, now: Date) -> ProviderUsage {
        let (currency, amount) = chosenBalance(
            values: response.data.balances?.mapValues { Optional($0) } ?? [:],
            preferred: nil
        )
        return ProviderUsage(
            planName: L("Inference key"),
            windows: [],
            asOf: now,
            balance: BalanceInfo(
                remaining: amount,
                used: nil,
                currencySymbol: currencySymbol(for: currency)
            )
        )
    }

    nonisolated static func chosenBalance(
        values: [String: Double?],
        preferred: String?
    ) -> (String, Double) {
        let normalized = Dictionary(uniqueKeysWithValues: values.compactMap { key, value in
            value.map { (key.uppercased(), $0) }
        })
        let preferredKey = preferred?.uppercased()
        let fallbacks = [preferredKey, "USD", "DIEM"].compactMap { $0 }
        for currency in fallbacks {
            if let amount = normalized[currency] {
                return (currency, max(0, amount))
            }
        }
        return ("USD", 0)
    }

    nonisolated static func currencySymbol(for currency: String) -> String {
        switch currency.uppercased() {
        case "USD": return "$"
        case "DIEM": return "DIEM "
        case "VCU": return "VCU "
        default: return "\(currency.uppercased()) "
        }
    }

    private static func errorMessage(from data: Data) -> String? {
        struct Response: Decodable { let error: String? }
        return (try? JSONDecoder().decode(Response.self, from: data))?.error
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        guard contains(key), !(try decodeNil(forKey: key)) else { return nil }
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let string = try? decode(String.self, forKey: key) { return Double(string) }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKeys keys: [Key]) throws -> Double? {
        for key in keys where contains(key) {
            if let value = try decodeFlexibleDoubleIfPresent(forKey: key) {
                return value
            }
        }
        return nil
    }
}

enum VeniceError: LocalizedError {
    case badResponse
    case invalidKey
    case apiError(String)
    case parseFailed(String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return L("Unexpected response from Venice")
        case .invalidKey: return L("Venice key rejected — check the key in Settings")
        case .apiError(let message): return L("Venice API error: \(message)")
        case .parseFailed(let message): return L("Failed to parse Venice response: \(message)")
        case .httpStatus(let code): return L("Venice returned HTTP \(code)")
        }
    }
}
