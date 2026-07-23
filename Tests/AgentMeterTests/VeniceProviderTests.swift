import XCTest
@testable import AgentMeter

final class VeniceProviderTests: XCTestCase {
    func testUSDBalanceMapping() throws {
        let json = #"{"canConsume":true,"consumptionCurrency":"USD","balances":{"usd":10.0,"diem":27.5},"diemEpochAllocation":100}"#
        let response = try JSONDecoder().decode(
            VeniceProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = VeniceProvider.usage(from: response, now: Date())
        XCTAssertTrue(usage.windows.isEmpty)
        let balance = try XCTUnwrap(usage.balance)
        XCTAssertEqual(balance.remaining, 10.0, accuracy: 0.001)
        XCTAssertNil(balance.used)
        XCTAssertEqual(balance.currencySymbol, "$")
        XCTAssertEqual(usage.menuSummary(direction: .used), "$10")
    }

    func testDIEMConsumptionCurrencySelection() throws {
        let json = #"{"canConsume":true,"consumptionCurrency":"DIEM","balances":{"usd":10.0,"diem":27.5}}"#
        let response = try JSONDecoder().decode(
            VeniceProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = VeniceProvider.usage(from: response, now: Date())
        let balance = try XCTUnwrap(usage.balance)
        XCTAssertEqual(balance.remaining, 27.5, accuracy: 0.001)
        XCTAssertEqual(balance.currencySymbol, "DIEM ")
        XCTAssertEqual(usage.menuSummary(direction: .used), "DIEM 28")
    }

    func testStringEncodedAndNullableOfficialBalances() throws {
        let json = #"{"canConsume":true,"consumptionCurrency":"USD","balances":{"usd":"4.61","diem":null},"diemEpochAllocation":"100"}"#
        let response = try JSONDecoder().decode(
            VeniceProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = VeniceProvider.usage(from: response, now: Date())
        XCTAssertEqual(try XCTUnwrap(usage.balance).remaining, 4.61, accuracy: 0.001)
        XCTAssertEqual(usage.balance?.currencySymbol, "$")
    }

    func testInferenceKeyRateLimitsFallbackMapping() throws {
        let json = #"{"data":{"accessPermitted":true,"balances":{"USD":4.6145621,"DIEM":0},"nextEpochBegins":"2026-07-24T00:00:00.000Z"}}"#
        let response = try JSONDecoder().decode(
            VeniceProvider.RateLimitsResponse.self,
            from: Data(json.utf8)
        )
        let usage = VeniceProvider.usage(from: response, now: Date())
        XCTAssertEqual(usage.planName, "Inference key")
        XCTAssertEqual(try XCTUnwrap(usage.balance).remaining, 4.6145621, accuracy: 0.000001)
        XCTAssertEqual(usage.balance?.currencySymbol, "$")
    }

    func testLegacyUppercaseBalanceShapeStillDecodes() throws {
        let json = #"{"canConsume":true,"consumptionCurrency":"DIEM","balances":{"USD":1.0,"DIEM":2.5}}"#
        let response = try JSONDecoder().decode(
            VeniceProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(VeniceProvider.usage(from: response, now: Date()).balance?.remaining, 2.5)
    }
}
