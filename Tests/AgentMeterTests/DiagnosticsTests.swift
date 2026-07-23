import XCTest
@testable import AgentMeter

final class DiagnosticsTests: XCTestCase {
    private let secretKeyURL = "https://example.com/keys?token=SUPER_SECRET_PLANTED"

    func testFormatProviderIncludesWindowPercents() {
        let usage = ProviderUsage(
            planName: nil,
            windows: [
                UsageWindow(label: "5h", usedPercent: 42, resetsAt: nil),
                UsageWindow(label: "Weekly", usedPercent: 17, resetsAt: nil),
            ],
            asOf: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let text = Diagnostics.formatProvider(
            id: "codex",
            displayName: "Codex",
            detected: true,
            authKindName: "localCredentials",
            mode: .auto,
            showsInMenuBar: true,
            state: .ready(usage)
        )
        XCTAssertTrue(text.contains("5h: 42% used"))
        XCTAssertTrue(text.contains("Weekly: 17% used"))
        XCTAssertTrue(text.contains("as of"))
    }

    func testFormatProviderIncludesStaleError() {
        let since = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = ProviderUsage(
            planName: nil,
            windows: [UsageWindow(label: "5h", usedPercent: 50, resetsAt: nil)],
            asOf: nil
        )
        let text = Diagnostics.formatProvider(
            id: "cursor",
            displayName: "Cursor",
            detected: true,
            authKindName: "localCredentials",
            mode: .on,
            showsInMenuBar: true,
            state: .stale(usage, error: "HTTP 503", since: since)
        )
        XCTAssertTrue(text.contains("stale since"))
        XCTAssertTrue(text.contains("error: HTTP 503"))
    }

    func testFormatProviderErrorState() {
        let text = Diagnostics.formatProvider(
            id: "claude",
            displayName: "Claude",
            detected: false,
            authKindName: "localCredentials",
            mode: .off,
            showsInMenuBar: false,
            state: .error("token expired")
        )
        XCTAssertTrue(text.contains("error — token expired"))
    }

    func testAuthKindNameOmitsKeyURL() {
        let text = Diagnostics.formatProvider(
            id: "openrouter",
            displayName: "OpenRouter",
            detected: true,
            authKindName: "apiKey",
            mode: .on,
            showsInMenuBar: true,
            state: .loading
        )
        XCTAssertTrue(text.contains("Auth: apiKey"))
        XCTAssertFalse(text.contains(secretKeyURL))
        XCTAssertFalse(text.contains("keyURL"))
        XCTAssertFalse(text.contains("SUPER_SECRET_PLANTED"))
    }
}
