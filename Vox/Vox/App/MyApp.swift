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
            let store = try SwiftDataNodeStore.persistent()
            #if DEBUG
            SampleData.seedIfRequested(store)
            #endif
            return store
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
    }
}
