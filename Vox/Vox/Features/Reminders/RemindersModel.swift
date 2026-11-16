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
    /// Called after this model changed nodes itself (made, reopened or removed a reminder's todo), so the notes screens redraw.
    var onNodesChanged: () -> Void = {}

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
    /// Ones that already went off stay, so a day shows everything it had. Cancelled ones still to come don't.
    func entries(in interval: DateInterval, now: Date = .now) -> [Entry] {
        _ = revision
        let reminders = ((try? store.all()) ?? []).filter { !$0.done || $0.fireAt <= now }.flatMap { reminder in
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

    /// The next reminder, alarm or deadline, and when the one before it went off.
    /// The countdown on the home screen runs between the two.
    func nextTimed(after now: Date = .now) -> (entry: Entry, since: Date)? {
        _ = revision
        let pending = pending()
        // Each with the time it was set, where the countdown starts if nothing went off before it.
        let reminders = pending.compactMap { reminder in
            reminder.nextFire(after: now).map { (entry: Entry(date: $0, source: .reminder(reminder)), set: reminder.updatedAt) }
        }
        let deadlines = allNodes().compactMap { node -> (entry: Entry, set: Date)? in
            guard let due = node.dueAt, due > now, node.status != .done else { return nil }
            return (Entry(date: due, source: .deadline(node)), node.updatedAt)
        }
        guard let next = (reminders + deadlines).min(by: { $0.entry.date < $1.entry.date }) else { return nil }
        let lastDay = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        let previous = pending.flatMap { $0.occurrences(in: lastDay) }.max()
        let since = max(previous ?? next.set, next.entry.date.addingTimeInterval(-86_400))
        return (next.entry, min(since, now))
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

    /// The todo an entry ticks off: the reminder's item, or the item with the deadline.
    func todo(for entry: Entry) -> Node? {
        switch entry.source {
        case .deadline(let node): return node
        case .reminder(let reminder): return reminder.nodeID.flatMap(node(id:))
        }
    }

    /// The item a reminder is about, to open on tap. Nil for a reminder's own todo in the Reminders list,
    /// which opens the reminder editor instead.
    func linkedItem(of reminder: Reminder) -> Node? {
        guard let node = reminder.nodeID.flatMap(node(id:)), !nodes.isInRemindersList(node) else { return nil }
        return node
    }

    /// Todos with no time still to come. Ones whose reminder is still ahead already show in the dated list.
    func untimed(_ todos: [Node], now: Date = .now) -> [Node] {
        _ = revision
        let timed = Set(pending().filter { $0.nextFire(after: now) != nil }.compactMap(\.nodeID))
        return todos.filter { !timed.contains($0.id) }
    }

    // MARK: Writes

    /// Saves and schedules. Asks for permission the first time.
    /// A reminder about nothing in particular gets a todo in the Reminders list, so it can be ticked off.
    func save(_ reminder: Reminder) {
        var reminder = reminder
        var nodesChanged = false
        perform {
            if reminder.nodeID == nil, !reminder.done {
                reminder.nodeID = try nodes.makeTodo(for: reminder).id
                nodesChanged = true
            } else if let id = reminder.nodeID, var todo = try nodes.node(id: id),
                      nodes.isInRemindersList(todo), todo.title != reminder.title {
                // Its own todo follows the reminder's title.
                todo.title = reminder.title
                try nodes.update(todo)
                nodesChanged = true
            }
            try store.save(reminder)
        }
        if nodesChanged { onNodesChanged() }
        Task {
            do {
                try await scheduler.schedule(reminder)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Deletes it, and its todo in the Reminders list if it has one. Items elsewhere stay.
    func delete(_ reminder: Reminder) {
        var nodesChanged = false
        perform {
            try store.delete(id: reminder.id)
            if let id = reminder.nodeID, let todo = try nodes.node(id: id), nodes.isInRemindersList(todo) {
                try nodes.delete(id: id)
                nodesChanged = true
            }
        }
        if nodesChanged { onNodesChanged() }
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

    /// Call after nodes change. Gives every reminder a todo, cancels reminders whose item is done or deleted,
    /// and marks one-time reminders that already went off as done (their todo stays until ticked).
    /// A repeating reminder's own todo, ticked, only counts for that time: it opens again when the reminder next goes off.
    func reconcile(now: Date = .now) {
        var nodesChanged = false
        for var reminder in ((try? store.all()) ?? []) where !reminder.done {
            if reminder.nodeID == nil, let todo = try? nodes.makeTodo(for: reminder) {
                reminder.nodeID = todo.id
                try? store.save(reminder)
                nodesChanged = true
            }
            var itemGone = false
            if let nodeID = reminder.nodeID {
                let node = (try? nodes.node(id: nodeID)) ?? nil
                if var node, node.status == .done, reminder.repeatRule != nil, nodes.isInRemindersList(node) {
                    if node.updatedAt < now, !reminder.occurrences(in: DateInterval(start: node.updatedAt, end: now)).isEmpty {
                        node.status = .todo
                        try? nodes.update(node)
                        nodesChanged = true
                    }
                    continue
                }
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
        if nodesChanged { onNodesChanged() }
        rescheduleNudges(now: now)
    }

    /// iOS keeps at most 64 waiting notifications per app. Nudges take the soonest 40, leaving room for reminders.
    static let maxNudges = 40
    /// The last nudge update. The next one waits for it, so two never mix.
    private var nudgeTask: Task<Void, Never>?

    /// Puts deadline nudges on the clock for every open item with a due date, replacing the old ones.
    private func rescheduleNudges(now: Date) {
        let nudges = allNodes()
            .flatMap { DeadlineNudge.nudges(for: $0, now: now) }
            .sorted { $0.fireAt < $1.fireAt }
            .prefix(Self.maxNudges)
        let previous = nudgeTask
        nudgeTask = Task { [scheduler] in
            await previous?.value
            await scheduler.replaceNudges(Array(nudges))
        }
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
