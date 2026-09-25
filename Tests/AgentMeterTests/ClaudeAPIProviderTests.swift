import Foundation
import XCTest
@testable import AgentMeter

final class ClaudeAPIProviderTests: XCTestCase {
    private let start = ISO8601DateFormatter().date(from: "2026-09-01T00:00:00Z")!
    private let now = ISO8601DateFormatter().date(from: "2026-09-25T12:34:56Z")!

    func testReportsConvertCentsAndAggregateBothPages() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("123.78912", more: true, next: "second", endingAt: "2026-09-24T00:00:00Z"))
        await client.set("/v1/organizations/cost_report", page: "second", body: costPage("76.21088"))
        await client.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 10, output: 20, read: 30, oneHour: 40, fiveMinutes: 50, more: true, next: "second", endingAt: "2026-09-24T00:00:00Z"))
        await client.set("/v1/organizations/usage_report/messages", page: "second", body: tokenPage(input: 1, output: 2, read: 3, oneHour: 4, fiveMinutes: 5))

        let provider = makeProvider(client: client)
        let usage = try await provider.fetch()
        XCTAssertEqual(usage.planName, "Organization")
        let summary = try XCTUnwrap(usage.apiUsage)
        XCTAssertEqual(summary.costUSD, 2, accuracy: 0.000001)
        XCTAssertEqual(summary.inputTokens, 11)
        XCTAssertEqual(summary.outputTokens, 22)
        XCTAssertEqual(summary.cacheReadTokens, 33)
        XCTAssertEqual(summary.cacheCreationTokens, 99)
        XCTAssertEqual(summary.periodStart, start)
        XCTAssertEqual(summary.periodEnd, ISO8601DateFormatter().date(from: "2026-09-25T00:00:00Z"))
        XCTAssertEqual(usage.asOf, now)
        XCTAssertEqual(usage.balance?.kind, .spent)
        XCTAssertEqual(usage.balance?.remaining, 2)

        let requests = await client.requests
        XCTAssertEqual(requests.count, 4)
        for request in requests {
            let url = try XCTUnwrap(request.url)
            let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "api.anthropic.com")
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "starting_at" })?.value, "2026-09-01T00:00:00Z")
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "ending_at" })?.value, "2026-09-26T00:00:00Z")
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "bucket_width" })?.value, "1d")
            XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "limit" })?.value, "31")
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "test-admin-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "AgentMeter/1.0")
            XCTAssertFalse(url.absoluteString.contains("test-admin-key"))
        }
        XCTAssertEqual(requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value }, ["second", "second"])
    }

    func testRejectsMalformedCostAndPagination() async throws {
        for amount in ["garbage", "12garbage", "-1", "NaN"] {
            let client = MockClaudeAPIClient()
            await client.set("/v1/organizations/cost_report", page: nil, body: costPage(amount))
            await client.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 0, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
            let provider = makeProvider(client: client)
            await XCTAssertMalformedReport(try await provider.fetch())
        }
        let nonUSD = MockClaudeAPIClient()
        await nonUSD.set("/v1/organizations/cost_report", page: nil, body: costPage("10", currency: "EUR"))
        await nonUSD.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 0, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
        await XCTAssertMalformedReport(try await makeProvider(client: nonUSD).fetch())

        let missing = MockClaudeAPIClient()
        await missing.set("/v1/organizations/cost_report", page: nil, body: costPage("10", more: true, next: nil))
        await XCTAssertMalformedReport(try await makeProvider(client: missing).fetch())

        let cycle = MockClaudeAPIClient()
        await cycle.set("/v1/organizations/cost_report", page: nil, body: costPage("10", more: true, next: "loop"))
        await cycle.set("/v1/organizations/cost_report", page: "loop", body: costPage("10", more: true, next: "loop"))
        await XCTAssertMalformedReport(try await makeProvider(client: cycle).fetch())
        let cycleCount = await cycle.requestCount
        XCTAssertEqual(cycleCount, 2)
    }

    func testFractionalCentsAreNotRoundedEarly() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("123.78912"))
        await client.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 0, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
        let usage = try await makeProvider(client: client).fetch()
        let summary = try XCTUnwrap(usage.apiUsage)
        XCTAssertEqual(summary.costUSD, 1.2378912, accuracy: 0.000000001)
    }

    func testCoverageUsesOlderCostOrTokenReportCutoff() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil,
                         body: costPage("200", endingAt: "2026-09-25T00:00:00Z"))
        await client.set("/v1/organizations/usage_report/messages", page: nil,
                         body: tokenPage(input: 10, output: 0, read: 0, oneHour: 0, fiveMinutes: 0,
                                         endingAt: "2026-09-24T00:00:00Z"))

        let usage = try await makeProvider(client: client).fetch()
        let summary = try XCTUnwrap(usage.apiUsage)
        XCTAssertEqual(summary.costUSD, 2)
        XCTAssertEqual(summary.inputTokens, 10)
        XCTAssertEqual(summary.periodEnd, ISO8601DateFormatter().date(from: "2026-09-24T00:00:00Z"))
        XCTAssertEqual(usage.asOf, now)
    }

    func testEmptyReportHasNoCoveredBuckets() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil,
                         body: "{\"data\":[],\"has_more\":false,\"next_page\":null}")
        await client.set("/v1/organizations/usage_report/messages", page: nil,
                         body: tokenPage(input: 10, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))

        let usage = try await makeProvider(client: client).fetch()
        let summary = try XCTUnwrap(usage.apiUsage)
        XCTAssertEqual(summary.costUSD, 0)
        XCTAssertEqual(summary.periodEnd, start)
        XCTAssertEqual(usage.asOf, now)
    }

    func testFutureBucketEndIsClampedToCheckTime() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil,
                         body: costPage("100", endingAt: "2026-09-26T00:00:00Z"))
        await client.set("/v1/organizations/usage_report/messages", page: nil,
                         body: tokenPage(input: 1, output: 0, read: 0, oneHour: 0, fiveMinutes: 0,
                                         endingAt: "2026-09-26T00:00:00Z"))

        let usage = try await makeProvider(client: client).fetch()
        XCTAssertEqual(usage.apiUsage?.periodEnd, now)
        XCTAssertEqual(usage.asOf, now)
    }

    func testRejectsMalformedBucketEnd() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil,
                         body: costPage("100", endingAt: "not-a-date"))
        await client.set("/v1/organizations/usage_report/messages", page: nil,
                         body: tokenPage(input: 1, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
        await XCTAssertMalformedReport(try await makeProvider(client: client).fetch())
    }

    func testRejectsNegativeAndOverflowTokens() async throws {
        let negative = MockClaudeAPIClient()
        await negative.set("/v1/organizations/cost_report", page: nil, body: costPage("0"))
        await negative.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: -1, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
        await XCTAssertThrowsAsync(try await makeProvider(client: negative).fetch())

        let overflow = MockClaudeAPIClient()
        await overflow.set("/v1/organizations/cost_report", page: nil, body: costPage("0"))
        await overflow.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: Int.max, output: 0, read: 0, oneHour: Int.max, fiveMinutes: 1))
        await XCTAssertThrowsAsync(try await makeProvider(client: overflow).fetch())
    }

    func testSanitizesTransportAndHTTPFailures() async throws {
        let secret = "test-admin-key"
        let transport: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { _ in
            throw NSError(domain: "request \(secret)", code: 1)
        }
        let provider = ClaudeAPIProvider(
            keyReader: { secret }, clock: { self.now }, transport: transport,
            cache: ClaudeAPIReportCache()
        )
        do {
            _ = try await provider.fetch()
            XCTFail("Expected transport failure")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains(secret))
        }

        for (code, expected) in [(401, "401"), (403, "403"), (429, "429"), (500, "500")] {
            let client = MockClaudeAPIClient()
            await client.set("/v1/organizations/cost_report", page: nil, body: "{\"error\":\"\(secret)\"}", status: code)
            do {
                _ = try await makeProvider(client: client).fetch()
                XCTFail("Expected HTTP \(code)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains(expected))
                XCTAssertFalse(error.localizedDescription.contains(secret))
            }
        }
    }

    func testCacheSingleFlightKeyChangeMonthRolloverAndFailureCooldown() async throws {
        let state = LockedState(key: "first", now: now)
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("100"))
        await client.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 1, output: 1, read: 1, oneHour: 1, fiveMinutes: 1))
        await client.setDelay(50_000_000)
        let provider = ClaudeAPIProvider(
            keyReader: { state.key }, clock: { state.now },
            transport: { request in try await client.send(request) },
            cache: ClaudeAPIReportCache()
        )
        async let first = provider.fetch()
        async let second = provider.fetch()
        _ = try await (first, second)
        var count = await client.requestCount
        XCTAssertEqual(count, 2)
        _ = try await provider.fetch()
        count = await client.requestCount
        XCTAssertEqual(count, 2)

        state.now = state.now.addingTimeInterval(301)
        _ = try await provider.fetch()
        count = await client.requestCount
        XCTAssertEqual(count, 4)

        state.key = "second"
        _ = try await provider.fetch()
        count = await client.requestCount
        XCTAssertEqual(count, 6)
        state.now = ISO8601DateFormatter().date(from: "2026-10-01T00:00:01Z")!
        _ = try await provider.fetch()
        count = await client.requestCount
        XCTAssertEqual(count, 8)

        let failureClient = MockClaudeAPIClient()
        await failureClient.set("/v1/organizations/cost_report", page: nil, body: "{}", status: 429)
        let failureProvider = ClaudeAPIProvider(
            keyReader: { state.key }, clock: { state.now },
            transport: { request in try await failureClient.send(request) },
            cache: ClaudeAPIReportCache()
        )
        await XCTAssertThrowsAsync(try await failureProvider.fetch())
        await XCTAssertThrowsAsync(try await failureProvider.fetch())
        var failureCount = await failureClient.requestCount
        XCTAssertEqual(failureCount, 1)
        state.now = state.now.addingTimeInterval(61)
        await XCTAssertThrowsAsync(try await failureProvider.fetch())
        failureCount = await failureClient.requestCount
        XCTAssertEqual(failureCount, 2)
    }

    func testManualRefreshBypassesFiveMinuteSuccessCache() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("100"))
        await client.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 1, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
        let provider = makeProvider(client: client)

        let initial = try await provider.fetch()
        XCTAssertEqual(initial.apiUsage?.costUSD, 1)
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("200"))
        let automatic = try await provider.fetch()
        XCTAssertEqual(automatic.apiUsage?.costUSD, 1)
        let cachedRequestCount = await client.requestCount
        XCTAssertEqual(cachedRequestCount, 2)

        let forced = try await provider.fetch(forceRefresh: true)
        XCTAssertEqual(forced.apiUsage?.costUSD, 2)
        let forcedRequestCount = await client.requestCount
        XCTAssertEqual(forcedRequestCount, 4)
        let refreshedAutomatic = try await provider.fetch()
        XCTAssertEqual(refreshedAutomatic.apiUsage?.costUSD, 2)
        let finalRequestCount = await client.requestCount
        XCTAssertEqual(finalRequestCount, 4)
    }

    func testAutomaticRefreshJoinsForcedRequestEvenWithCachedSuccess() async throws {
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("100"))
        await client.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 0, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
        let provider = makeProvider(client: client)
        let initial = try await provider.fetch()
        XCTAssertEqual(initial.apiUsage?.costUSD, 1)

        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("200"))
        await client.blockRequests()
        let forced = Task { try await provider.fetch(forceRefresh: true) }
        await client.waitForRequestCount(3)
        let automatic = Task { try await provider.fetch() }
        // Give the automatic fetch time to enter the cache while the forced
        // request is blocked, so returning the old value fails this test.
        try await Task.sleep(nanoseconds: 20_000_000)
        await client.unblockRequests()

        let forcedUsage = try await forced.value
        let automaticUsage = try await automatic.value
        XCTAssertEqual(forcedUsage.apiUsage?.costUSD, 2)
        XCTAssertEqual(automaticUsage.apiUsage?.costUSD, 2)
        let requestCount = await client.requestCount
        XCTAssertEqual(requestCount, 4)
    }

    func testFailedManualRefreshInvalidatesSuccessAndAppliesCooldownToAutomaticRefresh() async throws {
        let state = LockedState(key: "test-admin-key", now: now)
        let client = MockClaudeAPIClient()
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("100"))
        await client.set("/v1/organizations/usage_report/messages", page: nil, body: tokenPage(input: 0, output: 0, read: 0, oneHour: 0, fiveMinutes: 0))
        let provider = ClaudeAPIProvider(
            keyReader: { state.key }, clock: { state.now },
            transport: { request in try await client.send(request) },
            cache: ClaudeAPIReportCache()
        )
        let initial = try await provider.fetch()
        XCTAssertEqual(initial.apiUsage?.costUSD, 1)

        await client.set("/v1/organizations/cost_report", page: nil, body: "{}", status: 429)
        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("Expected forced refresh to fail")
        } catch ClaudeAPIError.rateLimited {
            // The failure must become the visible state for this key and month.
        }
        do {
            _ = try await provider.fetch(forceRefresh: true)
            XCTFail("Expected manual refresh to respect the failure cooldown")
        } catch ClaudeAPIError.rateLimited {
            // Manual refresh must not hammer the reporting endpoint after 429.
        }
        do {
            _ = try await provider.fetch()
            XCTFail("Expected automatic refresh to keep the failure visible")
        } catch ClaudeAPIError.rateLimited {
            // During the cooldown, automatic refresh must not return old spend.
        }
        let cooldownRequestCount = await client.requestCount
        XCTAssertEqual(cooldownRequestCount, 3)

        state.now = state.now.addingTimeInterval(61)
        await client.set("/v1/organizations/cost_report", page: nil, body: costPage("200"))
        let recovered = try await provider.fetch()
        XCTAssertEqual(recovered.apiUsage?.costUSD, 2)
        let recoveredRequestCount = await client.requestCount
        XCTAssertEqual(recoveredRequestCount, 5)
    }

    private func makeProvider(client: MockClaudeAPIClient) -> ClaudeAPIProvider {
        ClaudeAPIProvider(
            keyReader: { "test-admin-key" }, clock: { self.now },
            transport: { request in try await client.send(request) },
            cache: ClaudeAPIReportCache()
        )
    }

    private func costPage(_ amount: String, currency: String = "USD", more: Bool = false,
                          next: String? = nil, endingAt: String = "2026-09-25T00:00:00Z") -> String {
        let token = next.map { "\"\($0)\"" } ?? "null"
        return "{\"data\":[{\"ending_at\":\"\(endingAt)\",\"results\":[{\"amount\":\"\(amount)\",\"currency\":\"\(currency)\"}]}],\"has_more\":\(more),\"next_page\":\(token)}"
    }

    private func tokenPage(input: Int, output: Int, read: Int, oneHour: Int, fiveMinutes: Int,
                           more: Bool = false, next: String? = nil,
                           endingAt: String = "2026-09-25T00:00:00Z") -> String {
        let token = next.map { "\"\($0)\"" } ?? "null"
        return "{\"data\":[{\"ending_at\":\"\(endingAt)\",\"results\":[{\"uncached_input_tokens\":\(input),\"output_tokens\":\(output),\"cache_read_input_tokens\":\(read),\"cache_creation\":{\"ephemeral_1h_input_tokens\":\(oneHour),\"ephemeral_5m_input_tokens\":\(fiveMinutes)}}]}],\"has_more\":\(more),\"next_page\":\(token)}"
    }
}

