import XCTest
@testable import AgentMeter
import AgentMeterStatusKit

final class SubscriptionRenewalTests: XCTestCase {
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return utcCalendar.date(from: components)!
    }

    func testNextRenewalJan31ToMarch() {
        let renewal = SubscriptionRenewal(
            anchorDate: utcDate(year: 2026, month: 1, day: 31),
            platform: .chatgpt,
            confirmedAt: nil,
            remindDaysBefore: 3
        )
        let now = utcDate(year: 2026, month: 3, day: 1)
        let next = renewal.nextRenewal(after: now, calendar: utcCalendar)
        XCTAssertEqual(
            utcCalendar.component(.month, from: next),
            3
        )
        XCTAssertEqual(
            utcCalendar.component(.day, from: next),
            31
        )
    }

    func testNextRenewalJan31ToFebruary() {
        let renewal = SubscriptionRenewal(
            anchorDate: utcDate(year: 2026, month: 1, day: 31),
            platform: .chatgpt,
            confirmedAt: nil,
            remindDaysBefore: 3
        )
        let now = utcDate(year: 2026, month: 2, day: 10)
        let next = renewal.nextRenewal(after: now, calendar: utcCalendar)
        XCTAssertEqual(utcCalendar.component(.month, from: next), 2)
        XCTAssertEqual(utcCalendar.component(.day, from: next), 28)
    }

    func testNextRenewalFutureAnchorUnchanged() {
        let anchor = utcDate(year: 2027, month: 5, day: 15)
        let renewal = SubscriptionRenewal(
            anchorDate: anchor,
            platform: .apple,
            confirmedAt: nil,
            remindDaysBefore: 0
        )
        let now = utcDate(year: 2026, month: 1, day: 1)
        XCTAssertEqual(renewal.nextRenewal(after: now, calendar: utcCalendar), anchor)
    }

    func testNextRenewalAnchorTodayReturnsToday() {
        let today = utcDate(year: 2026, month: 4, day: 10)
        let renewal = SubscriptionRenewal(
            anchorDate: today,
            platform: .google,
            confirmedAt: nil,
            remindDaysBefore: 1
        )
        XCTAssertEqual(renewal.nextRenewal(after: today, calendar: utcCalendar), today)
    }

    func testReminderDateAtNineAMLocal() {
        var local = Calendar.current
        local.timeZone = TimeZone(identifier: "America/New_York")!
        let renewal = SubscriptionRenewal(
            anchorDate: local.date(from: DateComponents(year: 2026, month: 5, day: 10))!,
            platform: .chatgpt,
            confirmedAt: nil,
            remindDaysBefore: 3
        )
        let renewalDate = local.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 12))!
        let reminder = renewal.reminderDate(for: renewalDate, calendar: local)
        XCTAssertNotNil(reminder)
        XCTAssertEqual(local.component(.day, from: reminder!), 7)
        XCTAssertEqual(local.component(.hour, from: reminder!), 9)
        XCTAssertEqual(local.component(.minute, from: reminder!), 0)
    }

    func testReminderDateNilWhenOff() {
        let renewal = SubscriptionRenewal(
            anchorDate: utcDate(year: 2026, month: 6, day: 1),
            platform: .other,
            confirmedAt: nil,
            remindDaysBefore: 0
        )
        let renewalDate = utcDate(year: 2026, month: 6, day: 1)
        XCTAssertNil(renewal.reminderDate(for: renewalDate, calendar: utcCalendar))
    }

    func testNeedsReconfirmationAt89Versus91Days() {
        let now = Date()
        var renewal = SubscriptionRenewal(
            anchorDate: now,
            platform: .chatgpt,
            confirmedAt: now.addingTimeInterval(-89 * 24 * 3600),
            remindDaysBefore: 3
        )
        XCTAssertFalse(renewal.needsReconfirmation)

        renewal.confirmedAt = now.addingTimeInterval(-91 * 24 * 3600)
        XCTAssertTrue(renewal.needsReconfirmation)

        renewal.confirmedAt = nil
        XCTAssertTrue(renewal.needsReconfirmation)
    }

    func testCodableRoundTrip() throws {
        let original = SubscriptionRenewal(
            anchorDate: utcDate(year: 2026, month: 7, day: 4),
            platform: .apple,
            confirmedAt: utcDate(year: 2026, month: 6, day: 1),
            remindDaysBefore: 7
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SubscriptionRenewal.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    @MainActor
    func testSettingsStorePersistsRenewals() {
        let suiteName = "SubscriptionRenewalTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsStore(defaults: defaults)
        let renewal = SubscriptionRenewal(
            anchorDate: utcDate(year: 2026, month: 8, day: 1),
            platform: .google,
            confirmedAt: nil,
            remindDaysBefore: 3
        )
        settings.setRenewal(renewal, for: "codex")
        XCTAssertEqual(settings.renewal(for: "codex"), renewal)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.renewal(for: "codex"), renewal)

        settings.removeRenewal(for: "codex")
        XCTAssertNil(settings.renewal(for: "codex"))
        let reloadedAfterRemove = SettingsStore(defaults: defaults)
        XCTAssertNil(reloadedAfterRemove.renewal(for: "codex"))

        defaults.removePersistentDomain(forName: suiteName)
    }

    @MainActor
    func testRemoveCodexAccountDropsRenewal() {
        let suiteName = "SubscriptionRenewalTests-remove-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let settings = SettingsStore(defaults: defaults)
        let account = CodexAccountConfig(label: "Work", codexHomePath: "~/.codex-work")
        settings.addCodexAccount(account)
        let providerID = "codex:\(account.id.uuidString)"
        settings.setRenewal(
            SubscriptionRenewal(
                anchorDate: utcDate(year: 2026, month: 9, day: 1),
                platform: .chatgpt,
                confirmedAt: nil,
                remindDaysBefore: 1
            ),
            for: providerID
        )
        settings.removeCodexAccount(id: account.id)
        XCTAssertNil(settings.renewal(for: providerID))
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testSnapshotWriterMapsRenewal() {
        let now = utcDate(year: 2026, month: 3, day: 1)
        let renewal = SubscriptionRenewal(
            anchorDate: utcDate(year: 2026, month: 1, day: 31),
            platform: .apple,
            confirmedAt: utcDate(year: 2026, month: 2, day: 1),
            remindDaysBefore: 3
        )
        let usage = ProviderUsage(
            planName: "Pro",
            windows: [UsageWindow(label: "5h", usedPercent: 10, resetsAt: nil)],
            asOf: now
        )
        let status = StatusSnapshotWriter.mapProvider(
            StatusSnapshotWriter.ProviderInput(
                id: "codex",
                displayName: "Codex",
                state: .ready(usage),
                renewal: renewal
            ),
            now: now
        )

        XCTAssertEqual(status.renewal?.platform, "apple")
        XCTAssertEqual(status.renewal?.confirmedAt, renewal.confirmedAt)
        XCTAssertEqual(
            status.renewal?.expectedAt,
            renewal.nextRenewal(after: now)
        )
    }
}
