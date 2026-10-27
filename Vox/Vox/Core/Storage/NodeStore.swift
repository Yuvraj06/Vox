import Foundation

/// The only way features read and write nodes.
/// Reads never return soft-deleted nodes.
protocol NodeStore {
    func node(id: UUID) throws -> Node?
    /// Children sorted by `position`. Pass nil for top-level nodes.
    func children(of parentID: UUID?) throws -> [Node]
    /// Every node below `id`, at any depth.
    func descendants(of id: UUID) throws -> [Node]
    func insert(_ node: Node) throws
    /// Saves all fields and bumps `updatedAt`.
    func update(_ node: Node) throws
    /// Soft deletes the node and everything below it.
    func delete(id: UUID) throws
}

extension NodeStore {
    /// Creates a node at the end of its parent's children.
    @discardableResult
    func create(
        kind: NodeKind,
        title: String,
        parentID: UUID?,
        status: TaskStatus? = nil,
        view: PageView? = nil,
        columnType: TaskStatus? = nil,
        color: String? = nil,
        body: String? = nil,
        details: [NodeDetail] = []
    ) throws -> Node {
        let last = try children(of: parentID).last?.position
        let node = Node(
            parentID: parentID,
            kind: kind,
            title: title,
            body: body,
            status: status,
            view: view,
            columnType: columnType,
            color: color,
            details: details,
            position: NodeOrdering.position(between: last, and: nil)
        )
        try insert(node)
        return node
    }

    /// Moves a child so it ends up at `index` among its siblings.
    func move(id: UUID, toIndex index: Int) throws {
        guard var node = try self.node(id: id) else { return }
        let siblings = try children(of: node.parentID).filter { $0.id != id }
        let clamped = min(max(index, 0), siblings.count)
        let before = clamped > 0 ? siblings[clamped - 1].position : nil
        let after = clamped < siblings.count ? siblings[clamped].position : nil
        node.position = NodeOrdering.position(between: before, and: after)
        try update(node)
    }
}

/// Position math for ordering siblings. Insert between 1 and 2 gives 1.5.
enum NodeOrdering {
    static func position(between before: Double?, and after: Double?) -> Double {
        switch (before, after) {
        case (nil, nil): 1
        case let (b?, nil): b + 1
        case let (nil, a?): a - 1
        case let (b?, a?): (b + a) / 2
        }
    }
}
