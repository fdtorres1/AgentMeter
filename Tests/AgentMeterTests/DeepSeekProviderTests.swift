import XCTest
@testable import AgentMeter

final class DeepSeekProviderTests: XCTestCase {
    func testBalanceMapping() throws {
        let json = #"{"is_available":true,"balance_infos":[{"currency":"USD","total_balance":"12.50","granted_balance":"0.00","topped_up_balance":"12.50"}]}"#
        let response = try JSONDecoder().decode(
            DeepSeekProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = DeepSeekProvider.usage(from: response, now: Date())
        XCTAssertTrue(usage.windows.isEmpty)
        XCTAssertNil(usage.planName)
        let balance = try XCTUnwrap(usage.balance)
        XCTAssertEqual(balance.remaining, 12.50, accuracy: 0.001)
        XCTAssertNil(balance.used)
        XCTAssertEqual(balance.currencySymbol, "$")
        XCTAssertEqual(usage.menuSummary, "$12")
    }

    func testCNYFallbackWhenNoUSD() throws {
        let json = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"88.00","granted_balance":"0.00","topped_up_balance":"88.00"}]}"#
        let response = try JSONDecoder().decode(
            DeepSeekProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = DeepSeekProvider.usage(from: response, now: Date())
        let balance = try XCTUnwrap(usage.balance)
        XCTAssertEqual(balance.remaining, 88.0, accuracy: 0.001)
        XCTAssertEqual(balance.currencySymbol, "¥")
        XCTAssertEqual(usage.menuSummary, "¥88")
    }
}
