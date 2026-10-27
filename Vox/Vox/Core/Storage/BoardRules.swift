import Foundation

/// Board rules that more than one feature needs (Notes screens and the Brain).
extension NodeStore {
    /// Children of an item that act as its board columns (everything that is not a section).
    func columnItems(in containerID: UUID) throws -> [Node] {
        try children(of: containerID).filter { $0.kind == .item && !$0.isBoard }
    }

    /// Gives an item Todo, Doing, Done columns.
    func addDefaultColumns(to itemID: UUID) throws {
        for status in TaskStatus.allCases {
            try create(kind: .item, title: status.label, parentID: itemID, columnType: status)
        }
    }

    /// The column a card with `status` belongs in: a column of that type first, then any that accepts it.
    func fittingColumn(among columns: [Node], for status: TaskStatus?) -> Node? {
        columns.first { $0.columnType != nil && $0.columnType == status }
            ?? columns.first { ColumnRules.accepts($0.columnType, status) }
    }

    /// If `card` sits in a board column that no longer fits its status, moves it to a sibling column that does.
    func moveToFittingColumn(_ card: Node) throws {
        guard let column = try card.parentID.flatMap({ try node(id: $0) }), !column.isBoard,
              let board = try column.parentID.flatMap({ try node(id: $0) }), board.isBoard,
              !ColumnRules.accepts(column.columnType, card.status),
              let target = fittingColumn(among: try columnItems(in: board.id), for: card.status) else { return }
        var moved = card
        moved.parentID = target.id
        moved.position = try endPosition(in: target.id, excluding: card.id)
        try update(moved)
    }

    /// A position after every child of `parentID`, ignoring `id`.
    func endPosition(in parentID: UUID?, excluding id: UUID) throws -> Double {
        let last = try children(of: parentID).filter { $0.id != id }.last?.position
        return NodeOrdering.position(between: last, and: nil)
    }
}
