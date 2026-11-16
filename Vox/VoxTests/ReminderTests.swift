import Foundation
import Testing
@testable import Vox

@MainActor
struct ReminderTests {
    let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func makeModel() throws -> (RemindersModel, SwiftDataNodeStore, FakeReminderScheduler) {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let scheduler = FakeReminderScheduler()
        let model = RemindersModel(store: SwiftDataReminderStore(container: container), nodes: nodes, scheduler: scheduler)
        return (model, nodes, scheduler)
    }

    // MARK: Repeats

    @Test func repeatRuleRoundTripsAsText() {
        #expect(RepeatRule(text: "daily") == .daily)
        #expect(RepeatRule(text: "weekly:mon") == .weekly(2))
        #expect(RepeatRule.weekly(7).text == "weekly:sat")
        #expect(RepeatRule(text: "sometimes") == nil)
    }

    @Test func onceOnlyShowsOnItsDay() {
        let reminder = Reminder(title: "Call mom", fireAt: date(3, 18))
        #expect(reminder.occurrences(in: DateInterval(start: date(3, 0), end: date(4, 0)), calendar: calendar) == [date(3, 18)])
        #expect(reminder.occurrences(in: DateInterval(start: date(4, 0), end: date(5, 0)), calendar: calendar).isEmpty)
    }

    @Test func dailyShowsEveryDayFromTheFirst() {
        let reminder = Reminder(title: "Water plants", fireAt: date(3, 8), repeatRule: .daily)
        let week = DateInterval(start: date(1, 0), end: date(8, 0))
        #expect(reminder.occurrences(in: week, calendar: calendar) == (3...7).map { date($0, 8) })
    }

    @Test func weeklyShowsOncePerWeek() {
        // November 2, 2026 is a Monday.
        let reminder = Reminder(title: "Standup", fireAt: date(2, 9, 30), repeatRule: .weekly(2))
        let month = DateInterval(start: date(1, 0), end: date(30, 0))
        #expect(reminder.occurrences(in: month, calendar: calendar) == [2, 9, 16, 23].map { date($0, 9, 30) })
    }

    // MARK: Store

    @Test func storeSavesUpdatesAndSoftDeletes() throws {
        let store = try SwiftDataReminderStore.inMemory()
        var reminder = Reminder(title: "Gym", fireAt: date(5, 7), kind: .alarm, repeatRule: .weekly(5))
        try store.save(reminder)
        #expect(try store.reminder(id: reminder.id)?.repeatRule == .weekly(5))

        reminder.title = "Gym day"
        try store.save(reminder)
        #expect(try store.all().map(\.title) == ["Gym day"])

        try store.delete(id: reminder.id)
        #expect(try store.all().isEmpty)
    }

    // MARK: Model

