import Foundation
import SwiftData

/// SwiftData row for a node. Only this file knows it exists.
/// Enums are stored as raw strings so the shape matches Postgres.
/// New fields are optional so older saved data still opens.
@Model
final class NodeEntity {
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var parentID: UUID?
    var kind: String
    var title: String
    var body: String?
    var status: String?
    var view: String?
    /// JSON array of {key, value}. Matches the `details` jsonb column.
    var detailsJSON: String?
    var columnType: String?
    var color: String?
    var dueAt: Date?
    var estimateMinutes: Int?
    var position: Double
    var createdAt: Date
    var updatedAt: Date
    var deleted: Bool

    init(_ node: Node) {
        id = node.id
        userID = node.userID
        parentID = node.parentID
        kind = node.kind.rawValue
        title = node.title
        body = node.body
        status = node.status?.rawValue
        view = node.view?.rawValue
        detailsJSON = Self.encode(node.details)
        columnType = node.columnType?.rawValue
        color = node.color
        dueAt = node.dueAt
        estimateMinutes = node.estimateMinutes
        position = node.position
        createdAt = node.createdAt
        updatedAt = node.updatedAt
        deleted = node.deleted
    }

    func apply(_ node: Node) {
        userID = node.userID
        parentID = node.parentID
        kind = node.kind.rawValue
        title = node.title
        body = node.body
        status = node.status?.rawValue
        view = node.view?.rawValue
        detailsJSON = Self.encode(node.details)
        columnType = node.columnType?.rawValue
        color = node.color
        dueAt = node.dueAt
        estimateMinutes = node.estimateMinutes
        position = node.position
        updatedAt = node.updatedAt
        deleted = node.deleted
    }

    var value: Node {
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
            details: Self.decode(detailsJSON),
            dueAt: dueAt,
            estimateMinutes: estimateMinutes,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deleted: deleted
        )
    }

    /// Empty arrays are stored as nil, like a null jsonb column.
    private static func encode<T: Encodable>(_ values: [T]) -> String? {
        guard !values.isEmpty, let data = try? JSONEncoder().encode(values) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decode<T: Decodable>(_ json: String?) -> [T] {
        guard let json else { return [] }
        return (try? JSONDecoder().decode([T].self, from: Data(json.utf8))) ?? []
    }
}

enum NodeStoreError: Error {
    case notFound(UUID)
}

final class SwiftDataNodeStore: NodeStore {
    // Keep the container alive. The context alone does not retain it.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Throwaway store for tests and previews.
    static func inMemory() throws -> SwiftDataNodeStore {
        SwiftDataNodeStore(container: try LocalDatabase.inMemory())
    }

    func node(id: UUID) throws -> Node? {
        try entity(id: id).flatMap { $0.deleted ? nil : $0.value }
    }

    func children(of parentID: UUID?) throws -> [Node] {
        let descriptor = FetchDescriptor<NodeEntity>(
            predicate: #Predicate { $0.parentID == parentID && !$0.deleted },
            sortBy: [SortDescriptor(\.position)]
        )
        return try context.fetch(descriptor).map(\.value)
    }

    func descendants(of id: UUID) throws -> [Node] {
        var result: [Node] = []
        var queue = [id]
        while !queue.isEmpty {
            let kids = try children(of: queue.removeFirst())
            result += kids
            queue += kids.map(\.id)
        }
        return result
    }

    func insert(_ node: Node) throws {
        context.insert(NodeEntity(node))
        try context.save()
    }

    func update(_ node: Node) throws {
        guard let entity = try entity(id: node.id) else { throw NodeStoreError.notFound(node.id) }
        var changed = node
        changed.updatedAt = .now
        entity.apply(changed)
        try context.save()
    }

    func delete(id: UUID) throws {
        let ids = [id] + (try descendants(of: id).map(\.id))
        let now = Date.now
        for nodeID in ids {
            guard let entity = try entity(id: nodeID) else { continue }
            entity.deleted = true
            entity.updatedAt = now
        }
        try context.save()
    }

    private func entity(id: UUID) throws -> NodeEntity? {
        var descriptor = FetchDescriptor<NodeEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
