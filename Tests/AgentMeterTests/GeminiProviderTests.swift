import XCTest
@testable import AgentMeter

final class GeminiProviderTests: XCTestCase {
    func testUsageMappingGroupsByFamilyAndInverts() throws {
        let json = """
        {
          "buckets": [
            {"modelId": "gemini-2.5-pro", "remainingFraction": 0.8, "resetTime": "2026-07-02T00:00:00Z"},
            {"modelId": "gemini-2.5-pro", "remainingFraction": 0.6, "resetTime": "2026-07-02T00:00:00Z"},
            {"modelId": "gemini-2.5-flash", "remainingFraction": 0.95, "resetTime": "2026-07-02T00:00:00Z"},
            {"modelId": "gemini-2.5-flash-lite", "remainingFraction": 1.0, "resetTime": "2026-07-02T00:00:00Z"}
          ]
        }
        """
        let response = try JSONDecoder().decode(GeminiProvider.QuotaResponse.self, from: Data(json.utf8))
        let usage = GeminiProvider.usage(from: response, plan: "Free", now: Date())
        XCTAssertEqual(usage.planName, "Free")
        XCTAssertEqual(usage.windows.map(\.label), ["Pro (24h)", "Flash (24h)", "Flash-Lite (24h)"])
        // Pro keeps the worst (lowest remaining 0.6 -> 40% used).
        XCTAssertEqual(usage.windows[0].usedPercent, 40.0, accuracy: 0.001)
        XCTAssertEqual(usage.windows[1].usedPercent, 5.0, accuracy: 0.001)
        XCTAssertEqual(usage.windows[2].usedPercent, 0.0, accuracy: 0.001)
    }

    func testUsageMappingIgnoresUnknownModels() throws {
        let json = #"{"buckets":[{"modelId":"imagen-3","remainingFraction":0.5,"resetTime":null}]}"#
        let response = try JSONDecoder().decode(GeminiProvider.QuotaResponse.self, from: Data(json.utf8))
        let usage = GeminiProvider.usage(from: response, plan: nil, now: Date())
        XCTAssertTrue(usage.windows.isEmpty)
    }
}
