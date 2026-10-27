import Foundation

/// Describes what actions would do, as trails like Todo -> Movies -> Dune, without changing anything.
/// Also spots plans that deserve a second look in the Thinking tab.
struct PlanPreview {
    enum Problem: Error, Equatable {
        /// A ref points nowhere. The full Brain might do better.
        case unknownRef(String)
        /// Something the app can't do yet. No point retrying.
        case unsupported(String)
    }

    struct Result {
        var steps: [PlanStep]
        /// True when a ref was only found by title, not by an id the model was given.
        var guessedRef = false
        /// True when a new top level list looks like one that already exists.
        var maybeDuplicate = false
        /// The full path of nodes made by earlier actions, by action number (1 based), for #1 refs.
        fileprivate var made: [Int: [String]] = [:]
    }

    let context: BrainContext

    /// Steps for the actions written so far. Used while streaming, so unfinished actions are skipped quietly.
    func partialSteps(for actions: [BrainAction]) -> [PlanStep] {
        var result = Result(steps: [])
        for (index, action) in actions.enumerated() {
            guard let step = try? step(for: action, index: index, into: &result) else { continue }
            result.steps.append(step)
        }
        return result.steps
    }

    func steps(for actions: [BrainAction]) throws(Problem) -> Result {
        var result = Result(steps: [])
        for (index, action) in actions.enumerated() {
            result.steps.append(try step(for: action, index: index, into: &result))
        }
        return result
    }

    // MARK: One action

    /// Also notes in `result` what nodes it makes and anything that looks unsure.
    private func step(for action: BrainAction, index: Int, into result: inout Result) throws(Problem) -> PlanStep {
        func place(_ ref: String?) throws(Problem) -> [String] {
            switch resolve(ref, made: result.made) {
            case .top: return []
            case .path(let path, let guessed):
                if guessed { result.guessedRef = true }
                return path
            case .missing(let ref): throw .unknownRef(ref)
            }
        }
        func target(_ ref: String?) throws(Problem) -> (path: [String], title: String) {
            let path = try place(ref)
            guard let title = path.last else { throw .unknownRef(ref ?? "") }
            return (Array(path.dropLast()), title)
        }

        switch action.type {
        case .createNode:
            let title = try nonEmpty(action.title)
            let path = try place(action.parent)
            result.made[index + 1] = path + [title]
            if path.isEmpty, !NodeSearch.rank(query: title, in: context.allNodes(), ancestors: context.ancestorTitles(of:)).isEmpty {
                result.maybeDuplicate = true
            }
            let what = action.kind == .note ? "note" : (action.view?.rawValue ?? "list")
            return PlanStep(id: index, verb: .create, path: path, title: title, note: what)

        case .addItem:
            let title = try nonEmpty(action.title)
            var path = try place(action.parent)
            // A card on a board lands in the column for its status.
            if let parent = node(at: action.parent), parent.isBoard {
                path.append((action.status.flatMap { TaskStatus(rawValue: $0.rawValue) } ?? .todo).label)
            }
            result.made[index + 1] = path + [title]
            let status = action.status.flatMap { TaskStatus(rawValue: $0.rawValue) }?.label
            return PlanStep(id: index, verb: .add, path: path, title: title, note: status)

        case .setStatus:
            let node = try target(action.target)
            let status = action.status.flatMap { TaskStatus(rawValue: $0.rawValue) }?.label ?? "?"
            return PlanStep(id: index, verb: .change, path: node.path, title: node.title, note: status)

        case .setDetail:
            let node = try target(action.target)
            return PlanStep(id: index, verb: .change, path: node.path, title: node.title, note: "\(action.key ?? "?") \(action.value ?? "?")")

        case .setDue:
            let node = try target(action.target)
            var note = "due \(action.timePhrase ?? "?")"
            if let minutes = action.estimateMinutes, minutes > 0 { note += ", \(minutes) min" }
            return PlanStep(id: index, verb: .change, path: node.path, title: node.title, note: note)

        case .renameNode:
            let node = try target(action.target)
            let title = try nonEmpty(action.title)
            return PlanStep(id: index, verb: .rename, path: node.path, title: title, note: "was \(node.title)")

        case .moveNode:
            let node = try target(action.target)
            let path = try place(action.parent)
            return PlanStep(id: index, verb: .move, path: path, title: node.title, note: nil)

        case .deleteNode:
            let node = try target(action.target)
            return PlanStep(id: index, verb: .delete, path: node.path, title: node.title, note: nil)

        case .createReminder:
            let path = action.target.map { $0.isEmpty ? [] : (try? place($0)) ?? [] } ?? []
            let phrase = action.timePhrase?.trimmingCharacters(in: .whitespaces) ?? ""
            if phrase.isEmpty {
                // No time: a todo in the Reminders list, like the executor does.
                let title = action.title.flatMap { $0.isEmpty ? nil : $0 } ?? path.last ?? "Reminder"
                return PlanStep(id: index, verb: .add, path: [ActionExecutor.remindersListTitle], title: title, note: "no time")
            }
            guard let fireAt = DatePhrase.firstFire(from: phrase) else {
                throw .unsupported("I couldn't understand the time \"\(phrase)\". Try something like tomorrow 5pm.")
            }
            let title = action.title.flatMap { $0.isEmpty ? nil : $0 } ?? path.last ?? "Reminder"
            let when = DatePhrase.repeatRule(in: phrase).map { "\($0.label.lowercased()) \(fireAt.formatted(date: .omitted, time: .shortened))" }
                ?? fireAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())
            let kind = action.reminderKind == .alarm ? "Alarm" : "Reminder"
            return PlanStep(id: index, verb: .add, path: path, title: title, note: "\(kind), \(when)")

        case .unclear:
            throw .unknownRef("")
        }
    }

    // MARK: Refs

    private enum Place {
        case top
        /// Full path including the node's own title. `guessed` means it was found by title only.
        case path([String], guessed: Bool)
        case missing(String)
    }

    /// Same rules as the executor: top, #2, an id like n3, a UUID, or a title.
    private func resolve(_ ref: String?, made: [Int: [String]]) -> Place {
        let ref = ref?.trimmingCharacters(in: .whitespaces) ?? ""
        if ref.isEmpty || ["top", "root", "none", "null"].contains(ref.lowercased()) { return .top }
        if ref.hasPrefix("#") {
            guard let number = Int(ref.dropFirst()), let path = made[number] else { return .missing(ref) }
            return .path(path, guessed: false)
        }
        if let node = node(at: ref) {
            let guessed = context.id(forHandle: ref) == nil && UUID(uuidString: ref) == nil
            return .path(context.ancestorTitles(of: node) + [node.title], guessed: guessed)
        }
        return .missing(ref)
    }

    /// An existing node for a ref, if there is one. The title fallback matches the executor's.
    private func node(at ref: String?) -> Node? {
        guard let ref = ref?.trimmingCharacters(in: .whitespaces), !ref.isEmpty, !ref.hasPrefix("#") else { return nil }
        if let id = context.id(forHandle: ref) ?? UUID(uuidString: ref) {
            return try? context.store.node(id: id)
        }
        let first = ref.split(separator: "/").first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        var current = context.allNodes().first { $0.title.lowercased() == first }
        for title in ref.split(separator: "/").dropFirst().map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            guard let parent = current else { return nil }
            current = (try? context.store.children(of: parent.id))?.first { $0.title.lowercased() == title }
        }
        return current
    }

    private func nonEmpty(_ text: String?) throws(Problem) -> String {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { throw .unknownRef("") }
        return text
    }
}
