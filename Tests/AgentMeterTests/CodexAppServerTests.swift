import XCTest
@testable import AgentMeter

final class CodexAppServerTests: XCTestCase {
    private let loggedInAccountJSON = """
    {"id":2,"result":{"account":{"type":"chatgpt","email":"user@example.com","planType":"prolite"},"requiresOpenaiAuth":true}}
    """

    private let nullAccountJSON = """
    {"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}
    """

    private let rateLimitsJSON = """
    {"id":3,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1790572320},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"prolite"},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":1790572320},"secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"prolite"}}}}
    """

    private let authRequiredJSON = """
    {"error":{"code":-32600,"message":"codex account authentication required to read rate limits"},"id":3}
    """

    func testParseAccountLoggedIn() throws {
        let object = try jsonObject(loggedInAccountJSON)
        let parsed = CodexAppServerClient.parseAccount(object)
        XCTAssertEqual(parsed?.email, "user@example.com")
        XCTAssertEqual(parsed?.planType, "prolite")
    }

    func testParseAccountNull() throws {
        let object = try jsonObject(nullAccountJSON)
        let parsed = CodexAppServerClient.parseAccount(object)
        XCTAssertEqual(parsed?.email, nil)
        XCTAssertEqual(parsed?.planType, nil)
    }

    func testParseRateLimits() throws {
        let object = try jsonObject(rateLimitsJSON)
        let limits = try XCTUnwrap(CodexAppServerClient.parseRateLimits(object))
        XCTAssertEqual(limits.limitId, "codex")
        XCTAssertEqual(limits.planType, "prolite")
        XCTAssertEqual(limits.primary?.usedPercent, 7)
        XCTAssertEqual(limits.primary?.windowMinutes, 10080)
        XCTAssertEqual(limits.secondary, nil)
        XCTAssertEqual(limits.credits?.hasCredits, false)
    }

    func testAuthenticationRequiredError() throws {
        let object = try jsonObject(authRequiredJSON)
        XCTAssertTrue(CodexAppServerClient.isAuthenticationRequiredError(object))
        XCTAssertNil(CodexAppServerClient.parseRateLimits(object))
    }

    func testUsageMapping() {
        let reading = CodexAccountReading(
            email: "user@example.com",
            planType: "prolite",
            rateLimits: CodexRateLimits(
                primary: CodexWindow(usedPercent: 7, windowMinutes: 10080, resetsAt: nil),
                secondary: CodexWindow(usedPercent: 3, windowMinutes: 300, resetsAt: nil),
                limitId: "codex",
                planType: "prolite",
                credits: CodexCredits(hasCredits: false, unlimited: false, balance: "0")
            )
        )
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let usage = CodexAppServerClient.usage(from: reading, now: now)

        XCTAssertEqual(usage.planName, "Pro Lite")
        XCTAssertEqual(usage.windows.count, 2)
        XCTAssertEqual(usage.windows[0].label, "Weekly limit")
        XCTAssertEqual(usage.windows[1].label, "5h limit")
        XCTAssertEqual(usage.asOf, now)
        XCTAssertNil(usage.balance)
    }

    func testUsageIncludesCreditsWhenPresent() {
        let reading = CodexAccountReading(
            email: "user@example.com",
            planType: "pro",
            rateLimits: CodexRateLimits(
                primary: nil,
                secondary: nil,
                limitId: "codex",
                planType: "pro",
                credits: CodexCredits(hasCredits: true, unlimited: false, balance: "12.50")
            )
        )
        let usage = CodexAppServerClient.usage(from: reading, now: Date())
        XCTAssertEqual(usage.balance?.remaining, 12.5)
        XCTAssertEqual(usage.balance?.currencySymbol, "$")
    }

    func testCandidatePathsOrdering() {
        let paths = CodexAppServerClient.candidatePaths(
            home: "/Users/test",
            pathEnv: "/custom/bin:/another/bin"
        )
        XCTAssertEqual(paths[0], "/opt/homebrew/bin/codex")
        XCTAssertEqual(paths[1], "/usr/local/bin/codex")
        XCTAssertEqual(paths[2], "/Users/test/.local/bin/codex")
        XCTAssertTrue(paths.contains("/custom/bin/codex"))
        XCTAssertTrue(paths.contains("/another/bin/codex"))
    }

