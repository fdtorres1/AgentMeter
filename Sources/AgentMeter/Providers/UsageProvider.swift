import Foundation

/// A usage source shown in the menu bar (Codex, Cursor, Claude, Gemini, ...).
protocol UsageProvider: Sendable {
    /// Stable identifier used for settings persistence.
    var id: String { get }
    var displayName: String { get }
    /// Short code shown in the menu bar, e.g. "Cx".
    var shortCode: String { get }
    /// Whether this provider's local credentials/data appear to exist on this
    /// machine. Used by the "Auto" visibility mode. Must be cheap and must not
    /// trigger permission prompts (no Keychain, no network).
    var isDetected: Bool { get }
    func fetch() async throws -> ProviderUsage
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
        case .auto: return "Auto"
        case .on: return "On"
        case .off: return "Off"
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
