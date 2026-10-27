import SwiftData
import SwiftUI

@main struct MyApp: App {
    @State private var notes: NotesModel
    @State private var capture: CaptureModel
    @State private var thinking: ThinkingQueue
    @State private var gemini: GeminiSettings
    @State private var reminders: RemindersModel
    @State private var history: HistoryModel

    init() {
        let container = Self.makeContainer()
        let nodeStore = SwiftDataNodeStore(container: container)
        #if DEBUG
        SampleData.seedIfRequested(nodeStore)
        #endif
        let notes = NotesModel(store: nodeStore)
        let reminderStore = SwiftDataReminderStore(container: container)
        #if DEBUG
        SampleData.seedRemindersIfRequested(reminderStore)
        #endif
        let reminders = RemindersModel(
            store: reminderStore,
            nodes: nodeStore,
            scheduler: SystemReminderScheduler()
        )
        // An item marked done (by hand or by voice) cancels its reminders.
        notes.onChange = { reminders.reconcile() }
        let gemini = GeminiSettings()
        let actionLog = SwiftDataActionLogStore(container: container)
        let brain = Brain(
            nodes: nodeStore,
            log: actionLog,
            gemini: gemini,
            reminders: reminderStore,
            onChange: { notes.refresh() },
            onReminders: { added, removed in reminders.changedOutside(added: added, removed: removed) }
        )
        brain.prewarm()
        _notes = State(initialValue: notes)
        _capture = State(initialValue: CaptureModel(runner: brain))
        _thinking = State(initialValue: brain.thinking)
        _gemini = State(initialValue: gemini)
        _reminders = State(initialValue: reminders)
        _history = State(initialValue: HistoryModel(
            log: actionLog,
            ancestors: { id in nodeStore.ancestorIDs(of: id) },
            undo: { try brain.undo($0) }
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(notes)
                .environment(capture)
                .environment(thinking)
                .environment(gemini)
                .environment(reminders)
                .environment(history)
                .task { await reminders.rescheduleAll() }
        }
    }

    private static func makeContainer() -> ModelContainer {
        do {
            return try LocalDatabase.persistent()
        } catch {
            fatalError("Could not open the local database: \(error)")
        }
    }
}
