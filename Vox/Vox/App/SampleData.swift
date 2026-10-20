#if DEBUG
import Foundation

/// Debug only. Launch with `-seedSampleData` to fill an empty store with an example project.
enum SampleData {
    static func seedIfRequested(_ store: any NodeStore) {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData"),
              (try? store.children(of: nil).isEmpty) == true else { return }
        do {
            let orbit = try store.create(kind: .folder, title: "Orbit", parentID: nil, view: .board)
            let frontend = try store.create(kind: .folder, title: "Frontend", parentID: orbit.id)
            let backend = try store.create(kind: .folder, title: "Backend", parentID: orbit.id)
            let hardware = try store.create(kind: .folder, title: "Hardware", parentID: orbit.id)
            try store.create(kind: .task, title: "Login screen", parentID: frontend.id, status: .doing)
            try store.create(kind: .task, title: "Settings page", parentID: frontend.id)
            try store.create(kind: .task, title: "Auth API", parentID: backend.id, status: .done)
            try store.create(kind: .task, title: "Sync endpoint", parentID: backend.id)
            try store.create(kind: .task, title: "Order PCB", parentID: hardware.id, status: .doing)

            let movies = try store.create(kind: .list, title: "Movies Watched", parentID: nil)
            for title in ["Dune", "Interstellar", "Arrival"] {
                try store.create(kind: .item, title: title, parentID: movies.id)
            }
            try store.create(kind: .note, title: "Trip ideas", parentID: nil, body: "Hike near the lake\nSunrise at the ridge")
        } catch {
            print("Seeding failed: \(error)")
        }
    }
}
#endif
