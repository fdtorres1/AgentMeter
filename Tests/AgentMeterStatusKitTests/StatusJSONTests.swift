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

    func testRoundTripPreservesClaudeAPIUsageReport() throws {
        let periodStart = Date(timeIntervalSince1970: 1_800_000_000)
        let periodEnd = Date(timeIntervalSince1970: 1_800_086_400)
        let apiUsage = APIUsageStatus(
            costUSD: 12.34,
            inputTokens: 1_200,
            outputTokens: 340,
            cacheReadTokens: 500,
            cacheCreationTokens: 60,
            periodStart: periodStart,
            periodEnd: periodEnd
        )
        let snapshot = StatusSnapshot(
            generatedAt: periodEnd,
            appVersion: "1.12.0",
            providers: [ProviderStatus(
                id: "claude",
                displayName: "Claude",
                state: "ready",
                apiUsage: apiUsage
            )]
        )

        let decoded = try StatusJSON.decode(StatusJSON.encode(snapshot))
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.providers.first?.apiUsage?.prepaidCreditsStatus, "unavailable")
        XCTAssertNil(decoded.providers.first?.balance)
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
        XCTAssertNil(decoded.providers.first?.apiUsage)
    }
}