private actor MockClaudeAPIClient {
    private struct Reply { let data: Data; let status: Int }
    private var replies: [String: Reply] = [:]
    private(set) var requests: [URLRequest] = []
    private var delay: UInt64 = 0
    private var blocked = false
    private var blockedRequests: [CheckedContinuation<Void, Never>] = []
    private var requestWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    var requestCount: Int { requests.count }

    func set(_ path: String, page: String?, body: String, status: Int = 200) {
        replies["\(path)|\(page ?? "")"] = Reply(data: Data(body.utf8), status: status)
    }

    func setDelay(_ nanos: UInt64) { delay = nanos }

    func blockRequests() { blocked = true }

    func unblockRequests() {
        blocked = false
        let pending = blockedRequests
        blockedRequests.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitForRequestCount(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { continuation in
            requestWaiters.append((count, continuation))
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let ready = requestWaiters.filter { requests.count >= $0.count }
        requestWaiters.removeAll { requests.count >= $0.count }
        ready.forEach { $0.continuation.resume() }
        if blocked {
            await withCheckedContinuation { continuation in
                blockedRequests.append(continuation)
            }
        }
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        let url = request.url!
        let page = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "page" })?.value
        guard let reply = replies["\(url.path)|\(page ?? "")"] else { throw NSError(domain: "missing fixture", code: 0) }
        return (reply.data, HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class LockedState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String
    private var storedNow: Date

    init(key: String, now: Date) { storedKey = key; storedNow = now }
    var key: String {
        get { lock.lock(); defer { lock.unlock() }; return storedKey }
        set { lock.lock(); defer { lock.unlock() }; storedKey = newValue }
    }
    var now: Date {
        get { lock.lock(); defer { lock.unlock() }; return storedNow }
        set { lock.lock(); defer { lock.unlock() }; storedNow = newValue }
    }
}

private func XCTAssertThrowsAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { /* expected */ }
}

private func XCTAssertMalformedReport<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected malformed report", file: file, line: line)
    } catch ClaudeAPIError.malformedReport {
        // Expected precise failure; a missing fixture or network error is not sufficient.
    } catch {
        XCTFail("Expected malformed report, got \(type(of: error))", file: file, line: line)
    }
}
