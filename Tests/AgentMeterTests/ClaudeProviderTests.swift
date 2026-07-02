import XCTest
@testable import AgentMeter

final class ClaudeProviderTests: XCTestCase {
    func testDecodeCredentialsMillisecondExpiry() throws {
        let json = """
        {"claudeAiOauth":{"accessToken":"at","refreshToken":"rt","expiresAt":1770073758676,"subscriptionType":"max"}}
        """
        let creds = try XCTUnwrap(ClaudeProvider.decodeCredentials(Data(json.utf8)))
        XCTAssertEqual(creds.accessToken, "at")
        XCTAssertEqual(creds.refreshToken, "rt")
        XCTAssertEqual(creds.subscriptionType, "max")
        // 1770073758676 ms == 2026-02-02, well in the past -> expired.
        XCTAssertTrue(creds.isExpired)
    }

    func testUsageMappingFromResponse() throws {
        let json = """
        {
          "five_hour": {"utilization": 12.5, "resets_at": "2026-07-01T20:24:41Z"},
          "seven_day": {"utilization": 5.0, "resets_at": "2026-07-08T00:00:00Z"},
          "seven_day_opus": {"utilization": 40.0, "resets_at": "2026-07-08T00:00:00Z"}
        }
        """
        let response = try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: Data(json.utf8))
        let usage = ClaudeProvider.usage(from: response, plan: "max", now: Date())
        XCTAssertEqual(usage.planName, "Max")
        XCTAssertEqual(usage.windows.map(\.label), ["5h limit", "Weekly limit", "Weekly (Opus)"])
        XCTAssertEqual(usage.worstWindow?.label, "Weekly (Opus)")
        XCTAssertEqual(usage.worstWindow?.usedPercent, 40.0)
        XCTAssertNotNil(usage.windows[0].resetsAt)
    }

    func testUsageMappingSkipsMissingWindows() throws {
        let json = #"{"five_hour": {"utilization": 3.0, "resets_at": "2026-07-01T20:24:41Z"}}"#
        let response = try JSONDecoder().decode(ClaudeProvider.UsageResponse.self, from: Data(json.utf8))
        let usage = ClaudeProvider.usage(from: response, plan: nil, now: Date())
        XCTAssertEqual(usage.windows.count, 1)
    }
}
