import Foundation

/// How a provider authenticates, which determines its Settings UI.
enum ProviderAuthKind: Equatable {
    /// Reads credentials another app already stores locally (original model).
    case localCredentials
    /// User pastes an API key, stored in the app's own Keychain items.
    /// `keyURL` is where the user can create one.
    case apiKey(keyURL: String)
    /// Browser OAuth flow that provisions a key (e.g. OpenRouter PKCE).
    case oauth
}

/// A usage source shown in the menu bar (Codex, Cursor, Claude, Gemini, ...).
protocol UsageProvider: Sendable {
    /// Stable identifier used for settings persistence.
    var id: String { get }
    var displayName: String { get }
    /// Short code shown in the menu bar, e.g. "Cx".
    var shortCode: String { get }
    /// Whether this provider's local credentials/data appear to exist on this
    /// machine. Used by the "Auto" visibility mode. Must be cheap and must not
    /// trigger permission prompts (no network; own-app Keychain items only,
    /// which never prompt).
    var isDetected: Bool { get }
    var authKind: ProviderAuthKind { get }
    func fetch() async throws -> ProviderUsage
    var dashboardURL: URL? { get }
}

extension UsageProvider {
    var authKind: ProviderAuthKind { .localCredentials }

    /// Keychain account name for API-key providers.
    var keychainAccount: String { "apikey.\(id)" }

    /// Optional provider-specific guidance shown beside credential setup.
    var credentialHelpText: String? { nil }

    var apiKeyPlaceholder: String { L("API key") }

    var dashboardURL: URL? { nil }
}

enum ProviderKeyError: LocalizedError {
    case missingKey(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let name):
            return L("No \(name) API key set — add one in Settings")
        }
    }
}

/// Per-provider visibility preference.
enum ProviderMode: String, CaseIterable, Identifiable {
    /// Show when the provider is detected on this machine.
    case auto
    case on
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return L("Auto")
        case .on: return L("On")
        case .off: return L("Off")
        }
    }

    func isVisible(detected: Bool) -> Bool {
        switch self {
        case .auto: return detected
        case .on: return true
        case .off: return false
        }
    }
}
