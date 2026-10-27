import FoundationModels

/// What the model returns for one command. Guided generation means it can only produce this shape.
@Generable(description: "The changes to make for one command.")
struct BrainPlan: Codable {
    @Guide(description: "Actions applied in order. Usually 1 to 6.", .maximumCount(8))
    var actions: [BrainAction]
}

/// One action, in a flat shape: every action uses the same fields and leaves the rest empty.
/// Kept flat on purpose so the schema stays small for the model's 4K window.
@Generable
struct BrainAction: Codable, Hashable {
    var type: ActionType
    @Guide(description: "The node this changes: an id from a tool like n3, or #2 for the node made by action 2.")
    var target: String?
    @Guide(description: "Where a new or moved node goes: an id like n3, #1, or top.")
    var parent: String?
    var title: String?
    var kind: KindChoice?
    var view: ViewChoice?
    var status: StatusChoice?
    var key: String?
    var value: String?
    @Guide(description: "Time words exactly as said, like tomorrow 5pm. Never a computed date.")
    var timePhrase: String?
    var estimateMinutes: Int?
    var reminderKind: ReminderChoice?
    @Guide(description: "For unclear only: a short question to ask the user.")
    var question: String?

    init(
        type: ActionType,
        target: String? = nil,
        parent: String? = nil,
        title: String? = nil,
        kind: KindChoice? = nil,
        view: ViewChoice? = nil,
        status: StatusChoice? = nil,
        key: String? = nil,
        value: String? = nil,
        timePhrase: String? = nil,
        estimateMinutes: Int? = nil,
        reminderKind: ReminderChoice? = nil,
        question: String? = nil
    ) {
        self.type = type
        self.target = target
        self.parent = parent
        self.title = title
        self.kind = kind
        self.view = view
        self.status = status
        self.key = key
        self.value = value
        self.timePhrase = timePhrase
        self.estimateMinutes = estimateMinutes
        self.reminderKind = reminderKind
        self.question = question
    }
}

extension BrainAction {
    /// An action that is still being written by the model. Nil until its type is known.
    init?(partial: BrainAction.PartiallyGenerated) {
        guard let type = partial.type else { return nil }
        self.init(
            type: type,
            target: partial.target,
            parent: partial.parent,
            title: partial.title,
            kind: partial.kind,
            view: partial.view,
            status: partial.status,
            key: partial.key,
            value: partial.value,
            timePhrase: partial.timePhrase,
            estimateMinutes: partial.estimateMinutes,
            reminderKind: partial.reminderKind,
            question: partial.question
        )
    }
}

@Generable
enum ActionType: String, Codable, CaseIterable {
    case createNode, addItem, setStatus, setDetail, setDue, renameNode, moveNode, deleteNode, createReminder, unclear
}

@Generable
enum KindChoice: String, Codable, CaseIterable {
    case item, note
}

@Generable
enum ViewChoice: String, Codable, CaseIterable {
    case list, checklist, board, folder
}

@Generable
enum StatusChoice: String, Codable, CaseIterable {
    case todo, doing, done
}

@Generable
enum ReminderChoice: String, Codable, CaseIterable {
    case reminder, alarm
}
