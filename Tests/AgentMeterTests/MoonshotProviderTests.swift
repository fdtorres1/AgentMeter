import XCTest
@testable import AgentMeter

final class MoonshotProviderTests: XCTestCase {
    func testBalanceMapping() throws {
        let json = #"{"code":0,"data":{"available_balance":8.13,"voucher_balance":5.0,"cash_balance":3.13},"status":true}"#
        let response = try JSONDecoder().decode(
            MoonshotProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = MoonshotProvider.usage(from: response, now: Date())
        XCTAssertTrue(usage.windows.isEmpty)
        let balance = try XCTUnwrap(usage.balance)
        XCTAssertEqual(balance.remaining, 8.13, accuracy: 0.001)
        XCTAssertNil(balance.used)
        XCTAssertEqual(balance.currencySymbol, "$")
        XCTAssertEqual(usage.menuSummary(direction: .used), "$8.13")
    }

    func testNegativeAvailableBalanceClampsToZero() throws {
        let json = #"{"code":0,"data":{"available_balance":-2.5,"voucher_balance":0.0,"cash_balance":-2.5},"status":true}"#
        let response = try JSONDecoder().decode(
            MoonshotProvider.BalanceResponse.self,
            from: Data(json.utf8)
        )
        let usage = MoonshotProvider.usage(from: response, now: Date())
        XCTAssertEqual(usage.balance?.remaining, 0)
        XCTAssertEqual(usage.menuSummary(direction: .used), "$0")
    }
}
