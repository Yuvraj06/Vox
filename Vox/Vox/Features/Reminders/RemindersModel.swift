import Foundation
import Observation

/// What the reminder screens talk to. Saves reminders, puts them on the system clock,
/// and builds the Today, Tomorrow and calendar lists on the home screen.
@Observable
final class RemindersModel {
    /// One thing on a day: a reminder or alarm going off, or an item's deadline.
    struct Entry: Identifiable, Hashable {
        enum Source: Hashable {
            case reminder(Reminder)
            case deadline(Node)
        }

        let date: Date
        let source: Source
        var id: String {
            switch source {
            case .reminder(let reminder): "\(reminder.id)-\(date.timeIntervalSince1970)"
            case .deadline(let node): "due-\(node.id)"
            }
        }
    }

    private let store: any ReminderStore
    private let nodes: any NodeStore
    private let scheduler: any ReminderScheduling
    /// Bumped after every write. Reads touch it so views redraw.
    private var revision = 0
    var errorMessage: String?

    init(store: any ReminderStore, nodes: any NodeStore, scheduler: any ReminderScheduling) {
        self.store = store
        self.nodes = nodes
        self.scheduler = scheduler
    }

    // MARK: Reads

    func reminders(for nodeID: UUID) -> [Reminder] {
        _ = revision
        return ((try? store.reminders(for: nodeID)) ?? []).filter { !$0.done }
    }

    /// Reminders, alarms and deadlines in `interval`, soonest first.
    func entries(in interval: DateInterval) -> [Entry] {
        _ = revision
        let reminders = ((try? store.all()) ?? []).filter { !$0.done }.flatMap { reminder in
            reminder.occurrences(in: interval).map { Entry(date: $0, source: .reminder(reminder)) }
        }
        let deadlines = allNodes().compactMap { node -> Entry? in
            guard let due = node.dueAt, interval.contains(due), node.status != .done else { return nil }
            return Entry(date: due, source: .deadline(node))
        }
        return (reminders + deadlines).sorted { $0.date < $1.date }
    }

    func entries(on day: Date, calendar: Calendar = .current) -> [Entry] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return entries(in: interval)
    }

    /// The next time of each pending reminder, alarm and deadline, soonest first. Repeats show once.
    func upcoming(from now: Date = .now, limit: Int? = nil) -> [Entry] {
        _ = revision
        let reminders = pending().compactMap { reminder in
            reminder.nextFire(after: now).map { Entry(date: $0, source: .reminder(reminder)) }
        }
        let deadlines = allNodes().compactMap { node -> Entry? in
            guard let due = node.dueAt, due > now, node.status != .done else { return nil }
            return Entry(date: due, source: .deadline(node))
        }
        let all = (reminders + deadlines).sorted { $0.date < $1.date }
        return limit.map { Array(all.prefix($0)) } ?? all
    }

    /// The next reminder or alarm to go off (not a deadline), and when the one before it went off.
    /// The countdown on the home screen runs between the two. Looks at reminders only, so it stays quick.
    func nextTimed(after now: Date = .now) -> (entry: Entry, since: Date)? {
        _ = revision
        let pending = pending()
        guard let (reminder, date) = pending
            .compactMap({ reminder in reminder.nextFire(after: now).map { (reminder, $0) } })
            .min(by: { $0.1 < $1.1 }) else { return nil }
        let lastDay = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        let previous = pending.flatMap { $0.occurrences(in: lastDay) }.max()
        let since = max(previous ?? reminder.updatedAt, date.addingTimeInterval(-86_400))
        return (Entry(date: date, source: .reminder(reminder)), min(since, now))
    }

    private func pending() -> [Reminder] {
        ((try? store.all()) ?? []).filter { !$0.done }
    }

    /// Start of every day in `interval` that has something on it. Used for the calendar dots.
    func busyDays(in interval: DateInterval, calendar: Calendar = .current) -> Set<Date> {
        Set(entries(in: interval).map { calendar.startOfDay(for: $0.date) })
    }

    /// True once it has been saved, so the editor can offer Delete.
    func isSaved(_ id: UUID) -> Bool {
        _ = revision
        return ((try? store.reminder(id: id)) ?? nil) != nil
    }

    func node(id: UUID) -> Node? {
        _ = revision
        return try? nodes.node(id: id)
    }

    // MARK: Writes

    /// Saves and schedules. Asks for permission the first time.
    func save(_ reminder: Reminder) {
        perform { try store.save(reminder) }
        Task {
            do {
                try await scheduler.schedule(reminder)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func delete(_ reminder: Reminder) {
        perform { try store.delete(id: reminder.id) }
        Task { await scheduler.cancel(id: reminder.id) }
    }

    /// A voice command made reminders, or an undo removed some. They are already saved or deleted.
    func changedOutside(added: [Reminder], removed: [UUID]) {
        revision += 1
        Task {
            for id in removed { await scheduler.cancel(id: id) }
            for reminder in added {
                do {
                    try await scheduler.schedule(reminder)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Puts every pending reminder back on the system clock. Run once at launch.
    func rescheduleAll() async {
        reconcile()
        for reminder in ((try? store.all()) ?? []) where !reminder.done && reminder.nextFire() != nil {
            try? await scheduler.schedule(reminder)
        }
    }

    /// Call after nodes change. Cancels reminders whose item is done or deleted,
    /// and marks one-time reminders that already went off as done.
    func reconcile(now: Date = .now) {
        for var reminder in ((try? store.all()) ?? []) where !reminder.done {
            var itemGone = false
            if let nodeID = reminder.nodeID {
                let node = (try? nodes.node(id: nodeID)) ?? nil
                itemGone = node == nil || node?.status == .done
            }
            let wentOff = reminder.repeatRule == nil && reminder.fireAt <= now
            guard itemGone || wentOff else { continue }
            reminder.done = true
            try? store.save(reminder)
            if itemGone {
                let id = reminder.id
                Task { await scheduler.cancel(id: id) }
            }
        }
        revision += 1
    }

    // MARK: Helpers

    private func allNodes() -> [Node] {
        let top = (try? nodes.children(of: nil)) ?? []
        return top + top.flatMap { (try? nodes.descendants(of: $0.id)) ?? [] }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
        revision += 1
    }
}
