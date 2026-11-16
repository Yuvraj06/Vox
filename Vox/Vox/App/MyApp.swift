import SwiftData
import SwiftUI

@main struct MyApp: App {
    @State private var notes: NotesModel
    @State private var capture: CaptureModel
    @State private var thinking: ThinkingQueue
    @State private var gemini: GeminiSettings
    @State private var reminders: RemindersModel
    @State private var history: HistoryModel
    @State private var auth: AuthModel
    @State private var sync: SyncEngine
    @Environment(\.scenePhase) private var scenePhase

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
        reminders.onNodesChanged = { notes.redraw() }
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
        // Downloads from other devices refresh the screens and put new reminders on the clock.
        let sync = SyncEngine(store: SwiftDataSyncStore(container: container)) {
            notes.refresh()
            Task { await reminders.rescheduleAll() }
        }
        _sync = State(initialValue: sync)
        // Signing in gives everything made while signed out to that account, then syncs it.
        _auth = State(initialValue: AuthModel(
            onSignIn: { userID in
                try? nodeStore.claimUnowned(by: userID)
                try? reminderStore.claimUnowned(by: userID)
                try? actionLog.claimUnowned(by: userID)
                sync.userID = userID
                Task { await sync.syncNow() }
            },
            onSignOut: { sync.userID = nil }
        ))
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
                .environment(auth)
                .environment(sync)
                // The confirmation email's link opens Vox here.
                .onOpenURL { url in Task { await auth.handle(url) } }
                // Coming back to the app picks up changes made elsewhere.
                .onChange(of: scenePhase) { _, phase in
                    // A ticked repeating reminder opens again once it next goes off.
                    if phase == .active { reminders.reconcile(); Task { await sync.syncNow() } }
                }
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
