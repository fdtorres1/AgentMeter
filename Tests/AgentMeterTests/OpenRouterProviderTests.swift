import XCTest
@testable import AgentMeter

final class OpenRouterProviderTests: XCTestCase {
    func testCreditsMapping() throws {
        let json = #"{"data":{"total_credits":25.0,"total_usage":12.6}}"#
        let response = try JSONDecoder().decode(
            OpenRouterProvider.CreditsResponse.self,
            from: Data(json.utf8)
        )
        let usage = OpenRouterProvider.usage(from: response, now: Date())
        XCTAssertTrue(usage.windows.isEmpty)
        let balance = try XCTUnwrap(usage.balance)
        XCTAssertEqual(balance.remaining, 12.4, accuracy: 0.001)
        XCTAssertEqual(balance.used, 12.6)
        XCTAssertEqual(usage.menuSummary(direction: .used), "$12")
    }

    func testNegativeBalanceClampsToZero() throws {
        let json = #"{"data":{"total_credits":10.0,"total_usage":11.5}}"#
        let response = try JSONDecoder().decode(
            OpenRouterProvider.CreditsResponse.self,
            from: Data(json.utf8)
        )
        let usage = OpenRouterProvider.usage(from: response, now: Date())
        XCTAssertEqual(usage.balance?.remaining, 0)
    }

    func testRegularKeyWithLimitMapsToWindowAndRemainingBalance() throws {
        let json = #"{"data":{"limit":20.0,"limit_remaining":14.0,"usage":6.0,"usage_monthly":3.0}}"#
        let response = try JSONDecoder().decode(
            OpenRouterProvider.KeyResponse.self,
            from: Data(json.utf8)
        )
        let usage = OpenRouterProvider.usage(from: response, now: Date())
        XCTAssertEqual(usage.windows.first?.label, "Key limit")
        XCTAssertEqual(usage.windows.first?.usedPercent, 30)
        XCTAssertEqual(usage.balance?.remaining, 14)
        XCTAssertEqual(usage.balance?.used, 6)
        XCTAssertEqual(usage.balance?.kind, .remaining)
    }

    func testUncappedRegularKeyShowsMonthlySpendWithoutLowBalanceSemantics() throws {
        let json = #"{"data":{"limit":null,"limit_remaining":null,"usage":8.0,"usage_daily":0.5,"usage_weekly":2.0,"usage_monthly":3.25}}"#
        let response = try JSONDecoder().decode(
            OpenRouterProvider.KeyResponse.self,
            from: Data(json.utf8)
        )
        let usage = OpenRouterProvider.usage(from: response, now: Date())
        XCTAssertTrue(usage.windows.isEmpty)
        XCTAssertEqual(usage.balance?.remaining, 3.25)
        XCTAssertEqual(usage.balance?.kind, .spent)
        XCTAssertEqual(usage.balance?.display, "$3.25 used")
    }

    func testPKCEChallengeIsBase64URLOfSHA256() {
        // RFC 7636 appendix B test vector.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(
            OpenRouterAuthFlow.challenge(for: verifier),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func testVerifierIsURLSafeAndUnique() {
        let a = OpenRouterAuthFlow.randomVerifier()
        let b = OpenRouterAuthFlow.randomVerifier()
        XCTAssertNotEqual(a, b)
        XCTAssertNil(a.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testBalanceFormatting() {
        XCTAssertEqual(BalanceInfo(remaining: 12.4, used: nil, currencySymbol: "$").display, "$12.40 left")
        XCTAssertEqual(BalanceInfo(remaining: 5, used: nil, currencySymbol: "¥").display, "¥5 left")
        XCTAssertEqual(BalanceInfo(remaining: 123.456, used: nil, currencySymbol: "$").shortDisplay, "$123")
        XCTAssertEqual(BalanceInfo(remaining: 3.21, used: nil, currencySymbol: "$").shortDisplay, "$3.21")
    }
}
