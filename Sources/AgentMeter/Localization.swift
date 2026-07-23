import Foundation

/// Looks up a localized string in the SPM resource bundle. SwiftUI's implicit
/// LocalizedStringKey lookup targets Bundle.main, which is empty for a
/// hand-bundled SwiftPM executable, so all user-facing strings go through this.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