    @Test func doneItemCancelsItsReminders() async throws {
        let (model, nodes, scheduler) = try makeModel()
        var task = try nodes.create(kind: .item, title: "Essay", parentID: nil, status: .doing)
        let reminder = Reminder(nodeID: task.id, title: "Essay", fireAt: .now.addingTimeInterval(3600))
        try await scheduler.schedule(reminder)
        model.save(reminder)
        #expect(model.reminders(for: task.id).count == 1)

        task.status = .done
        try nodes.update(task)
        model.reconcile()
        #expect(model.reminders(for: task.id).isEmpty)
        // The cancel runs in the background.
        for _ in 0..<50 where scheduler.scheduled.contains(reminder.id) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!scheduler.scheduled.contains(reminder.id))
    }

    @Test func dayListHasRemindersAndDeadlines() throws {
        let (model, nodes, _) = try makeModel()
        let tomorrow = Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400)
        var report = try nodes.create(kind: .item, title: "Report", parentID: nil, status: .todo)
        report.dueAt = tomorrow.addingTimeInterval(17 * 3600)
        try nodes.update(report)
        model.save(Reminder(title: "Call mom", fireAt: tomorrow.addingTimeInterval(9 * 3600)))

        let entries = model.entries(on: tomorrow)
        #expect(entries.count == 2)
        if case .reminder(let first) = entries.first?.source { #expect(first.title == "Call mom") } else { Issue.record("expected the reminder first") }
        if case .deadline(let node) = entries.last?.source { #expect(node.title == "Report") } else { Issue.record("expected the deadline last") }
        #expect(model.busyDays(in: DateInterval(start: tomorrow, duration: 86_400)) == [tomorrow])
    }

    // MARK: Every reminder is a todo

    @Test func standaloneReminderGetsATodoInReminders() async throws {
        let (model, nodes, scheduler) = try makeModel()
        let reminder = Reminder(title: "Call mom", fireAt: .now.addingTimeInterval(3600))
        model.save(reminder)
        let saved = try #require(model.reminders(for: reminder.id).first)
        let todo = try #require(try nodes.node(id: reminder.id))
        #expect(saved.nodeID == todo.id && todo.title == "Call mom" && todo.status == .todo)
        #expect(nodes.isInRemindersList(todo))
        #expect(model.linkedItem(of: saved) == nil)

        // Ticking the todo cancels a one-time reminder.
        var ticked = todo
        ticked.status = .done
        try nodes.update(ticked)
        model.reconcile()
        #expect(model.reminders(for: todo.id).isEmpty)
        for _ in 0..<50 where scheduler.scheduled.contains(reminder.id) { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!scheduler.scheduled.contains(reminder.id))
    }

    @Test func renamingAndDeletingFollowTheTodo() throws {
        let (model, nodes, _) = try makeModel()
        var reminder = Reminder(title: "Pay bill", fireAt: .now.addingTimeInterval(3600))
        model.save(reminder)
        reminder = try #require(model.reminders(for: reminder.id).first)
        reminder.title = "Pay rent"
        model.save(reminder)
        #expect(try nodes.node(id: reminder.id)?.title == "Pay rent")
        model.delete(reminder)
        #expect(try nodes.node(id: reminder.id) == nil)
    }

    @Test func oldStandaloneRemindersGetATodoOnReconcile() throws {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let store = SwiftDataReminderStore(container: container)
        let reminder = Reminder(title: "Gym", fireAt: .now.addingTimeInterval(3600))
        try store.save(reminder)
        let model = RemindersModel(store: store, nodes: nodes, scheduler: FakeReminderScheduler())
        var redrawn = false
        model.onNodesChanged = { redrawn = true }
        model.reconcile()
        #expect(try store.reminder(id: reminder.id)?.nodeID == reminder.id)
        #expect(try nodes.node(id: reminder.id)?.status == .todo)
        #expect(redrawn)
    }

    @Test func tickedRepeatOpensAgainWhenItNextGoesOff() throws {
        let (model, nodes, _) = try makeModel()
        let start = Date.now.addingTimeInterval(-3600)
        let reminder = Reminder(title: "Water plants", fireAt: start, repeatRule: .daily)
        model.save(reminder)
        var todo = try #require(try nodes.node(id: reminder.id))
        todo.status = .done
        try nodes.update(todo)

        // Ticked today: stays ticked, and the reminder keeps repeating.
        model.reconcile()
        #expect(try nodes.node(id: todo.id)?.status == .done)
        #expect(model.reminders(for: todo.id).count == 1)

        // Tomorrow, after it goes off again, it is a todo again.
        model.reconcile(now: start.addingTimeInterval(86_400 + 60))
        #expect(try nodes.node(id: todo.id)?.status == .todo)
    }

    @Test func untimedHidesTodosWithAReminderAhead() throws {
        let (model, nodes, _) = try makeModel()
        model.save(Reminder(title: "Later", fireAt: .now.addingTimeInterval(3600)))
        let list = try nodes.remindersList()
        try nodes.create(kind: .item, title: "Buy milk", parentID: list.id, status: .todo)
        #expect(model.untimed(try nodes.children(of: list.id)).map(\.title) == ["Buy milk"])
    }

    @Test func dayKeepsWhatAlreadyWentOff() throws {
        let (model, _, _) = try makeModel()
        let today = Calendar.current.startOfDay(for: .now)
        let day = DateInterval(start: today, duration: 86_400)
        let noon = today.addingTimeInterval(12 * 3600)
        model.save(Reminder(title: "Lunch", fireAt: noon))
        var cancelled = Reminder(title: "Gone", fireAt: noon.addingTimeInterval(3600))
        cancelled.done = true
        model.save(cancelled)

        // After 1 PM, lunch went off and is marked done, but the day still shows it.
        model.reconcile(now: noon.addingTimeInterval(1800))
        let titles = model.entries(in: day, now: noon.addingTimeInterval(1800)).map(\.title)
        #expect(titles == ["Lunch"])
    }
}

