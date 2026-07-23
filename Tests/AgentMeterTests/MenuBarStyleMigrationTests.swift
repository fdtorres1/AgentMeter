import XCTest
@testable import AgentMeter

@MainActor
final class MenuBarStyleMigrationTests: XCTestCase {
    func testMigratesLegacyCompactMenuBarTrue() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "compactMenuBar")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.menuBarStyle, .compact)
    }

    func testFreshDefaultsToFull() {
        let suiteName = "test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertEqual(settings.menuBarStyle, .full)
    }
}
