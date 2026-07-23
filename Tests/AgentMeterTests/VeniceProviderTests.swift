import XCTest
@testable import AgentMeter

final class VeniceProviderTests: XCTestCase {
    func testUSDBalanceMapping() throws {
        let json = #"{"canConsume":true,"consumptionCurrency":"USD","balances":{"USD":10.0,"DIEM":27.5,"VCU":0.0}}"#
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
        XCTAssertEqual(usage.menuSummary, "$10")
    }

    func testDIEMConsumptionCurrencySelection() throws {
        let json = #"{"canConsume":true,"consumptionCurrency":"DIEM","balances":{"USD":10.0,"DIEM":27.5,"VCU":0.0}}"#
        let response = try JSONDecoder().decode(
            VeniceProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = VeniceProvider.usage(from: response, now: Date())
        let balance = try XCTUnwrap(usage.balance)
        XCTAssertEqual(balance.remaining, 27.5, accuracy: 0.001)
        XCTAssertEqual(balance.currencySymbol, "DIEM ")
        XCTAssertEqual(usage.menuSummary, "DIEM 28")
    }
}
