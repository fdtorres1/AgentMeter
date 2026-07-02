import XCTest
@testable import AgentMeter

final class CursorFetcherTests: XCTestCase {
    func testJWTSubjectExtraction() throws {
        // Header/payload/signature with payload {"sub":"user_123"}
        let payload = Data(#"{"sub":"user_123"}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "")
        let token = "eyJhbGciOiJSUzI1NiJ9.\(payload).sig"
        XCTAssertEqual(try CursorUsageFetcher.jwtSubject(from: token), "user_123")
    }

    func testCookieHeaderEncodesSeparator() throws {
        let cookie = try CursorUsageFetcher.cookieHeader(sub: "user_123", token: "abc")
        XCTAssertEqual(cookie, "WorkosCursorSessionToken=user%5F123%3A%3Aabc")
    }

    func testUsageMappingFromSummary() throws {
        let json = """
        {
          "billingCycleEnd": "2026-07-22T04:35:56.000Z",
          "membershipType": "ultra",
          "individualUsage": {
            "plan": {
              "used": 9793,
              "limit": 40000,
              "autoPercentUsed": 0,
              "apiPercentUsed": 19.586,
              "totalPercentUsed": 6.5286
            }
          }
        }
        """
        let summary = try JSONDecoder().decode(
            CursorUsageFetcher.UsageSummary.self,
            from: Data(json.utf8)
        )
        let usage = CursorUsageFetcher.usage(from: summary, now: Date())
        XCTAssertEqual(usage.planName, "Ultra")
        XCTAssertEqual(usage.windows.map(\.label), ["Included usage", "Auto usage", "API usage"])
        XCTAssertEqual(usage.worstWindow?.label, "API usage")
        XCTAssertEqual(usage.worstWindow?.usedPercent ?? 0, 19.586, accuracy: 0.001)
        XCTAssertNotNil(usage.windows[0].resetsAt)
    }

    func testTeamAccountFallbackToPersonalCap() throws {
        // Enterprise/team account with no `plan` block, only an overall cap.
        let json = """
        {
          "billingCycleEnd": "2026-07-22T04:35:56.000Z",
          "membershipType": "enterprise",
          "individualUsage": { "overall": { "used": 2500, "limit": 10000 } },
          "teamUsage": {}
        }
        """
        let summary = try JSONDecoder().decode(
            CursorUsageFetcher.UsageSummary.self,
            from: Data(json.utf8)
        )
        let usage = CursorUsageFetcher.usage(from: summary, now: Date())
        XCTAssertEqual(usage.windows.map(\.label), ["Personal cap"])
        XCTAssertEqual(usage.windows.first?.usedPercent, 25.0)
    }

    func testTeamPooledFallback() throws {
        let json = """
        {
          "membershipType": "team",
          "individualUsage": {},
          "teamUsage": { "pooled": { "used": 9000, "limit": 10000 } }
        }
        """
        let summary = try JSONDecoder().decode(
            CursorUsageFetcher.UsageSummary.self,
            from: Data(json.utf8)
        )
        let usage = CursorUsageFetcher.usage(from: summary, now: Date())
        XCTAssertEqual(usage.windows.map(\.label), ["Team pool"])
        XCTAssertEqual(usage.windows.first?.usedPercent, 90.0)
    }

    /// Full live round-trip using the real local Cursor token.
    /// Opt-in via CURSOR_LIVE_TEST=1 so CI/other machines skip it.
    func testLiveFetchIfEnabled() async throws {
        guard ProcessInfo.processInfo.environment["CURSOR_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CURSOR_LIVE_TEST=1 to run the live Cursor fetch test")
        }
        let usage = try await CursorUsageFetcher().fetchUsage()
        XCTAssertFalse(usage.windows.isEmpty)
        for window in usage.windows {
            XCTAssertGreaterThanOrEqual(window.usedPercent, 0)
            XCTAssertLessThanOrEqual(window.usedPercent, 100)
        }
    }
}
