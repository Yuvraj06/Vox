import Foundation

/// One entry in the notes tree. Same shape as the `nodes` table in Supabase.
/// This is a plain value type, so the UI never touches SwiftData directly.
struct Node: Identifiable, Hashable, Sendable {
    var id: UUID
    var userID: UUID?
    var parentID: UUID?
    var kind: NodeKind
    var title: String
    var body: String?
    /// Entries only. nil = plain line, set = task.
    var status: TaskStatus?
    /// Pages only.
    var view: PageView?
    /// Pages only. Empty = the default Todo, Doing, Done columns.
    var columns: [BoardColumnDef]
    /// Entries only. Which board column the entry sits in.
    var columnID: UUID?
    /// Small ordered fields, like rating or coordinates.
    var details: [NodeDetail]
    var dueAt: Date?
    var estimateMinutes: Int?
    var position: Double
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        parentID: UUID? = nil,
        kind: NodeKind,
        title: String,
        body: String? = nil,
        status: TaskStatus? = nil,
        view: PageView? = nil,
        columns: [BoardColumnDef] = [],
        columnID: UUID? = nil,
        details: [NodeDetail] = [],
        dueAt: Date? = nil,
        estimateMinutes: Int? = nil,
        position: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deleted: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.parentID = parentID
        self.kind = kind
        self.title = title
        self.body = body
        self.status = kind == .entry ? status : nil
        self.view = kind == .page ? (view ?? .list) : nil
        self.columns = kind == .page ? columns : []
        self.columnID = kind == .entry ? columnID : nil
        self.details = details
        self.dueAt = dueAt
        self.estimateMinutes = estimateMinutes
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    var isTask: Bool { status != nil }
}

enum NodeKind: String, Codable, CaseIterable, Sendable {
    case page, entry, note

    /// Reads kinds saved by older builds (folder, list, item, task).
    init(storedValue: String) {
        switch storedValue {
        case "page", "folder", "list": self = .page
        case "note": self = .note
        default: self = .entry
        }
    }
}

enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case todo, doing, done

    var label: String {
        switch self {
        case .todo: "Todo"
        case .doing: "Doing"
        case .done: "Done"
        }
    }
}

enum PageView: String, Codable, CaseIterable, Sendable {
    case list, checklist, board

    var label: String {
        switch self {
        case .list: "List"
        case .checklist: "Checklist"
        case .board: "Board"
        }
    }
}

struct NodeDetail: Codable, Hashable, Sendable {
    var key: String
    var value: String
}

/// One board column. The `status` is its type: it sets the tint and what counts as finished.
/// nil = neutral: no tint, holds tasks that are not finished.
struct BoardColumnDef: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var title: String
    var status: TaskStatus?

    init(id: UUID = UUID(), title: String, status: TaskStatus?) {
        self.id = id
        self.title = title
        self.status = status
    }

    /// Used when a page has no custom columns. Fixed ids so cards stay put.
    static let defaults: [BoardColumnDef] = [
        BoardColumnDef(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!, title: "Todo", status: .todo),
        BoardColumnDef(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!, title: "Doing", status: .doing),
        BoardColumnDef(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!, title: "Done", status: .done),
    ]

    /// Typed columns hold their own status. Neutral columns hold anything not finished.
    func accepts(_ entryStatus: TaskStatus?) -> Bool {
        if let status { return entryStatus == status }
        return entryStatus != .done
    }

    /// The status a card gets when dropped here. Neutral keeps Todo or Doing, and reopens Done.
    func statusOnDrop(from current: TaskStatus?) -> TaskStatus {
        if let status { return status }
        if let current, current != .done { return current }
        return .todo
    }

    /// Which column a task card shows in: its own column if that still fits its status,
    /// else the first column of that type, else the first column that accepts it, else the first column.
    static func placement(of entry: Node, in columns: [BoardColumnDef]) -> UUID? {
        if let own = columns.first(where: { $0.id == entry.columnID }), own.accepts(entry.status) {
            return own.id
        }
        return (columns.first { $0.status != nil && $0.status == entry.status }
            ?? columns.first { $0.accepts(entry.status) }
            ?? columns.first)?.id
    }
}
