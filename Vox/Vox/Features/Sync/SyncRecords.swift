import Foundation
import Supabase

// Rows exactly as the Supabase tables have them, snake_case and all.
// `owner` fills in rows made before signing in.

struct NodeRecord: Codable, Equatable {
    var id: UUID
    var userID: UUID
    var parentID: UUID?
    var kind: String
    var title: String
    var body: String?
    var status: String?
    var view: String?
    var color: String?
    var columnType: String?
    var details: [NodeDetail]?
    var dueAt: Date?
    var estimateMinutes: Int?
    var position: Double
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, status, view, color, details, position, deleted
        case userID = "user_id", parentID = "parent_id", columnType = "column_type", dueAt = "due_at"
        case estimateMinutes = "estimate_minutes", createdAt = "created_at", updatedAt = "updated_at"
    }

    init(_ node: Node, owner: UUID) {
        id = node.id
        userID = node.userID ?? owner
        parentID = node.parentID
        kind = node.kind.rawValue
        title = node.title
        body = node.body
        status = node.status?.rawValue
        view = node.view?.rawValue
        color = node.color
        columnType = node.columnType?.rawValue
        details = node.details.isEmpty ? nil : node.details
        dueAt = node.dueAt
        estimateMinutes = node.estimateMinutes
        position = node.position
        createdAt = node.createdAt
        updatedAt = node.updatedAt
        deleted = node.deleted
    }

    var node: Node {
        Node(
            id: id,
            userID: userID,
            parentID: parentID,
            kind: NodeKind(storedValue: kind),
            title: title,
            body: body,
            status: status.flatMap(TaskStatus.init(rawValue:)),
            view: view.flatMap(PageView.init(rawValue:)),
            columnType: columnType.flatMap(TaskStatus.init(rawValue:)),
            color: color,
            details: details ?? [],
            dueAt: dueAt,
            estimateMinutes: estimateMinutes,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deleted: deleted
        )
    }
}

struct ReminderRecord: Codable, Equatable {
    var id: UUID
    var userID: UUID
    var nodeID: UUID?
    var title: String
    var fireAt: Date
    var kind: String
    var repeatRule: String?
    var done: Bool
    var updatedAt: Date
    var deleted: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, kind, done, deleted
        case userID = "user_id", nodeID = "node_id", fireAt = "fire_at", repeatRule = "repeat_rule", updatedAt = "updated_at"
    }

    init(_ reminder: Reminder, owner: UUID) {
        id = reminder.id
        userID = reminder.userID ?? owner
        nodeID = reminder.nodeID
        title = reminder.title
        fireAt = reminder.fireAt
        kind = reminder.kind.rawValue
        repeatRule = reminder.repeatRule?.text
        done = reminder.done
        updatedAt = reminder.updatedAt
        deleted = reminder.deleted
    }

    var reminder: Reminder {
        Reminder(
            id: id,
            userID: userID,
            nodeID: nodeID,
            title: title,
            fireAt: fireAt,
            kind: ReminderKind(rawValue: kind) ?? .reminder,
            repeatRule: RepeatRule(text: repeatRule),
            done: done,
            updatedAt: updatedAt,
            deleted: deleted
        )
    }
}

struct ActionLogRecord: Codable, Equatable {
    var id: UUID
    var userID: UUID
    var createdAt: Date
    var transcript: String
    /// Real JSON in the `actions` jsonb column, not a string of it.
    var actions: AnyJSON
    var inverse: [InverseStep]
    var summary: String
    var undone: Bool

    enum CodingKeys: String, CodingKey {
        case id, transcript, actions, inverse, summary, undone
        case userID = "user_id", createdAt = "created_at"
    }

    init(_ entry: ActionLogEntry, owner: UUID) {
        id = entry.id
        userID = entry.userID ?? owner
        createdAt = entry.createdAt
        transcript = entry.transcript
        actions = (try? JSONDecoder().decode(AnyJSON.self, from: Data(entry.actionsJSON.utf8))) ?? .array([])
        inverse = entry.inverse
        summary = entry.summary
        undone = entry.undone
    }

    var entry: ActionLogEntry {
        let json = (try? JSONEncoder().encode(actions)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return ActionLogEntry(
            id: id,
            userID: userID,
            createdAt: createdAt,
            transcript: transcript,
            actionsJSON: json,
            inverse: inverse,
            summary: summary,
            undone: undone
        )
    }
}
