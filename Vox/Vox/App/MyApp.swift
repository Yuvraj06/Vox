import SwiftUI

@main struct MyApp: App {
    @State private var notes = NotesModel(store: Self.makeNodeStore())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(notes)
        }
    }

    private static func makeNodeStore() -> any NodeStore {
        do {
            return try SwiftDataNodeStore.persistent()
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
    }
}
