import XCTest
@testable import AgentMeter

final class LocalizationTests: XCTestCase {
    func testSpanishTranslationsExistInCatalog() throws {
        let catalogURL = Bundle.module.url(
            forResource: "Localizable",
            withExtension: "xcstrings"
        )
        let url = try XCTUnwrap(catalogURL)
        let data = try Data(contentsOf: url)

        struct StringUnit: Decodable {
            let state: String
            let value: String
        }

        struct Localization: Decodable {
            let stringUnit: StringUnit
        }

        struct Entry: Decodable {
            let localizations: [String: Localization]?
        }

        struct Catalog: Decodable {
            let strings: [String: Entry]
        }

        let catalog = try JSONDecoder().decode(Catalog.self, from: data)
        let sampleKeys = [
            "Refresh",
            "Weekly limit",
            "resets soon",
            "% left",
            "Balance",
        ]

        for key in sampleKeys {
            let entry = try XCTUnwrap(catalog.strings[key], "Missing catalog entry for \(key)")
            let spanish = try XCTUnwrap(
                entry.localizations?["es"]?.stringUnit.value,
                "Missing Spanish translation for \(key)"
            )
            XCTAssertFalse(spanish.isEmpty, "Empty Spanish translation for \(key)")
        }
    }

    func testLReturnsEnglishByDefault() {
        XCTAssertEqual(L("Refresh"), "Refresh")
        XCTAssertEqual(L("Weekly limit"), "Weekly limit")
    }

    func testPackagedAppUsesResourcesBundleBeforeDevelopmentFallback() throws {
        let appURL = try makeAppFixture()
        defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }
        let appBundle = try XCTUnwrap(Bundle(url: appURL))
        var fallbackWasCalled = false

        let resources = try resolveLocalizationBundle(mainBundle: appBundle) {
            fallbackWasCalled = true
            return .module
        }

        XCTAssertFalse(fallbackWasCalled)
        XCTAssertEqual(
            resources.localizedString(forKey: "Packaged probe", value: nil, table: nil),
            "From packaged bundle"
        )
    }

    func testPackagedAppMissingResourcesDoesNotUseDevelopmentFallback() throws {
        let appURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("MissingResources.app")
        try FileManager.default.createDirectory(
            at: appURL.appendingPathComponent("Contents", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: appURL.deletingLastPathComponent()) }
        try Data("<?xml version=\"1.0\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.missing</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>".utf8)
            .write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let appBundle = try XCTUnwrap(Bundle(url: appURL))
        var fallbackWasCalled = false

        XCTAssertThrowsError(try resolveLocalizationBundle(mainBundle: appBundle) {
            fallbackWasCalled = true
            return .module
        }) { error in
            XCTAssertTrue(String(describing: error).contains("localization resources are missing"))
        }
        XCTAssertFalse(fallbackWasCalled)
    }

    private func makeAppFixture() throws -> URL {
        let baseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let appURL = baseURL.appendingPathComponent("Fixture.app", isDirectory: true)
        let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        let bundleURL = resourcesURL.appendingPathComponent("AgentMeter_AgentMeter.bundle", isDirectory: true)
        let englishURL = bundleURL.appendingPathComponent("en.lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: englishURL, withIntermediateDirectories: true)
        let info = "<?xml version=\"1.0\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.agentmeter.resources</string><key>CFBundlePackageType</key><string>BNDL</string></dict></plist>"
        try Data(info.utf8).write(to: bundleURL.appendingPathComponent("Info.plist"))
        let appInfo = "<?xml version=\"1.0\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>test.agentmeter.app</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>"
        try Data(appInfo.utf8).write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        try Data("\"Packaged probe\" = \"From packaged bundle\";".utf8)
            .write(to: englishURL.appendingPathComponent("Localizable.strings"))
        return appURL
    }
}
