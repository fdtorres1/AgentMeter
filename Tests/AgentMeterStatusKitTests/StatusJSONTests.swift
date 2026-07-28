import XCTest
import AgentMeterStatusKit

final class StatusJSONTests: XCTestCase {
    private let schemaV1Fixture = """
    {
      "appVersion": "1.0",
      "generatedAt": "2026-07-28T20:15:00Z",
      "providers": [
        {
          "displayName": "Codex",
          "id": "codex",
          "state": "ready",
          "windows": [
            {
              "label": "5h",
              "resetsAt": "2026-07-28T22:00:00Z",
              "usedPercent": 42
            }
          ]
        }
      ],
      "schemaVersion": 1
    }
    """

    func testRoundTripPreservesValues() throws {
        let reset = Date(timeIntervalSince1970: 1_700_000_000)
        let generated = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = StatusSnapshot(
            generatedAt: generated,
            appVersion: "1.0",
            providers: [
                ProviderStatus(
                    id: "codex",
                    displayName: "Codex",
                    state: "ready",
                    windows: [
                        WindowStatus(label: "5h", usedPercent: 42, resetsAt: reset)
                    ]
                )
            ]
        )

        let data = try StatusJSON.encode(snapshot)
        let decoded = try StatusJSON.decode(data)

        XCTAssertEqual(decoded, snapshot)
    }

    func testFixtureUsesExactSchemaV1KeyNames() throws {
        let data = try XCTUnwrap(schemaV1Fixture.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(object["generatedAt"])
        XCTAssertNotNil(object["appVersion"])
        XCTAssertNotNil(object["providers"])

        let providers = try XCTUnwrap(object["providers"] as? [[String: Any]])
        let provider = try XCTUnwrap(providers.first)
        XCTAssertNotNil(provider["id"])
        XCTAssertNotNil(provider["displayName"])
        XCTAssertNotNil(provider["state"])
        XCTAssertNotNil(provider["windows"])

        let windows = try XCTUnwrap(provider["windows"] as? [[String: Any]])
        let window = try XCTUnwrap(windows.first)
        XCTAssertNotNil(window["label"])
        XCTAssertNotNil(window["usedPercent"])
        XCTAssertNotNil(window["resetsAt"])

        let decoded = try StatusJSON.decode(data)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.providers.first?.id, "codex")
    }
}
