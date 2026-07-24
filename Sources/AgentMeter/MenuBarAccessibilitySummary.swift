import Foundation

/// Builds the spoken menu bar summary for VoiceOver (pure, testable).
enum MenuBarAccessibilitySummary {
    struct ProviderInput: Equatable {
        let displayName: String
        let state: ProviderState
    }

    nonisolated static func build(
        providers: [ProviderInput],
        countDirection: CountDirection,
        balanceThreshold: Double
    ) -> String {
        guard !providers.isEmpty else { return L("AgentMeter") }

        let segments = providers.map {
            providerSegment(
                displayName: $0.displayName,
                state: $0.state,
                countDirection: countDirection,
                balanceThreshold: balanceThreshold
            )
        }
        return ([L("AgentMeter")] + segments).joined(separator: ". ")
    }

    nonisolated static func providerSegment(
        displayName: String,
        state: ProviderState,
        countDirection: CountDirection,
        balanceThreshold: Double
    ) -> String {
        switch state {
        case .loading:
            return String(format: L("%@: %@"), displayName, L("loading"))
        case .error:
            return String(format: L("%@: %@"), displayName, L("error"))
        case .stale(let usage, _, _):
            if let value = usageValue(
                usage: usage,
                countDirection: countDirection,
                balanceThreshold: balanceThreshold
            ) {
                return appendQualifier(
                    String(format: L("%@: %@"), displayName, value),
                    L("data is stale")
                )
            }
            return String(format: L("%@: %@"), displayName, L("data is stale"))
        case .ready(let usage):
            let value = usageValue(
                usage: usage,
                countDirection: countDirection,
                balanceThreshold: balanceThreshold
            ) ?? L("No usage data")
            return String(format: L("%@: %@"), displayName, value)
        }
    }

    nonisolated private static func usageValue(
        usage: ProviderUsage,
        countDirection: CountDirection,
        balanceThreshold: Double
    ) -> String? {
        if let worst = usage.worstWindow {
            var text = countDirection.accessibilityPercentPhrase(worst.usedPercent)
            if let qualifier = UsageMeterSeverity.forUsedPercent(worst.usedPercent).qualifier {
                text = appendQualifier(text, qualifier)
            }
            return text
        }
        if let balance = usage.balance {
            var text = balance.accessibilityPhrase
            if balance.kind == .remaining, balance.remaining < balanceThreshold {
                text = appendQualifier(text, L("low balance"))
            }
            return text
        }
        return nil
    }

    nonisolated static func appendQualifier(_ text: String, _ qualifier: String) -> String {
        "\(text), \(qualifier)"
    }
}

extension CountDirection {
    nonisolated func accessibilityPercentPhrase(_ usedPercent: Double) -> String {
        let value = Int(displayPercent(usedPercent).rounded())
        switch self {
        case .used: return L("\(value)% used")
        case .remaining: return L("\(value)% remaining")
        }
    }
}

extension BalanceInfo {
    var accessibilityPhrase: String { display }
}
