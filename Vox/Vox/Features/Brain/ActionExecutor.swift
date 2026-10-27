import Foundation

/// Applies a list of actions to the store. All or nothing:
/// if any action fails, everything already done is rolled back.
final class ActionExecutor {
    enum Failure: Error, LocalizedError {
        /// The model asked a question instead of acting.
        case unclear(String)
        /// An action could not be applied. The message is for the user.
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .unclear(let question): question
            case .invalid(let message): message
            }
        }
    }

    struct Result {
        /// One line per action, for the screen. Like "Added Dune to Movies Watched".
        var lines: [String]
        /// Short text for the keychain, max 21 characters.
        var summary: String
        var inverse: [InverseStep]
        /// Reminders and alarms the command made. Already saved. The caller puts them on the clock.
        var reminders: [Reminder] = []
    }

    private let recorder: RecordingNodeStore
    private let context: BrainContext
    private let now: Date
    /// Nodes made by earlier actions, by action number (1 based). Referenced as #1, #2.
    private var made: [Int: UUID] = [:]
    /// Reminders worked out so far. Saved only when every action succeeded.
    private var newReminders: [Reminder] = []

    init(context: BrainContext, now: Date = .now) {
        self.context = context
        self.recorder = RecordingNodeStore(base: context.store)
        self.now = now
    }

    private var store: any NodeStore { recorder }

    func apply(_ actions: [BrainAction]) throws -> Result {
        if let unclear = actions.first(where: { $0.type == .unclear }) {
            throw Failure.unclear(unclear.question ?? "Sorry, what should I do?")
        }
        guard !actions.isEmpty else { throw Failure.invalid("I didn't find anything to do.") }

        var lines: [String] = []
        var summaries: [String] = []
        do {
            for (index, action) in actions.enumerated() {
                let outcome = try apply(action)
                if let id = outcome.made { made[index + 1] = id }
                lines.append(outcome.line)
                summaries.append(outcome.summary)
            }
            if !newReminders.isEmpty {
                guard let reminderStore = context.reminders else { throw Failure.invalid("Reminders aren't ready yet.") }
                for reminder in newReminders { try reminderStore.save(reminder) }
            }
        } catch {
            try? context.store.apply(recorder.inverse)
            for reminder in newReminders { try? context.reminders?.delete(id: reminder.id) }
            throw error
        }
        let inverse = recorder.inverse + newReminders.map { InverseStep.removeReminder($0.id) }
        return Result(lines: lines, summary: Self.summary(summaries), inverse: inverse, reminders: newReminders)
    }

    /// First action's summary, plus how many more, cut to 21 characters.
    static func summary(_ parts: [String]) -> String {
        guard let first = parts.first else { return "" }
        let more = parts.count > 1 ? " +\(parts.count - 1)" : ""
        let room = max(21 - more.count, 1)
        return String(first.prefix(room)) + more
    }

    // MARK: One action

    private struct Outcome {
        var made: UUID?
        var line: String
        var summary: String
    }

    private func apply(_ action: BrainAction) throws -> Outcome {
        switch action.type {
        case .createNode:
            let title = try required(action.title, "a title")
            let parent = try resolveParent(action.parent)
            let kind = NodeKind(rawValue: action.kind?.rawValue ?? "item") ?? .item
            let view = action.view.flatMap { PageView(rawValue: $0.rawValue) }
            let node: Node
            if let parent, parent.isBoard, view != .board {
                // A plain item on a board is a card, so it goes into a column.
                node = try addCard(title, kind: kind, status: nil, to: parent)
            } else {
                node = try store.create(kind: kind, title: title, parentID: parent?.id, view: view)
            }
            if view == .board { try store.addDefaultColumns(to: node.id) }
            let what = switch view {
            case .board: parent?.isBoard == true ? "section" : "board"
            case .folder: "folder"
            default: kind == .note ? "note" : "list"
            }
            return Outcome(
                made: node.id,
                line: "Created \(what) \(title)" + (parent.map { " in \($0.title)" } ?? ""),
                summary: "+ \(title)"
            )

        case .addItem:
            let title = try required(action.title, "a title")
            let parent = try resolveParent(action.parent)
            let status = action.status.flatMap { TaskStatus(rawValue: $0.rawValue) }
            let node = try addItem(title, status: status, to: parent)
            return Outcome(
                made: node.id,
                line: "Added \(title)" + (parent.map { " to \($0.title)" } ?? ""),
                summary: "+ \(title)" + (parent.map { " -> \(Self.firstWord($0.title))" } ?? "")
            )

        case .setStatus:
            var node = try resolveTarget(action.target)
            let status = try required(action.status.flatMap { TaskStatus(rawValue: $0.rawValue) }, "a status")
            node.status = status
            try store.update(node)
            try store.moveToFittingColumn(node)
            return Outcome(line: "\(node.title) is now \(status.label)", summary: "\(node.title): \(status.label)")

        case .setDetail:
            var node = try resolveTarget(action.target)
            let key = try required(action.key, "a field name").lowercased()
            let value = try required(action.value, "a value")
            if let index = node.details.firstIndex(where: { $0.key.lowercased() == key }) {
                node.details[index].value = value
            } else {
                node.details.append(NodeDetail(key: key, value: value))
            }
            try store.update(node)
            return Outcome(line: "Set \(key) of \(node.title) to \(value)", summary: "\(node.title) \(key)=\(value)")

        case .setDue:
            var node = try resolveTarget(action.target)
            let phrase = try required(action.timePhrase, "a time")
            guard let due = DatePhrase.date(from: phrase, now: now) else {
                throw Failure.invalid("I couldn't understand the time \"\(phrase)\".")
            }
            node.dueAt = due
            if let minutes = action.estimateMinutes, minutes > 0 { node.estimateMinutes = minutes }
            try store.update(node)
            let when = due.formatted(date: .abbreviated, time: .shortened)
            return Outcome(line: "\(node.title) is due \(when)", summary: "\(node.title) due")

        case .renameNode:
            var node = try resolveTarget(action.target)
            let title = try required(action.title, "a new title")
            let old = node.title
            node.title = title
            try store.update(node)
            return Outcome(line: "Renamed \(old) to \(title)", summary: "\(old) -> \(title)")

        case .moveNode:
            var node = try resolveTarget(action.target)
            let parent = try resolveParent(action.parent)
            let inside = try store.descendants(of: node.id).map(\.id) + [node.id]
            if let parent, inside.contains(parent.id) {
                throw Failure.invalid("I can't move \(node.title) inside itself.")
            }
            var newParentID = parent?.id
            if let parent, parent.isBoard {
                // Into a board means into the column that fits.
                newParentID = try column(on: parent, for: node.status ?? .todo).id
                node.status = node.status ?? .todo
            }
            node.parentID = newParentID
            node.position = try store.endPosition(in: newParentID, excluding: node.id)
            try store.update(node)
            let place = parent?.title ?? "the top level"
            return Outcome(line: "Moved \(node.title) to \(place)", summary: "\(node.title) -> \(Self.firstWord(place))")

        case .deleteNode:
            let node = try resolveTarget(action.target)
            try store.delete(id: node.id)
            return Outcome(line: "Deleted \(node.title)", summary: "- \(node.title)")

        case .createReminder:
            let linked = try action.target.flatMap { $0.isEmpty ? nil : try resolveTarget($0) }
            let phrase = action.timePhrase?.trimmingCharacters(in: .whitespaces) ?? ""
            if phrase.isEmpty {
                // No time said: a todo in the Reminders list. It stays there until ticked off.
                let title = try required(action.title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? linked?.title, "what to remind you about")
                let item = try store.create(kind: .item, title: title, parentID: try remindersList().id, status: .todo)
                return Outcome(made: item.id, line: "Added \(title) to Reminders", summary: "+ \(title) -> Reminders")
            }
            guard let fireAt = DatePhrase.firstFire(from: phrase, now: now) else {
                throw Failure.invalid("I couldn't understand the time \"\(phrase)\".")
            }
            let title = action.title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? linked?.title
            let kind: ReminderKind = action.reminderKind == .alarm ? .alarm : .reminder
            let reminder = Reminder(
                nodeID: linked?.id,
                title: try required(title, "what to remind you about"),
                fireAt: fireAt,
                kind: kind,
                repeatRule: DatePhrase.repeatRule(in: phrase)
            )
            newReminders.append(reminder)
            let when = reminder.repeatRule.map { "\($0.label.lowercased()) at \(fireAt.formatted(date: .omitted, time: .shortened))" }
                ?? fireAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            return Outcome(
                line: "\(kind.label) for \(reminder.title), \(when)",
                summary: "\(kind == .alarm ? "Alarm" : "Remind") \(fireAt.formatted(date: .omitted, time: .shortened))"
            )

        case .unclear:
            throw Failure.unclear(action.question ?? "Sorry, what should I do?")
        }
    }

    // MARK: Placing items

    /// Where reminders without a time go: the top level "Reminders" list, made the first time it's needed.
    static let remindersListTitle = "Reminders"

    private func remindersList() throws -> Node {
        if let list = try store.children(of: nil).first(where: {
            $0.kind == .item && $0.title.lowercased() == Self.remindersListTitle.lowercased()
        }) {
            return list
        }
        return try store.create(kind: .item, title: Self.remindersListTitle, parentID: nil, view: .checklist)
    }

    /// Adds an item under `parent`, following the parent's view.
    private func addItem(_ title: String, status: TaskStatus?, to parent: Node?) throws -> Node {
        guard let parent else { return try store.create(kind: .item, title: title, parentID: nil, status: status) }
        if parent.isBoard { return try addCard(title, kind: .item, status: status, to: parent) }
        // Inside a board column: the card takes the column's status.
        if let board = try parent.parentID.flatMap({ try store.node(id: $0) }), board.isBoard {
            let cardStatus = ColumnRules.statusOnDrop(into: parent.columnType, from: status)
            return try store.create(kind: .item, title: title, parentID: parent.id, status: cardStatus)
        }
        // Checklist rows are tasks.
        let rowStatus = status ?? (parent.view == .checklist ? .todo : nil)
        return try store.create(kind: .item, title: title, parentID: parent.id, status: rowStatus)
    }

    /// A card goes into the board column that fits its status.
    private func addCard(_ title: String, kind: NodeKind, status: TaskStatus?, to board: Node) throws -> Node {
        let target = try column(on: board, for: status ?? .todo)
        let cardStatus = kind == .item ? ColumnRules.statusOnDrop(into: target.columnType, from: status) : nil
        return try store.create(kind: kind, title: title, parentID: target.id, status: cardStatus)
    }

    /// The board's column for `status`. Uses the first section's columns if the board has none of its own,
    /// and makes Todo, Doing, Done if there are none at all.
    private func column(on board: Node, for status: TaskStatus) throws -> Node {
        var holder = board
        if try store.columnItems(in: board.id).isEmpty,
           let section = try store.children(of: board.id).first(where: \.isBoard) {
            holder = section
        }
        if try store.columnItems(in: holder.id).isEmpty {
            try store.addDefaultColumns(to: holder.id)
        }
        let columns = try store.columnItems(in: holder.id)
        guard let column = store.fittingColumn(among: columns, for: status) ?? columns.first else {
            throw Failure.invalid("\(board.title) has no columns.")
        }
        return column
    }

    // MARK: Refs

    private func resolveTarget(_ ref: String?) throws -> Node {
        let ref = try required(ref, "something to change")
        guard let node = try resolve(ref) else { throw Failure.invalid("I couldn't find \"\(ref)\".") }
        return node
    }

    /// nil means the top level.
    private func resolveParent(_ ref: String?) throws -> Node? {
        let ref = ref?.trimmingCharacters(in: .whitespaces) ?? ""
        if ref.isEmpty || ["top", "root", "none", "null"].contains(ref.lowercased()) { return nil }
        guard let node = try resolve(ref) else { throw Failure.invalid("I couldn't find \"\(ref)\".") }
        guard node.kind == .item else { throw Failure.invalid("\(node.title) is a note, so it can't hold items.") }
        return node
    }

    /// An id from a tool (n3), a node made earlier (#2), a UUID, or a title path like "Orbit/Frontend".
    private func resolve(_ ref: String) throws -> Node? {
        let ref = ref.trimmingCharacters(in: .whitespaces)
        if ref.hasPrefix("#"), let number = Int(ref.dropFirst()) {
            return try made[number].flatMap { try store.node(id: $0) }
        }
        if let id = context.id(forHandle: ref) ?? UUID(uuidString: ref) {
            return try store.node(id: id)
        }
        return try resolvePath(ref)
    }

    /// Fallback when the model writes a title instead of an id.
    private func resolvePath(_ path: String) throws -> Node? {
        let titles = path.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard let first = titles.first else { return nil }
        let madeNodes = try made.keys.sorted().compactMap { try made[$0].flatMap { try store.node(id: $0) } }
        var current = madeNodes.last { $0.title.lowercased() == first }
            ?? context.allNodes().first { $0.title.lowercased() == first }
        for title in titles.dropFirst() {
            guard let parent = current else { return nil }
            current = try store.children(of: parent.id).first { $0.title.lowercased() == title }
        }
        return current
    }

    private func required<T>(_ value: T?, _ what: String) throws -> T {
        if let text = value as? String, text.trimmingCharacters(in: .whitespaces).isEmpty {
            throw Failure.invalid("The command was missing \(what).")
        }
        guard let value else { throw Failure.invalid("The command was missing \(what).") }
        return value
    }

    private static func firstWord(_ title: String) -> String {
        title.split(separator: " ").first.map(String.init) ?? title
    }
}

