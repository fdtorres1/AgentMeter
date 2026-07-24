import AppKit

enum MenuBarSeverity { case normal, warning, critical, stale }

@MainActor
enum MenuBarTitleRenderer {
    nonisolated static func severity(
        for state: ProviderState,
        balanceThreshold: Double
    ) -> MenuBarSeverity {
        switch state {
        case .stale:
            return .stale
        case .loading:
            return .normal
        case .error:
            return .critical
        case .ready(let usage):
            if let worst = usage.worstWindow {
                return menuBarSeverity(from: UsageMeterSeverity.forUsedPercent(worst.usedPercent))
            }
            if let balance = usage.balance, balance.kind == .remaining {
                return balance.remaining < balanceThreshold ? .warning : .normal
            }
            return .normal
        }
    }

    static func nsColor(for severity: MenuBarSeverity) -> NSColor {
        switch severity {
        case .normal: .labelColor
        case .warning: .systemYellow
        case .critical: .systemRed
        case .stale: .secondaryLabelColor
        }
    }

    nonisolated private static func menuBarSeverity(from meter: UsageMeterSeverity) -> MenuBarSeverity {
        switch meter {
        case .normal: .normal
        case .warning: .warning
        case .critical: .critical
        }
    }

    static func image(
        entries: [(text: String, severity: MenuBarSeverity)],
        accessibilityDescription: String
    ) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attributed = NSMutableAttributedString()
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                attributed.append(NSAttributedString(
                    string: " · ",
                    attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
                ))
            }
            attributed.append(NSAttributedString(
                string: entry.text,
                attributes: [.font: font, .foregroundColor: nsColor(for: entry.severity)]
            ))
        }
        let size = attributed.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { _ in
            attributed.draw(at: .zero)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    static func iconImage(severity: MenuBarSeverity, accessibilityDescription: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return NSImage(size: NSSize(width: 14, height: 14))
        }
        let color = nsColor(for: severity)
        let size = symbol.size
        let image = NSImage(size: size, flipped: false) { _ in
            color.set()
            symbol.draw(in: NSRect(origin: .zero, size: size))
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
