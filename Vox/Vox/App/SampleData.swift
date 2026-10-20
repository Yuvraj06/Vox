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
            let minecraft = try store.create(kind: .item, title: "Minecraft coordinates", parentID: nil)
            try store.create(kind: .item, title: "Village", parentID: minecraft.id, details: [
                NodeDetail(key: "x", value: "120"), NodeDetail(key: "y", value: "64"), NodeDetail(key: "z", value: "-300"),
            ])

            try store.create(kind: .note, title: "New ideas", parentID: nil, body: "Voice keychain\nSunrise hike app")
        } catch {
            print("Seeding failed: \(error)")
        }
    }
}
#endif
