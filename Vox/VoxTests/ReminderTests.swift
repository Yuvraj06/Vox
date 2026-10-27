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
