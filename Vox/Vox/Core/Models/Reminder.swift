import Foundation

/// A reminder (a notification) or an alarm (rings, even on silent). Same shape as the `reminders` table in Supabase.
/// `nodeID` links it to an item or note. Nil means it stands alone, like "call mom".
struct Reminder: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var userID: UUID?
    var nodeID: UUID?
    var title: String
    /// The first (or only) time it goes off.
    var fireAt: Date
    var kind: ReminderKind
    /// Nil means once.
    var repeatRule: RepeatRule?
    /// Went off for good, or was cancelled because its item is done.
    var done: Bool
    var updatedAt: Date
    var deleted: Bool

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        nodeID: UUID? = nil,
        title: String,
        fireAt: Date,
        kind: ReminderKind = .reminder,
        repeatRule: RepeatRule? = nil,
        done: Bool = false,
        updatedAt: Date = .now,
        deleted: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.nodeID = nodeID
        self.title = title
        self.fireAt = fireAt
        self.kind = kind
        self.repeatRule = repeatRule
        self.done = done
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    /// Every time it goes off inside `interval`, in order.
    func occurrences(in interval: DateInterval, calendar: Calendar = .current) -> [Date] {
        guard let repeatRule else { return interval.contains(fireAt) ? [fireAt] : [] }
        let time = calendar.dateComponents([.hour, .minute], from: fireAt)
        var match = DateComponents(hour: time.hour, minute: time.minute)
        if case .weekly(let weekday) = repeatRule { match.weekday = weekday }
        // Start just before the window, but never before the first time.
        let start = max(interval.start, fireAt).addingTimeInterval(-1)
        var dates: [Date] = []
        calendar.enumerateDates(startingAfter: start, matching: match, matchingPolicy: .nextTime) { date, _, stop in
            guard let date, date < interval.end else { stop = true; return }
            dates.append(date)
        }
        return dates
    }

    /// The next time it goes off after `now`, if any.
    func nextFire(after now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard repeatRule != nil else { return fireAt > now ? fireAt : nil }
        let year = DateInterval(start: now, duration: 8 * 86_400)
        return occurrences(in: year, calendar: calendar).first
    }
}

enum ReminderKind: String, Codable, CaseIterable, Sendable {
    case reminder, alarm

    var label: String {
        switch self {
        case .reminder: "Reminder"
        case .alarm: "Alarm"
        }
    }

    var icon: String {
        switch self {
        case .reminder: "bell.fill"
        case .alarm: "alarm.fill"
        }
    }
}

/// How often it repeats. Stored as text: `daily` or `weekly:mon`.
enum RepeatRule: Hashable, Codable, Sendable {
    case daily
    /// Calendar weekday: 1 is Sunday, 2 is Monday, ... 7 is Saturday.
    case weekly(Int)

    private static let days = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    init?(text: String?) {
        guard let text = text?.lowercased() else { return nil }
        if text == "daily" { self = .daily; return }
        guard text.hasPrefix("weekly:"), let index = Self.days.firstIndex(of: String(text.dropFirst(7))) else { return nil }
        self = .weekly(index + 1)
    }

    var text: String {
        switch self {
        case .daily: "daily"
        case .weekly(let weekday): "weekly:\(Self.days[(weekday - 1) % 7])"
        }
    }

    var label: String {
        switch self {
        case .daily: "Every day"
        case .weekly(let weekday): "Every \(Calendar.current.weekdaySymbols[(weekday - 1) % 7])"
        }
    }

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let rule = RepeatRule(text: text) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown repeat rule \(text)"))
        }
        self = rule
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}
