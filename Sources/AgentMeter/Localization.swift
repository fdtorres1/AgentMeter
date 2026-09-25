import Foundation

enum LocalizationBundleError: Error, CustomStringConvertible {
    case missingPackagedResources(URL)

    var description: String {
        switch self {
        case .missingPackagedResources(let appURL):
            return "AgentMeter localization resources are missing from \(appURL.path)/Contents/Resources/AgentMeter_AgentMeter.bundle"
        }
    }
}

func resolveLocalizationBundle(
    mainBundle: Bundle,
    developmentBundle: () -> Bundle
) throws -> Bundle {
    let packagedBundleURL = mainBundle.resourceURL?
        .appendingPathComponent("AgentMeter_AgentMeter.bundle", isDirectory: true)

    if let packagedBundleURL, let bundle = Bundle(url: packagedBundleURL) {
        return bundle
    }

    if mainBundle.bundleURL.pathExtension == "app" {
        throw LocalizationBundleError.missingPackagedResources(mainBundle.bundleURL)
    }

    // Accessing Bundle.module can assert if its generated resource bundle is
    // absent, so keep the development fallback lazy until it is actually needed.
    return developmentBundle()
}

private enum LocalizationResources {
    static let bundle: Bundle = {
        do {
            return try resolveLocalizationBundle(mainBundle: .main) { .module }
        } catch {
            fatalError("AgentMeter startup failed: \(error)")
        }
    }()
}

/// Looks up a localized string in the SPM resource bundle. SwiftUI's implicit
/// LocalizedStringKey lookup targets Bundle.main, which is empty for a
/// hand-bundled SwiftPM executable, so all user-facing strings go through this.
func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: LocalizationResources.bundle)
}