/// Wraps a store and remembers how every touched node looked before,
/// so the changes can be rolled back or undone later.
final class RecordingNodeStore: NodeStore {
    private let base: any NodeStore
    private var order: [UUID] = []
    private var before: [UUID: Node?] = [:]

    init(base: any NodeStore) {
        self.base = base
    }

    /// Steps that put every touched node back the way it was.
    var inverse: [InverseStep] {
        order.map { id in before[id].flatMap { $0 }.map(InverseStep.restore) ?? .remove(id) }
    }

    func node(id: UUID) throws -> Node? { try base.node(id: id) }
    func children(of parentID: UUID?) throws -> [Node] { try base.children(of: parentID) }
    func descendants(of id: UUID) throws -> [Node] { try base.descendants(of: id) }

    func insert(_ node: Node) throws {
        remember(node.id, as: nil)
        try base.insert(node)
    }

    func update(_ node: Node) throws {
        remember(node.id, as: try base.node(id: node.id))
        try base.update(node)
    }

    func delete(id: UUID) throws {
        for node in try [base.node(id: id)].compactMap({ $0 }) + base.descendants(of: id) {
            remember(node.id, as: node)
        }
        try base.delete(id: id)
    }

    /// Only the first copy counts: that is how it looked before the command.
    private func remember(_ id: UUID, as node: Node?) {
        guard before.index(forKey: id) == nil else { return }
        before[id] = .some(node)
        order.append(id)
    }
}
