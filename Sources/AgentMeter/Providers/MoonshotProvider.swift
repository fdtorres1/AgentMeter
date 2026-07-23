import Foundation

/// Kimi (Moonshot) prepaid balance, authenticated by a key stored in the app's Keychain.
struct MoonshotProvider: UsageProvider {
    let id = "moonshot"
    let displayName = "Kimi"
    let shortCode = "Ki"

    static let balanceURL = URL(string: "https://api.moonshot.ai/v1/users/me/balance")!
    static let keyURL = "https://platform.moonshot.ai/console/api-keys"

    var isDetected: Bool {
        KeychainStore.exists(keychainAccount)
    }

    var authKind: ProviderAuthKind { .apiKey(keyURL: Self.keyURL) }

    var dashboardURL: URL? {
        URL(string: "https://platform.moonshot.ai/console")
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
        guard let http = response as? HTTPURLResponse else { throw MoonshotError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw MoonshotError.invalidKey
        }
        guard http.statusCode == 200 else { throw MoonshotError.httpStatus(http.statusCode) }

        let balance = try JSONDecoder().decode(BalanceResponse.self, from: data)
        return Self.usage(from: balance, now: Date())
    }

    struct BalanceResponse: Decodable {
        let code: Int?
        let data: DataPayload?
        let status: Bool?

        struct DataPayload: Decodable {
            let availableBalance: Double?
            let voucherBalance: Double?
            let cashBalance: Double?

            enum CodingKeys: String, CodingKey {
                case availableBalance = "available_balance"
                case voucherBalance = "voucher_balance"
                case cashBalance = "cash_balance"
            }
        }
    }

    nonisolated static func usage(from response: BalanceResponse, now: Date) -> ProviderUsage {
        let available = max(0, response.data?.availableBalance ?? 0)
        return ProviderUsage(
            planName: nil,
            windows: [],
            asOf: now,
            balance: BalanceInfo(
                remaining: available,
                used: nil,
                currencySymbol: "$"
            )
        )
    }

    enum MoonshotCredentialProbeResult: Equatable {
        case valid
    }

    static let manageKeysURL = URL(string: "https://platform.moonshot.ai/console/api-keys")!

    func assessCredential() async -> CredentialAssessment? {
        guard let key = KeychainStore.get(keychainAccount) else { return nil }

        var request = URLRequest(url: Self.balanceURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await HTTP.session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return CredentialAssessmentSupport.probeFailed(manageURL: Self.manageKeysURL)
            }
            _ = try JSONDecoder().decode(BalanceResponse.self, from: data)
            return Self.assessment(from: .valid)
        } catch {
            return CredentialAssessmentSupport.probeFailed(manageURL: Self.manageKeysURL)
        }
    }

    nonisolated static func assessment(from probe: MoonshotCredentialProbeResult) -> CredentialAssessment {
        CredentialAssessment(
            keyTypeLabel: L("Valid key"),
            summary: L("Reads prepaid balance only."),
            detail: L("This key lets apps call Kimi models using your prepaid balance. AgentMeter only reads how much balance is left; it cannot spend money or change your account."),
            upgradeHint: nil,
            manageURL: manageKeysURL
        )
    }
}

enum MoonshotError: LocalizedError {
    case badResponse
    case invalidKey
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return L("Unexpected response from Kimi")
        case .invalidKey: return L("Kimi key rejected — check the key in Settings")
        case .httpStatus(let code): return L("Kimi returned HTTP \(code))")
        }
    }
}
