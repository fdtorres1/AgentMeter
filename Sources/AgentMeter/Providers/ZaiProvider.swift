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

    var credentialHelpText: String? {
        L("Z.ai monitoring supports GLM Coding Plans only. Standard API billing and balance are not available through an API.")
    }

    var apiKeyPlaceholder: String {
        L("GLM Coding Plan API key")
    }

    var dashboardURL: URL? {
        URL(string: "https://z.ai/model-api")
    }

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
        if let error = Self.responseError(quota) {
            throw error
        }
        return Self.usage(from: quota, now: Date())
    }

    struct QuotaResponse: Decodable {
        let code: Int?
        let msg: String?
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

    nonisolated static func responseError(_ response: QuotaResponse) -> ZaiError? {
        guard let code = response.code, code != 200 else { return nil }
        let message = response.msg ?? ""
        if message.localizedCaseInsensitiveContains("coding plan")
            || message.contains("不存在coding plan") {
            return .noCodingPlan
        }
        return .apiError(code, message)
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
        case "TIME_LIMIT": return L("Time quota")
        case "TOKENS_LIMIT": return L("Token quota")
        default: return nil
        }
    }

    enum ZaiCredentialProbeResult: Equatable {
        case codingPlan
        case standardAPIKey
    }

    static let manageKeysURL = URL(string: "https://z.ai/manage-apikey/apikey-list")!

    func assessCredential() async -> CredentialAssessment? {
        guard let key = KeychainStore.get(keychainAccount) else { return nil }

        var request = URLRequest(url: Self.quotaURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await HTTP.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return CredentialAssessmentSupport.probeFailed(manageURL: Self.manageKeysURL)
            }
            if http.statusCode == 401 || http.statusCode == 403 {
                return CredentialAssessmentSupport.probeFailed(manageURL: Self.manageKeysURL)
            }
            guard http.statusCode == 200 else {
                return CredentialAssessmentSupport.probeFailed(manageURL: Self.manageKeysURL)
            }

            let quota = try JSONDecoder().decode(QuotaResponse.self, from: data)
            switch ZaiProvider.responseError(quota) {
            case .noCodingPlan:
                return Self.assessment(from: .standardAPIKey)
            case .some:
                return CredentialAssessmentSupport.probeFailed(manageURL: Self.manageKeysURL)
            case nil:
                return Self.assessment(from: .codingPlan)
            }
        } catch {
            return CredentialAssessmentSupport.probeFailed(manageURL: Self.manageKeysURL)
        }
    }

    nonisolated static func assessment(from probe: ZaiCredentialProbeResult) -> CredentialAssessment {
        switch probe {
        case .codingPlan:
            return CredentialAssessment(
                keyTypeLabel: L("GLM Coding Plan key"),
                summary: L("Shows your 5-hour and token quotas."),
                detail: L("This key is tied to a GLM Coding Plan subscription. AgentMeter reads your time and token quotas (they reset every few hours). It cannot spend money, call models, or change your account."),
                upgradeHint: nil,
                manageURL: manageKeysURL
            )
        case .standardAPIKey:
            return CredentialAssessment(
                keyTypeLabel: L("Standard API key"),
                summary: L("Valid key, but Z.ai only exposes usage for GLM Coding Plans"),
                detail: L("Your key is valid, but Z.ai does not publish usage or balance data for pay-as-you-go API keys. AgentMeter can only show numbers for GLM Coding Plan keys. Your key is fine for calling models — AgentMeter just has nothing to display."),
                upgradeHint: nil,
                manageURL: manageKeysURL
            )
        }
    }
}

enum ZaiError: LocalizedError {
    case badResponse
    case invalidKey
    case noCodingPlan
    case apiError(Int, String)
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse: return L("Unexpected response from Z.ai")
        case .invalidKey: return L("Z.ai key rejected — check the key in Settings")
        case .noCodingPlan:
            return L("Z.ai key is valid, but this account has no GLM Coding Plan")
        case .apiError(let code, let message):
            return message.isEmpty
                ? L("Z.ai API returned code \(code)")
                : L("Z.ai API returned code \(code): \(message)")
        case .httpStatus(let code): return L("Z.ai returned HTTP \(code)")
        }
    }
}
