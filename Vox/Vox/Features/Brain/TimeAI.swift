import Foundation
import FoundationModels

/// Last try for a time Swift can't read: the model works out the exact date from the words and today's date.
/// Gemini when there is a key, else the on-device model. Swift checks the answer is ahead of now and within a year.
enum TimeAI {
    static let instructions = """
        You read a spoken command and work out the exact local date and time it asks for.
        If it gives a time but no day, use today if that time is still ahead of now, otherwise tomorrow.
        "In 10 minutes" or "after 10 minutes" means 10 minutes after now.
        A day with no time means 9 AM that day.
        hour uses a 24 hour clock.
        If the command names no date or time at all, set found to false.
        """

    static func date(for command: String, now: Date = .now, gemini: GeminiClient?, calendar: Calendar = .current) async -> Date? {
        let prompt = prompt(command: command, now: now)
        var parts: TimeParts?
        if let gemini { parts = try? await gemini.time(prompt: prompt) }
        if parts == nil { parts = await onDevice(prompt) }
        guard let parts, parts.found,
              let year = parts.year, let month = parts.month, let day = parts.day, let hour = parts.hour,
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: parts.minute ?? 0)),
              date > now, date < now.addingTimeInterval(366 * 86_400)
        else { return nil }
        return date
    }

    /// "Now: Tuesday, 27 October 2026 at 9:40 PM." then the command.
    static func prompt(command: String, now: Date) -> String {
        let today = now.formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        return "Now: \(today).\nCommand: \(command)"
    }

    private static func onDevice(_ prompt: String) async -> TimeParts? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        guard let answer = try? await session.respond(
            to: prompt,
            generating: GeneratedTime.self,
            options: GenerationOptions(samplingMode: .greedy)
        ).content else { return nil }
        return TimeParts(found: answer.found, year: answer.year, month: answer.month, day: answer.day, hour: answer.hour, minute: answer.minute)
    }
}

/// The parts of a time, as both models return them.
struct TimeParts: Decodable {
    var found: Bool
    var year: Int?
    var month: Int?
    var day: Int?
    var hour: Int?
    var minute: Int?

    /// For Gemini, so it can only answer in this shape.
    static var schema: [String: Any] {
        let number: [String: Any] = ["type": "INTEGER", "nullable": true]
        return [
            "type": "OBJECT",
            "properties": [
                "found": ["type": "BOOLEAN"],
                "year": number, "month": number, "day": number, "hour": number, "minute": number,
            ],
            "required": ["found"],
        ]
    }
}

/// What the on-device model fills in.
@Generable
private struct GeneratedTime {
    @Guide(description: "true only if the command names a date or a time")
    var found: Bool
    var year: Int
    @Guide(description: "1 to 12", .range(1...12))
    var month: Int
    @Guide(description: "day of the month", .range(1...31))
    var day: Int
    @Guide(description: "0 to 23", .range(0...23))
    var hour: Int
    @Guide(description: "0 to 59", .range(0...59))
    var minute: Int
}
