import XCTest
@testable import AgentMeter

final class CodexReaderTests: XCTestCase {
    /// A realistic token_count event line matching the Codex CLI rollout format.
    private let sampleLine = """
    {"timestamp":"2026-07-01T20:24:41.123Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":50}},"rate_limits":{"limit_id":"codex","limit_name":null,"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":1782955492},"secondary":{"used_percent":5.0,"window_minutes":10080,"resets_at":1783456449},"credits":null,"individual_limit":null,"plan_type":"pro","rate_limit_reached_type":null}}}
    """

    func testParsesSampleLine() throws {
        let usage = try XCTUnwrap(CodexUsageReader.parse(line: sampleLine))
        XCTAssertEqual(usage.planName, "Pro")
        XCTAssertEqual(usage.windows.count, 2)
        XCTAssertEqual(usage.windows[0].label, "5h limit")
        XCTAssertEqual(usage.windows[0].usedPercent, 12.5)
        XCTAssertEqual(usage.windows[1].label, "Weekly limit")
        XCTAssertEqual(usage.windows[1].usedPercent, 5.0)
        XCTAssertEqual(
            usage.windows[0].resetsAt,
            Date(timeIntervalSince1970: 1_782_955_492)
        )
        XCTAssertNotNil(usage.asOf)
    }

    func testParsesTimestampWithoutFractionalSeconds() throws {
        let line = sampleLine.replacingOccurrences(
            of: "2026-07-01T20:24:41.123Z",
            with: "2026-07-01T20:24:41Z"
        )
        let usage = try XCTUnwrap(CodexUsageReader.parse(line: line))
        XCTAssertNotNil(usage.asOf)
    }

    func testIgnoresLinesWithoutRateLimits() {
        XCTAssertNil(CodexUsageReader.parse(line: #"{"type":"event_msg","payload":{"type":"agent_message"}}"#))
    }

    func testWindowLabels() {
        XCTAssertEqual(CodexUsageReader.windowLabel(minutes: 60), "60m limit")
        XCTAssertEqual(CodexUsageReader.windowLabel(minutes: 300), "5h limit")
        XCTAssertEqual(CodexUsageReader.windowLabel(minutes: 10080), "Weekly limit")
        XCTAssertEqual(CodexUsageReader.windowLabel(minutes: 43200), "30d limit")
    }

    /// Integration test against the real Codex sessions on this machine.
    /// Skips cleanly on machines without Codex installed.
    func testReadsRealSessionsIfPresent() throws {
        let reader = CodexUsageReader()
        guard FileManager.default.fileExists(atPath: reader.sessionsRoot.path) else {
            throw XCTSkip("No ~/.codex/sessions directory on this machine")
        }
        let usage = try reader.readUsage()
        XCTAssertFalse(usage.windows.isEmpty)
        for window in usage.windows {
            XCTAssertGreaterThanOrEqual(window.usedPercent, 0)
            XCTAssertLessThanOrEqual(window.usedPercent, 100)
        }
    }
}
