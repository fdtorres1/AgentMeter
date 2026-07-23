import Foundation

struct CredentialAssessment: Equatable {
    /// Short badge text, e.g. "Inference key", "Admin key", "GLM Coding Plan key", "Valid key".
    let keyTypeLabel: String
    /// One-line always-visible summary in plain language.
    let summary: String
    /// Expanded plain-language explanation (2-5 short sentences).
    let detail: String
    /// Optional suggestion when a more capable key exists (nil when the current key is already ideal or no alternative exists).
    let upgradeHint: String?
    /// Provider's key management page.
    let manageURL: URL?
}

extension UsageProvider {
    func assessCredential() async -> CredentialAssessment? { nil }
}

enum CredentialAssessmentSupport {
    nonisolated static func probeFailed(manageURL: URL?) -> CredentialAssessment {
        CredentialAssessment(
            keyTypeLabel: L("Couldn't check key"),
            summary: L("Verification failed — your key may still work."),
            detail: L("AgentMeter could not reach the provider to check this key. That is usually a network issue or a temporary API change. Your saved key was not removed."),
            upgradeHint: nil,
            manageURL: manageURL
        )
    }
}
