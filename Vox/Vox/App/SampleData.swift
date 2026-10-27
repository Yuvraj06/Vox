#if DEBUG
import Foundation

/// Debug only. Launch with `-seedSampleData` to fill an empty store with examples.
enum SampleData {
    static func seedIfRequested(_ store: any NodeStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData"),
              (try? store.children(of: nil).isEmpty) == true else { return }
        do {
            // A project board with three sections. Each section is a board with its own columns.
            let orbit = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board)

            func section(_ title: String, columns: [(String, TaskStatus?)]) throws -> [String: Node] {
                let section = try store.create(kind: .item, title: title, parentID: orbit.id, view: .board)
                var byTitle: [String: Node] = [:]
                for (name, type) in columns {
                    byTitle[name] = try store.create(kind: .item, title: name, parentID: section.id, columnType: type)
                }
                return byTitle
            }
            let standard: [(String, TaskStatus?)] = [("Todo", .todo), ("Doing", .doing), ("Done", .done)]

            let frontend = try section("Frontend", columns: [("Ideas", nil)] + standard)
            try store.create(kind: .item, title: "Dark mode", parentID: frontend["Ideas"]!.id, status: .todo)
            try store.create(kind: .item, title: "Settings page", parentID: frontend["Todo"]!.id, status: .todo)
            let login = try store.create(kind: .item, title: "Login screen", parentID: frontend["Doing"]!.id, status: .doing)
            try store.create(kind: .item, title: "Email field", parentID: login.id, status: .done)
            try store.create(kind: .item, title: "Password field", parentID: login.id, status: .todo)

            let backend = try section("Backend", columns: standard)
            try store.create(kind: .item, title: "Sync endpoint", parentID: backend["Todo"]!.id, status: .todo)
            try store.create(kind: .item, title: "Auth API", parentID: backend["Done"]!.id, status: .done)

            let hardware = try section("Hardware", columns: standard)
            try store.create(kind: .item, title: "Order PCB", parentID: hardware["Doing"]!.id, status: .doing)

            // Simple flat lists with details.
            let movies = try store.create(kind: .item, title: "Movies Watched", parentID: nil)
            for (title, rating) in [("Dune", "5"), ("Interstellar", "5"), ("Arrival", "4")] {
                try store.create(kind: .item, title: title, parentID: movies.id, details: [NodeDetail(key: "rating", value: rating)])
            }
            // Folders for organising, each with its own color.
            let personal = try store.create(kind: .item, title: "Personal", parentID: nil, view: .folder, color: "#E8919B")
            try store.create(kind: .item, title: "Work", parentID: nil, view: .folder, color: "#94ADD1")
            let games = try store.create(kind: .item, title: "Games", parentID: personal.id, view: .folder, color: "#8CD1B3")
            try store.create(kind: .note, title: "Gift ideas", parentID: personal.id, body: "Headphones for Sam")

            let minecraft = try store.create(kind: .item, title: "Minecraft coordinates", parentID: games.id)
            try store.create(kind: .item, title: "Village", parentID: minecraft.id, details: [
                NodeDetail(key: "x", value: "120"), NodeDetail(key: "y", value: "64"), NodeDetail(key: "z", value: "-300"),
            ])

            try store.create(kind: .note, title: "New ideas", parentID: nil, body: "Voice keychain\nSunrise hike app")
        } catch {
            print("Seeding failed: \(error)")
        }
    }

    /// Launch with `-seedReminders` to add a few reminders and alarms around today and tomorrow, if there are none yet.
    /// They are saved only, not put on the system clock, so nothing rings.
    static func seedRemindersIfRequested(_ store: any ReminderStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedReminders"),
              (try? store.all().isEmpty) == true else { return }
        let calendar = Calendar.current
        func at(_ dayOffset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: .now)) ?? .now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? .now
        }
        let samples = [
            Reminder(title: "Gym session", fireAt: .now.addingTimeInterval(29 * 60 + 42), kind: .alarm),
            Reminder(title: "Read 20 pages", fireAt: at(0, 22, 30)),
            Reminder(title: "DAA lab file", fireAt: at(1, 9), kind: .alarm),
            Reminder(title: "Team sync", fireAt: at(1, 14, 30)),
            Reminder(title: "Pay bill", fireAt: at(1, 18)),
            Reminder(title: "Movie night", fireAt: at(2, 20, 30)),
            Reminder(title: "Hackathon pitch", fireAt: at(3, 10), kind: .alarm),
            Reminder(title: "Water plants", fireAt: at(1, 8), repeatRule: .daily),
        ]
        for reminder in samples { try? store.save(reminder) }
    }
}
#endif
