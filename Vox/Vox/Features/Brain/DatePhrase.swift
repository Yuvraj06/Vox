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
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
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

        switch text {
        case "tonight": return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now)
        case "end of day", "eod", "end of the day": return calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)
        default: return nil
        }
    }

    private static let numberWords = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "fifteen": 15, "twenty": 20, "thirty": 30,
    ]

    /// "in 2 hours", "in ten minutes", "in a week", "in half an hour".
    private static func relativeDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        if text == "in half an hour" { return now.addingTimeInterval(30 * 60) }
        let words = text.split(separator: " ").map(String.init)
        guard words.count == 3, words[0] == "in",
              let amount = Int(words[1]) ?? numberWords[words[1]] else { return nil }
        let unit = words[2].hasSuffix("s") ? String(words[2].dropLast()) : words[2]
        let component: Calendar.Component? = switch unit {
        case "minute", "min": .minute
        case "hour", "hr": .hour
        case "day": .day
        case "week": .weekOfYear
        case "month": .month
        default: nil
        }
        return component.flatMap { calendar.date(byAdding: $0, value: amount, to: now) }
    }
}
