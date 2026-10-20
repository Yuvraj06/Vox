#if DEBUG
import Foundation

/// Debug only. Launch with `-seedSampleData` to fill an empty store with examples.
enum SampleData {
    static func seedIfRequested(_ store: any NodeStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData"),
              (try? store.children(of: nil).isEmpty) == true else { return }
        do {
            // A project board with sections and a task that has sub-tasks.
            var orbit = try store.create(kind: .page, title: "Orbit", parentID: nil, view: .board)
            orbit.columns = [
                BoardColumnDef(title: "Ideas", status: .todo),
                BoardColumnDef(title: "Building", status: .doing),
                BoardColumnDef(title: "Testing", status: .doing),
                BoardColumnDef(title: "Shipped", status: .done),
            ]
            try store.update(orbit)
            let frontend = try store.create(kind: .page, title: "Frontend", parentID: orbit.id, view: .checklist)
            let backend = try store.create(kind: .page, title: "Backend", parentID: orbit.id, view: .checklist)
            let hardware = try store.create(kind: .page, title: "Hardware", parentID: orbit.id, view: .checklist)
            let login = try store.create(kind: .entry, title: "Login screen", parentID: frontend.id, status: .doing)
            try store.create(kind: .entry, title: "Email field", parentID: login.id, status: .done)
            try store.create(kind: .entry, title: "Password field", parentID: login.id, status: .todo)
            try store.create(kind: .entry, title: "Settings page", parentID: frontend.id, status: .todo)
            try store.create(kind: .entry, title: "Auth API", parentID: backend.id, status: .done)
            try store.create(kind: .entry, title: "Sync endpoint", parentID: backend.id, status: .todo)
            try store.create(kind: .entry, title: "Order PCB", parentID: hardware.id, status: .doing)

            // Simple flat lists with details.
            let movies = try store.create(kind: .page, title: "Movies Watched", parentID: nil)
            for (title, rating) in [("Dune", "5"), ("Interstellar", "5"), ("Arrival", "4")] {
                try store.create(kind: .entry, title: title, parentID: movies.id, details: [NodeDetail(key: "rating", value: rating)])
            }
            let minecraft = try store.create(kind: .page, title: "Minecraft coordinates", parentID: nil)
            try store.create(kind: .entry, title: "Village", parentID: minecraft.id, details: [
                NodeDetail(key: "x", value: "120"), NodeDetail(key: "y", value: "64"), NodeDetail(key: "z", value: "-300"),
            ])

            try store.create(kind: .note, title: "New ideas", parentID: nil, body: "Voice keychain\nSunrise hike app")
        } catch {
            print("Seeding failed: \(error)")
        }
    }
}
#endif
