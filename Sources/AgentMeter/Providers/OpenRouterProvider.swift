import Foundation
import AppKit
import CryptoKit

/// OpenRouter credits, authenticated by a key stored in the app's Keychain.
///
/// The key can be provisioned two ways: pasted manually, or via OpenRouter's
/// OAuth PKCE flow ("Connect" in Settings), which asks the user to approve in
/// the browser and then calls back with a code we exchange for a dedicated,
/// individually revocable API key. Either way the key only ever goes to
/// openrouter.ai.
struct OpenRouterProvider: UsageProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"
    let shortCode = "OR"

    static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!

    var isDetected: Bool {
        KeychainStore.exists(keychainAccount)
    }

    var authKind: ProviderAuthKind { .oauth }

    func fetch() async throws -> ProviderUsage {
        guard let key = KeychainStore.get(keychainAccount) else {
            throw ProviderKeyError.missingKey(displayName)
        }

        var request = URLRequest(url: Self.creditsURL)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenRouterError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw OpenRouterError.invalidKey
        }
        guard http.statusCode == 200 else { throw OpenRouterError.httpStatus(http.statusCode) }

        let credits = try JSONDecoder().decode(CreditsResponse.self, from: data)
        return Self.usage(from: credits, now: Date())
    }

    struct CreditsResponse: Decodable {
        struct Payload: Decodable {
            let totalCredits: Double
            let totalUsage: Double
            enum CodingKeys: String, CodingKey {
                case totalCredits = "total_credits"
                case totalUsage = "total_usage"
            }
        }
        let data: Payload
    }

    static func usage(from response: CreditsResponse, now: Date) -> ProviderUsage {
        let remaining = max(0, response.data.totalCredits - response.data.totalUsage)
        return ProviderUsage(
            planName: "Credits",
            windows: [],
            asOf: now,
            balance: BalanceInfo(
                remaining: remaining,
                used: response.data.totalUsage,
                currencySymbol: "$"
            )
        )
    }
}

enum OpenRouterError: LocalizedError {
    case badResponse
    case invalidKey
    case httpStatus(Int)
    case authFlowFailed(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "Unexpected response from OpenRouter"
        case .invalidKey: return "OpenRouter key rejected — reconnect in Settings"
        case .httpStatus(let code): return "OpenRouter returned HTTP \(code)"
        case .authFlowFailed(let reason): return "OpenRouter connect failed: \(reason)"
        }
    }
}

/// OpenRouter OAuth PKCE flow. Provisions a dedicated API key for AgentMeter.
///
/// Flow: generate a code verifier, open openrouter.ai/auth in the browser with
/// its SHA-256 challenge and `agentmeter://openrouter` as the callback; on
/// approval the browser opens that URL with a `code`, which we exchange for an
/// API key and store in the Keychain. The verifier never leaves this process.
@MainActor
final class OpenRouterAuthFlow {
    static let shared = OpenRouterAuthFlow()
    static let callbackScheme = "agentmeter"
    static let callbackHost = "openrouter"

    private var pendingVerifier: String?

    func start() {
        let verifier = Self.randomVerifier()
        pendingVerifier = verifier
        let challenge = Self.challenge(for: verifier)

        var components = URLComponents(string: "https://openrouter.ai/auth")!
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: "\(Self.callbackScheme)://\(Self.callbackHost)"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        NSWorkspace.shared.open(components.url!)
    }

    /// Handles the agentmeter://openrouter?code=... callback.
    /// Returns true if the URL was consumed.
    func handleCallback(_ url: URL, onComplete: @escaping (Result<Void, Error>) -> Void) -> Bool {
        guard url.scheme == Self.callbackScheme, url.host == Self.callbackHost else { return false }
        guard let verifier = pendingVerifier,
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "code" })?.value else {
            onComplete(.failure(OpenRouterError.authFlowFailed("missing code")))
            return true
        }
        pendingVerifier = nil

        Task {
            do {
                let key = try await Self.exchange(code: code, verifier: verifier)
                KeychainStore.set(key, account: OpenRouterProvider().keychainAccount)
                onComplete(.success(()))
            } catch {
                onComplete(.failure(error))
            }
        }
        return true
    }

    static func exchange(code: String, verifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "code": code,
            "code_verifier": verifier,
            "code_challenge_method": "S256",
        ])

        let (data, response) = try await HTTP.session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw OpenRouterError.authFlowFailed("key exchange rejected")
        }
        struct KeyResponse: Decodable { let key: String }
        return try JSONDecoder().decode(KeyResponse.self, from: data).key
    }

    static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
