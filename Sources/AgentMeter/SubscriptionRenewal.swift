import Foundation

struct SubscriptionRenewal: Codable, Equatable, Sendable {
    enum Platform: String, Codable, CaseIterable, Sendable {
        case chatgpt, apple, google, other

        var displayName: String {
            switch self {
            case .chatgpt: return L("ChatGPT")
            case .apple: return L("Apple")
            case .google: return L("Google Play")
            case .other: return L("Other")
            }
        }
    }

    var anchorDate: Date
    var platform: Platform
    var confirmedAt: Date?
    var remindDaysBefore: Int
}

extension SubscriptionRenewal {
    nonisolated func nextRenewal(after now: Date, calendar: Calendar = .current) -> Date {
        let anchorDay = calendar.startOfDay(for: anchorDate)
        let nowDay = calendar.startOfDay(for: now)

        if anchorDay >= nowDay {
            return anchorDate
        }

        var monthsToAdd = 1
        while let candidate = calendar.date(byAdding: .month, value: monthsToAdd, to: anchorDate) {
            if calendar.startOfDay(for: candidate) >= nowDay {
                return candidate
            }
            monthsToAdd += 1
        }
        return anchorDate
    }

    nonisolated func daysUntilRenewal(from now: Date, calendar: Calendar = .current) -> Int {
        let renewal = nextRenewal(after: now, calendar: calendar)
        let startNow = calendar.startOfDay(for: now)
        let startRenewal = calendar.startOfDay(for: renewal)
        return calendar.dateComponents([.day], from: startNow, to: startRenewal).day ?? 0
    }

    nonisolated var needsReconfirmation: Bool {
        guard let confirmedAt else { return true }
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        return confirmedAt < cutoff
    }

    nonisolated func reminderDate(for renewal: Date, calendar: Calendar = .current) -> Date? {
        guard remindDaysBefore > 0 else { return nil }
        guard let reminderDay = calendar.date(byAdding: .day, value: -remindDaysBefore, to: renewal) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: reminderDay)
        components.hour = 9
        components.minute = 0
        components.second = 0
        return calendar.date(from: components)
    }
}
