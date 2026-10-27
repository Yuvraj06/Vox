import Foundation

/// Turns spoken time words ("tomorrow 5pm", "in 2 hours") into a date.
/// The model only copies the words. All date math happens here.
enum DatePhrase {
    /// "every day at 7" is daily, "every monday 9am" or "on mondays" is weekly. Nil means once.
    static func repeatRule(in phrase: String, calendar: Calendar = .current) -> RepeatRule? {
        let text = phrase.lowercased()
        if ["every day", "everyday", "daily", "each day", "every morning", "every evening", "every night"].contains(where: text.contains) {
            return .daily
        }
        for (index, name) in calendar.weekdaySymbols.map({ $0.lowercased() }).enumerated()
        where text.contains("every \(name)") || text.contains("\(name)s") {
            return .weekly(index + 1)
        }
        return nil
    }

    /// The first time a reminder goes off. Repeats without a day ("every day at 7") start at the next 7.
    static func firstFire(from phrase: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        var text = phrase.lowercased()
        for filler in ["every day", "everyday", "daily", "each day", "every "] { text = text.replacingOccurrences(of: filler, with: " ") }
        guard let date = date(from: text, now: now, calendar: calendar) else { return nil }
        if case .weekly(let weekday)? = repeatRule(in: phrase, calendar: calendar), calendar.component(.weekday, from: date) != weekday {
            let time = calendar.dateComponents([.hour, .minute], from: date)
            return calendar.nextDate(after: now, matching: DateComponents(hour: time.hour, minute: time.minute, weekday: weekday), matchingPolicy: .nextTime)
        }
        return date <= now ? calendar.date(byAdding: .day, value: 1, to: date) : date
    }

    static func date(from phrase: String, now: Date = .now, calendar: Calendar = .current) -> Date? {
        let text = normalized(phrase)
        guard !text.isEmpty else { return nil }
        if let exact = exactDate(text, calendar: calendar) { return exact }
        if let relative = relativeDate(text, now: now, calendar: calendar) { return relative }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        if let found = detector?.firstMatch(in: text, range: range)?.date {
            // "5pm" said after 5pm means tomorrow.
            if found < now, calendar.isDate(found, inSameDayAs: now) {
                return calendar.date(byAdding: .day, value: 1, to: found)
            }
            return found
        }
        return partOfDay(text, now: now, calendar: calendar)
    }

    /// Finds the time words inside a whole command, like "after one minute" in
    /// "set an alarm for today after one minute". Nil when it says no time.
    /// Repeat words come along, so "every day at 7" stays daily.
    static func spokenTime(in command: String, now: Date = .now, calendar: Calendar = .current) -> String? {
        let text = normalized(command)
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let matches = [relativePattern.firstMatch(in: text, range: range), halfHourPattern.firstMatch(in: text, range: range), detector?.firstMatch(in: text, range: range)]
        // The first match that really is a time. "in my day" looks like "in 2 days" but is not.
        let phrase = matches
            .compactMap { $0.flatMap { Range($0.range, in: text) }.map { String(text[$0]) } }
            .first { date(from: $0, now: now, calendar: calendar) != nil }
            ?? (partOfDay(text, now: now, calendar: calendar) != nil ? text : nil)
        return phrase.map { withRepeat($0, from: command, calendar: calendar) }
    }

    /// Puts the command's repeat words in front of a time, so "every day at 7" stays daily.
    static func withRepeat(_ phrase: String, from command: String, calendar: Calendar = .current) -> String {
        switch repeatRule(in: command, calendar: calendar) {
        case .daily?: "every day \(phrase)"
        case .weekly(let weekday)?: "every \(calendar.weekdaySymbols[weekday - 1].lowercased()) \(phrase)"
        case nil: phrase
        }
    }

