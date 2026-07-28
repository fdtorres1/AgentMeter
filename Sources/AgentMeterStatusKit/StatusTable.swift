import Foundation

public enum StatusTable {
    public static let defaultStalenessThreshold: TimeInterval = 600

    public static func isSnapshotStale(
        _ snapshot: StatusSnapshot,
        now: Date,
        threshold: TimeInterval = defaultStalenessThreshold
    ) -> Bool {
        now.timeIntervalSince(snapshot.generatedAt) > threshold
    }

    public static func renderStatusTable(
        _ snapshot: StatusSnapshot,
        now: Date = Date(),
        stalenessThreshold: TimeInterval = defaultStalenessThreshold
    ) -> String {
        var lines: [String] = []

        for (index, provider) in snapshot.providers.enumerated() {
            if index > 0 { lines.append("") }
            lines.append(provider.displayName)
            lines.append("  state: \(provider.state)")

            for window in provider.windows {
                var line = "  \(window.label): \(Int(window.usedPercent.rounded()))% used"
                if let resetsAt = window.resetsAt {
                    line += ", resets \(iso8601String(resetsAt))"
                }
                lines.append(line)
            }

            if let balance = provider.balance {
                let meaning = balance.kind == "remaining" ? "remaining" : "spent"
                lines.append("  balance: \(balance.currency)\(formatAmount(balance.amount)) \(meaning)")
            }

            if let asOf = provider.asOf {
                lines.append("  as of \(iso8601String(asOf))")
            }

            if let staleSince = provider.staleSince {
                lines.append("  stale since \(iso8601String(staleSince))")
            }

            if let error = provider.error {
                lines.append("  error: \(error)")
            }
        }

        if isSnapshotStale(snapshot, now: now, threshold: stalenessThreshold) {
            if !lines.isEmpty { lines.append("") }
            lines.append(
                "Warning: snapshot is older than \(Int(stalenessThreshold / 60)) minutes " +
                "(generated \(iso8601String(snapshot.generatedAt)))."
            )
        }

        return lines.joined(separator: "\n")
    }

    private static func iso8601String(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func formatAmount(_ value: Double) -> String {
        value == value.rounded() && value < 1000
            ? String(format: "%.0f", value)
            : String(format: "%.2f", value)
    }
}