    func testSuggestedHomePathSlug() {
        XCTAssertEqual(
            CodexAccountConfig.suggestedHomePath(for: "Work Account"),
            "~/.codex-work-account"
        )
        XCTAssertEqual(
            CodexAccountConfig.suggestedHomePath(for: "  "),
            "~/.codex-account"
        )
    }

    func testLoginCommandCreatesHomeFirst() {
        XCTAssertEqual(
            CodexAccountConfig.loginCommand(homePath: "~/.codex-main"),
            "mkdir -p ~/.codex-main && CODEX_HOME=~/.codex-main codex login"
        )
        XCTAssertEqual(
            CodexAccountConfig.loginCommand(homePath: "/Volumes/My Disk/codex home"),
            "mkdir -p '/Volumes/My Disk/codex home' && CODEX_HOME='/Volumes/My Disk/codex home' codex login"
        )
    }

    func testCodexAccountConfigCodableRoundTrip() throws {
        let original = CodexAccountConfig(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            label: "Work",
            codexHomePath: "~/.codex-work"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CodexAccountConfig.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testExtraProviderIdentity() {
        let config = CodexAccountConfig(label: "Work", codexHomePath: "~/.codex-work")
        let provider = CodexProvider(accountConfig: config)
        XCTAssertEqual(provider.id, "codex:\(config.id.uuidString)")
        XCTAssertEqual(provider.displayName, "Codex — Work")
        XCTAssertEqual(provider.shortCode, "CxW")
        XCTAssertFalse(provider.isPrimary)
    }

    func testPrimaryProviderIdentity() {
        let provider = CodexProvider()
        XCTAssertEqual(provider.id, "codex")
        XCTAssertEqual(provider.displayName, "Codex")
        XCTAssertEqual(provider.shortCode, "Cx")
        XCTAssertTrue(provider.isPrimary)
    }

    @MainActor
    func testSettingsStorePersistsExtraAccounts() {
        let defaults = UserDefaults(suiteName: "CodexAppServerTests")!
        defaults.removePersistentDomain(forName: "CodexAppServerTests")
        let settings = SettingsStore(defaults: defaults)
        let account = CodexAccountConfig(label: "Alt", codexHomePath: "~/.codex-alt")
        settings.addCodexAccount(account)
        XCTAssertEqual(settings.codexExtraAccounts.count, 1)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.codexExtraAccounts, [account])
        defaults.removePersistentDomain(forName: "CodexAppServerTests")
    }

    func testCodexPlanDisplayNames() {
        XCTAssertEqual(CodexPlan.displayName("prolite"), "Pro Lite")
        XCTAssertEqual(CodexPlan.displayName("pro"), "Pro")
        XCTAssertEqual(CodexPlan.displayName("team"), "Team")
        XCTAssertEqual(CodexPlan.displayName("unknown"), "Unknown")
    }

    func testDefaultProvidersIncludesExtras() {
        let config = CodexAccountConfig(label: "Alt", codexHomePath: "~/.codex-alt")
        let providers = UsageStore.defaultProviders(extraAccounts: [config])
        XCTAssertEqual(providers.count, 10)
        XCTAssertEqual(providers[0].id, "codex")
        XCTAssertEqual(providers[1].id, "codex:\(config.id.uuidString)")
        XCTAssertEqual(providers[2].id, "cursor")
    }

    private func jsonObject(_ json: String) throws -> [String: Any] {
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

final class CodexAccountDiscoveryTests: XCTestCase {
    func testDiscoversUnconfiguredHomesWithLogins() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let configured: Set<String> = [home.appendingPathComponent(".codex-default", isDirectory: true).standardizedFileURL.path]
        let withAuth: Set<String> = [".codex-default", ".codex-me-com"]
        let found = CodexAccountDiscovery.candidates(
            from: [".codex", ".codex-old-gmail", ".codex-me-com", ".codex-default", ".codex-", "Documents"],
            homeDirectory: home,
            configuredPaths: configured,
            hasAuth: { withAuth.contains($0.lastPathComponent) }
        )
        XCTAssertEqual(found.map(\.homePath), ["~/.codex-me-com"])
        XCTAssertEqual(found.first?.suggestedLabel, "me-com")
    }
}
