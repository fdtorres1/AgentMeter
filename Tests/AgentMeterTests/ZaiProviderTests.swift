import XCTest
@testable import AgentMeter

final class ZaiProviderTests: XCTestCase {
    func testQuotaMapping() throws {
        let json = #"{"code":200,"data":{"limits":[{"type":"TIME_LIMIT","percentage":34.0,"nextResetTime":1784800000000},{"type":"TOKENS_LIMIT","percentage":12.0,"nextResetTime":1784800000000}],"planName":"Coding Pro"},"success":true}"#
        let response = try JSONDecoder().decode(
            ZaiProvider.QuotaResponse.self,
            from: Data(json.utf8)
        )
        let usage = ZaiProvider.usage(from: response, now: Date())
        XCTAssertEqual(usage.planName, "Coding Pro")
        XCTAssertNil(usage.balance)
        XCTAssertEqual(usage.windows.count, 2)
        XCTAssertEqual(usage.windows[0].label, "Time quota")
        XCTAssertEqual(usage.windows[0].usedPercent, 34.0, accuracy: 0.001)
        XCTAssertEqual(usage.windows[1].label, "Token quota")
        XCTAssertEqual(usage.windows[1].usedPercent, 12.0, accuracy: 0.001)
        XCTAssertEqual(usage.menuSummary(direction: .used), "34%")

        let expectedReset = Date(timeIntervalSince1970: 1_784_800_000)
        XCTAssertEqual(usage.windows[0].resetsAt, expectedReset)
    }

    func testUnknownLimitTypesSkipped() throws {
        let json = #"{"code":200,"data":{"limits":[{"type":"UNKNOWN_TYPE","percentage":99.0},{"type":"TIME_LIMIT","percentage":50.0,"nextResetTime":1000000}],"planName":"Basic"},"success":true}"#
        let response = try JSONDecoder().decode(
            ZaiProvider.QuotaResponse.self,
            from: Data(json.utf8)
        )
        let usage = ZaiProvider.usage(from: response, now: Date())
        XCTAssertEqual(usage.windows.count, 1)
        XCTAssertEqual(usage.windows[0].label, "Time quota")
        XCTAssertEqual(usage.windows[0].usedPercent, 50.0, accuracy: 0.001)
        XCTAssertEqual(
            usage.windows[0].resetsAt,
            Date(timeIntervalSince1970: 1000)
        )
    }

    func testValidKeyWithoutCodingPlanGetsAccurateError() throws {
        let json = #"{"code":500,"msg":"当前用户不存在coding plan","success":false}"#
        let response = try JSONDecoder().decode(
            ZaiProvider.QuotaResponse.self,
            from: Data(json.utf8)
        )
        guard case .noCodingPlan = ZaiProvider.responseError(response) else {
            return XCTFail("Expected noCodingPlan")
        }
    }

    func testOtherBodyErrorIsNotClassifiedAsInvalidKey() throws {
        let json = #"{"code":503,"msg":"service unavailable","success":false}"#
        let response = try JSONDecoder().decode(
            ZaiProvider.QuotaResponse.self,
            from: Data(json.utf8)
        )
        guard case .apiError(let code, let message) = ZaiProvider.responseError(response) else {
            return XCTFail("Expected apiError")
        }
        XCTAssertEqual(code, 503)
        XCTAssertEqual(message, "service unavailable")
    }
}