    /// An exact time as text Swift reads back the same: "2026-10-28t07:00". For times the model worked out.
    static func exact(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "%04d-%02d-%02dt%02d:%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: Helpers

    /// Lower case, "p.m." as "pm", and spelled numbers before am, pm or o'clock as digits ("seven pm" is "7 pm").
    private static func normalized(_ phrase: String) -> String {
        var text = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        text = text.replacingOccurrences(of: "a.m.", with: "am").replacingOccurrences(of: "p.m.", with: "pm")
        for (word, value) in numberWords where value <= 12 && word.count > 2 {
            for suffix in [" am", " pm", " o'clock", " oclock"] {
                text = text.replacingOccurrences(of: "\(word)\(suffix)", with: "\(value)\(suffix)")
            }
        }
        return text
    }

    private static let exactPattern = try! NSRegularExpression(pattern: #"\b(\d{4})-(\d{2})-(\d{2})t(\d{2}):(\d{2})\b"#)

    /// "2026-10-28t07:00" anywhere in the text, from `exact(_:)`.
    private static func exactDate(_ text: String, calendar: Calendar) -> Date? {
        guard let match = exactPattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let parts = (1...5).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
        guard parts.count == 5 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4]))
    }

    private static let numberWords = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40,
        "forty-five": 45, "fifty": 50, "sixty": 60, "few": 3, "couple": 2,
    ]

    /// "in 2 hours", "after one minute", "in 1.5 hours", "in an hour and a half", "in 2 hours and 30 minutes".
    private static let relativePattern = try! NSRegularExpression(
        pattern: #"\b(?:in|after|within)\s+(?:about\s+|around\s+|a\s+)?([0-9]+(?:\.[0-9]+)?|[a-z-]+)\s*(?:of\s+)?(minute|min|hour|hr|day|week|month)s?\b(\s+and\s+a\s+half)?(?:\s+and\s+([0-9]+|[a-z-]+)\s*(?:minute|min)s?\b)?"#
    )
    /// "in half an hour".
    private static let halfHourPattern = try! NSRegularExpression(pattern: #"\b(?:in|after|within)\s+half\s+an?\s+hour\b"#)

    private static func relativeDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let range = NSRange(text.startIndex..., in: text)
        if halfHourPattern.firstMatch(in: text, range: range) != nil { return now.addingTimeInterval(30 * 60) }
        guard let match = relativePattern.firstMatch(in: text, range: range) else { return nil }
        func group(_ index: Int) -> String? { Range(match.range(at: index), in: text).map { String(text[$0]) } }
        func amount(_ word: String?) -> Double? { word.flatMap { Double($0) ?? numberWords[$0].map(Double.init) } }
        guard var value = amount(group(1)), let unit = group(2) else { return nil }
        if group(3) != nil { value += 0.5 }
        let extraMinutes = amount(group(4)) ?? 0
        switch unit {
        case "minute", "min": return now.addingTimeInterval((value + extraMinutes) * 60)
        case "hour", "hr": return now.addingTimeInterval(value * 3600 + extraMinutes * 60)
        case "day": return calendar.date(byAdding: .day, value: Int(value), to: now)
        case "week": return calendar.date(byAdding: .weekOfYear, value: Int(value), to: now)
        case "month": return calendar.date(byAdding: .month, value: Int(value), to: now)
        default: return nil
        }
    }

    /// "noon", "tonight", "tomorrow morning". The next one still ahead.
    private static func partOfDay(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let parts: [(word: String, hour: Int)] = [
            ("midnight", 0), ("noon", 12), ("midday", 12), ("tonight", 20), ("evening", 19),
            ("afternoon", 15), ("morning", 9), ("end of the day", 17), ("end of day", 17), ("eod", 17),
        ]
        guard let hour = parts.first(where: { text.contains($0.word) })?.hour else { return nil }
        let day = text.contains("tomorrow") ? calendar.date(byAdding: .day, value: 1, to: now) ?? now : now
        guard let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) else { return nil }
        return date <= now ? calendar.date(byAdding: .day, value: 1, to: date) : date
    }
}
