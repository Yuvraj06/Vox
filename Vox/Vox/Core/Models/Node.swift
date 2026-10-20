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
    var status: TaskStatus?
    var view: FolderView?
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
        view: FolderView? = nil,
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
        // Status only makes sense for tasks, view only for folders.
        self.status = kind == .task ? (status ?? .todo) : nil
        self.view = kind == .folder ? (view ?? .list) : nil
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
    }
}

enum NodeKind: String, Codable, CaseIterable, Sendable {
    case folder, list, item, task, note

    /// Kinds that can hold children.
    var isContainer: Bool { self == .folder || self == .list }
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

enum FolderView: String, Codable, CaseIterable, Sendable {
    case list, board
}
