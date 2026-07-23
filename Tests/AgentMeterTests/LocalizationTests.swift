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
}
