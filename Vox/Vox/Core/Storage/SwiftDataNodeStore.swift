import Foundation
import SwiftData

/// SwiftData row for a node. Only this file knows it exists.
/// Enums are stored as raw strings so the shape matches Postgres.
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
        position = node.position
        updatedAt = node.updatedAt
        deleted = node.deleted
    }

    var value: Node {
        Node(
            id: id,
            userID: userID,
            parentID: parentID,
            kind: NodeKind(rawValue: kind) ?? .item,
            title: title,
            body: body,
            status: status.flatMap(TaskStatus.init(rawValue:)),
            view: view.flatMap(FolderView.init(rawValue:)),
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deleted: deleted
        )
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

    /// Store on disk for the real app.
    static func persistent() throws -> SwiftDataNodeStore {
        SwiftDataNodeStore(container: try ModelContainer(for: NodeEntity.self))
    }

    /// Throwaway store for tests and previews.
    static func inMemory() throws -> SwiftDataNodeStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return SwiftDataNodeStore(container: try ModelContainer(for: NodeEntity.self, configurations: config))
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
