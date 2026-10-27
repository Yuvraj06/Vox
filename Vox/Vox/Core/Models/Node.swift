import Foundation

/// One entry in the notes tree. Same shape as the `nodes` table in Supabase.
/// This is a plain value type, so the UI never touches SwiftData directly.
struct Node: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var userID: UUID?
    var parentID: UUID?
    var kind: NodeKind
    var title: String
    var body: String?
    /// nil = plain item, set = task.
    var status: TaskStatus?
    /// Items only. How this item's children are shown.
    var view: PageView?
    /// Items only. When this item is a board column: its type. nil = neutral.
    var columnType: TaskStatus?
    /// Items only. A color the user picked, as hex like "#F7AD52". Used by folders.
    var color: String?
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
        columnType: TaskStatus? = nil,
        color: String? = nil,
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
        self.status = kind == .item ? status : nil
        self.view = kind == .item ? (view ?? .list) : nil
        self.columnType = kind == .item ? columnType : nil
        self.color = kind == .item ? color : nil
        self.details = details
        self.dueAt = dueAt
        self.estimateMinutes = estimateMinutes
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    var isTask: Bool { status != nil }
    var isBoard: Bool { view == .board }
    var isFolder: Bool { view == .folder }
}

enum NodeKind: String, Codable, CaseIterable, Sendable {
    case item, note

    /// Reads kinds saved by older builds (page, entry, folder, list, task).
    init(storedValue: String) {
        self = storedValue == "note" ? .note : .item
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
    case list, checklist, board, folder

    var label: String {
        switch self {
        case .list: "List"
        case .checklist: "Checklist"
        case .board: "Board"
        case .folder: "Folder"
        }
    }
}

struct NodeDetail: Codable, Hashable, Sendable {
    var key: String
    var value: String
}

/// Rules for board column types. `nil` is a neutral column.
enum ColumnRules {
    /// Typed columns hold their own status. Neutral columns hold anything not finished.
    static func accepts(_ columnType: TaskStatus?, _ status: TaskStatus?) -> Bool {
        if let columnType { return status == columnType }
        return status != .done
    }

    /// The status a card gets when it lands in a column. Neutral keeps Todo or Doing, and reopens Done.
    static func statusOnDrop(into columnType: TaskStatus?, from current: TaskStatus?) -> TaskStatus {
        if let columnType { return columnType }
        if let current, current != .done { return current }
        return .todo
    }
}
