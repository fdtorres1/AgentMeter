import Foundation
import Sparkle

/// Sparkle-backed auto-updates. The updater checks the appcast feed declared
/// in Info.plist (SUFeedURL, pointing at the latest GitHub release asset) and
/// verifies downloads against the EdDSA public key (SUPublicEDKey).
///
/// When running unbundled (swift run / tests) there is no Info.plist feed, so
/// the controller is created with automatic checks off and simply does nothing.
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: Bundle.main.bundleIdentifier != nil,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
