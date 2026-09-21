import XCTest
import AgentMeterStatusKit

final class CLIArgumentParserTests: XCTestCase {
    func testNoArgsIsUsageError() {
        XCTAssertEqual(CLIArgumentParser.parse([]), .failure(.usage))
    }

    func testHelpAndVersion() {
        XCTAssertEqual(CLIArgumentParser.parse(["--help"]), .success(.help))
        XCTAssertEqual(CLIArgumentParser.parse(["-h"]), .success(.help))
        XCTAssertEqual(CLIArgumentParser.parse(["--version"]), .success(.version))
    }

    func testStatusJsonFlag() {
        XCTAssertEqual(CLIArgumentParser.parse(["status"]), .success(.status(json: false)))
        XCTAssertEqual(CLIArgumentParser.parse(["status", "--json"]), .success(.status(json: true)))
        XCTAssertEqual(CLIArgumentParser.parse(["status", "--verbose"]), .failure(.usage))
    }

    func testRefreshWaitParsing() {
        XCTAssertEqual(CLIArgumentParser.parse(["refresh"]), .success(.refresh(waitSeconds: 0)))
        XCTAssertEqual(CLIArgumentParser.parse(["refresh", "--wait", "5"]), .success(.refresh(waitSeconds: 5)))
        XCTAssertEqual(CLIArgumentParser.parse(["refresh", "--wait"]), .failure(.usage))
        XCTAssertEqual(CLIArgumentParser.parse(["refresh", "--wait", "-1"]), .failure(.usage))
    }

    func testDoctorRejectsExtraArgs() {
        XCTAssertEqual(CLIArgumentParser.parse(["doctor"]), .success(.doctor))
        XCTAssertEqual(CLIArgumentParser.parse(["doctor", "--json"]), .failure(.usage))
    }

    func testSkillRejectsExtraArgs() {
        XCTAssertEqual(CLIArgumentParser.parse(["skill"]), .success(.skill))
        XCTAssertEqual(CLIArgumentParser.parse(["skill", "--json"]), .failure(.usage))
    }

    func testUnknownCommandIsUsageError() {
        XCTAssertEqual(CLIArgumentParser.parse(["unknown"]), .failure(.usage))
    }
}