/// "Remind me ..." and "set an alarm ..." from the Brain.
@MainActor
struct VoiceReminderTests {
    let calendar = Calendar.current
    /// Monday, November 2, 2026, 10:00.
    let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!

    @Test func repeatWords() {
        #expect(DatePhrase.repeatRule(in: "every day at 7am") == .daily)
        #expect(DatePhrase.repeatRule(in: "every Friday 9am") == .weekly(6))
        #expect(DatePhrase.repeatRule(in: "tomorrow 5pm") == nil)
    }

    @Test func firstFireTimes() throws {
        // The date reader works from the real clock, so these use it too.
        let daily = try #require(DatePhrase.firstFire(from: "every day at 7am"))
        #expect(daily > .now && daily < .now.addingTimeInterval(86_400))
        #expect(calendar.component(.hour, from: daily) == 7)

        let friday = try #require(DatePhrase.firstFire(from: "every friday at 9am"))
        #expect(friday > .now)
        #expect(calendar.component(.weekday, from: friday) == 6 && calendar.component(.hour, from: friday) == 9)
    }

    @Test func linkedAlarmIsSavedAndUndoable() throws {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let store = SwiftDataReminderStore(container: container)
        let backend = try nodes.create(kind: .item, title: "Backend", parentID: nil)
        let context = BrainContext(store: nodes)
        context.reminders = store

        let result = try ActionExecutor(context: context, now: now).apply([
            BrainAction(type: .createReminder, target: context.handle(for: backend), timePhrase: "tomorrow 5pm", reminderKind: .alarm),
        ])
        let saved = try #require(try store.all().first)
        #expect(saved.nodeID == backend.id && saved.kind == .alarm && saved.title == "Backend")
        #expect(calendar.component(.hour, from: saved.fireAt) == 17)
        #expect(result.reminders.map(\.id) == [saved.id])
        #expect(result.inverse.contains(.removeReminder(saved.id)))
    }

    @Test func standaloneVoiceReminderGetsATodo() throws {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let store = SwiftDataReminderStore(container: container)
        let context = BrainContext(store: nodes)
        context.reminders = store

        let result = try ActionExecutor(context: context, now: now).apply([
            BrainAction(type: .createReminder, title: "Call mom", timePhrase: "tomorrow 6pm"),
        ])
        let saved = try #require(try store.all().first)
        let todo = try #require(saved.nodeID.flatMap { try nodes.node(id: $0) })
        #expect(todo.title == "Call mom" && todo.status == .todo && nodes.isInRemindersList(todo))

        // Undo removes the todo too.
        try nodes.apply(result.inverse)
        #expect(try nodes.node(id: todo.id) == nil)
    }

    @Test func failedCommandSavesNoReminder() throws {
        let container = try LocalDatabase.inMemory()
        let store = SwiftDataReminderStore(container: container)
        let context = BrainContext(store: SwiftDataNodeStore(container: container))
        context.reminders = store
        #expect(throws: (any Error).self) {
            try ActionExecutor(context: context, now: now).apply([
                BrainAction(type: .createReminder, title: "Call mom", timePhrase: "6pm"),
                BrainAction(type: .deleteNode, target: "n99"),
            ])
        }
        #expect(try store.all().isEmpty)
    }

    @Test func previewShowsTheReminder() throws {
        let context = BrainContext(store: try SwiftDataNodeStore.inMemory())
        let steps = try PlanPreview(context: context).steps(for: [
            BrainAction(type: .createReminder, title: "Call mom", timePhrase: "tomorrow 6pm"),
        ]).steps
        #expect(steps.first?.title == "Call mom")
        #expect(steps.first?.note?.hasPrefix("Reminder, ") == true)
    }

    @Test func undoInBrainDeletesTheReminder() async throws {
        let container = try LocalDatabase.inMemory()
        let store = SwiftDataReminderStore(container: container)
        let log = SwiftDataActionLogStore(container: container)
        var removedIDs: [UUID] = []
        let brain = Brain(
            nodes: SwiftDataNodeStore(container: container), log: log, reminders: store,
            onReminders: { _, removed in removedIDs += removed }
        )
        let reminder = Reminder(title: "Call mom", fireAt: now.addingTimeInterval(3600))
        try store.save(reminder)
        let entry = ActionLogEntry(transcript: "remind me", actionsJSON: "[]", inverse: [.removeReminder(reminder.id)], summary: "Remind")
        try log.append(entry)

        try brain.undo(entry.id)
        #expect(try store.all().isEmpty)
        #expect(removedIDs == [reminder.id])
    }
}

/// "Remind me to buy groceries" with no time: a todo in the Reminders list.
@MainActor
struct NoTimeReminderTests {
    @Test func becomesATodoInReminders() throws {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let reminders = SwiftDataReminderStore(container: container)
        let context = BrainContext(store: nodes)
        context.reminders = reminders

        let action = BrainAction(type: .createReminder, title: "Buy groceries")
        let preview = try PlanPreview(context: context).steps(for: [action]).steps
        #expect(preview.first?.path == ["Reminders"])

        try ActionExecutor(context: context).apply([action])
        let list = try #require(try nodes.children(of: nil).first { $0.title == "Reminders" })
        #expect(try nodes.children(of: list.id).map { "\($0.title) \($0.status?.rawValue ?? "")" } == ["Buy groceries todo"])
        #expect(try reminders.all().isEmpty)

        // A second one reuses the same list.
        try ActionExecutor(context: BrainContext(store: nodes)).apply([BrainAction(type: .createReminder, title: "Do dishes", timePhrase: "")])
        #expect(try nodes.children(of: nil).filter { $0.title == "Reminders" }.count == 1)
        #expect(try nodes.children(of: list.id).count == 2)
    }
}

@MainActor
struct DeadlineNudgeTests {
    private let due = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 3600

    @Test func windowIsFourEstimatesWithinLimits() {
        #expect(DeadlineNudge.window(estimateMinutes: 30) == 2 * hour)
        #expect(DeadlineNudge.window(estimateMinutes: nil) == 2 * hour)
        #expect(DeadlineNudge.window(estimateMinutes: 300) == 20 * hour)
        #expect(DeadlineNudge.window(estimateMinutes: 10) == 2 * hour)
        #expect(DeadlineNudge.window(estimateMinutes: 5000) == 48 * hour)
    }

    @Test func nudgesComeCloserTogetherNearTheDeadline() {
        let node = Node(kind: .item, title: "Orbit API", status: .todo, dueAt: due, estimateMinutes: 30)
        let nudges = DeadlineNudge.nudges(for: node, now: due.addingTimeInterval(-5 * hour))
        #expect(nudges.map(\.lead) == [2 * hour, hour, 0.5 * hour, 0])
        #expect(nudges.map(\.fireAt) == nudges.map { due.addingTimeInterval(-$0.lead) })
        #expect(nudges.last?.body == "Due now")
        #expect(Set(nudges.map(\.id)).count == 4)
    }

    @Test func passedNudgesAreSkipped() {
        let node = Node(kind: .item, title: "Orbit API", dueAt: due, estimateMinutes: 30)
        let nudges = DeadlineNudge.nudges(for: node, now: due.addingTimeInterval(-0.75 * hour))
        #expect(nudges.map(\.lead) == [0.5 * hour, 0])
    }

    @Test func doneOrPastItemsGetNone() {
        let done = Node(kind: .item, title: "Shipped", status: .done, dueAt: due)
        #expect(DeadlineNudge.nudges(for: done, now: due.addingTimeInterval(-hour)).isEmpty)
        let late = Node(kind: .item, title: "Late", dueAt: due)
        #expect(DeadlineNudge.nudges(for: late, now: due.addingTimeInterval(1)).isEmpty)
    }
}
