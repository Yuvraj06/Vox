import Foundation
import Observation

/// What the Notes screens talk to. Wraps a `NodeStore` and tells SwiftUI to refresh after every write.
@Observable
final class NotesModel {
    private let store: any NodeStore
    /// Bumped after every write. Reads touch it so views redraw.
    private var revision = 0
    var errorMessage: String?
    /// Called after every change, from this model or from outside (like a voice command).
    /// Reminders use it to cancel the ones whose item is done.
    var onChange: () -> Void = {}

    init(store: any NodeStore) {
        self.store = store
    }

    /// Call after something outside this model (like a voice command) changed nodes.
    func refresh() {
        revision += 1
        onChange()
    }

    // MARK: Reads

    func node(id: UUID) -> Node? {
        _ = revision
        return try? store.node(id: id)
    }

    func children(of parentID: UUID?) -> [Node] {
        _ = revision
        return (try? store.children(of: parentID)) ?? []
    }

    /// Done vs total for an item's direct sub-tasks. nil when it has none.
    func progress(of id: UUID) -> (done: Int, total: Int)? {
        let tasks = children(of: id).filter(\.isTask)
        guard !tasks.isEmpty else { return nil }
        return (tasks.filter { $0.status == .done }.count, tasks.count)
    }

    // MARK: Board reads

    /// One column as shown on a board. Several column items with the same title
    /// (one per section) merge into one column.
    struct BoardColumn: Identifiable {
        let title: String
        let type: TaskStatus?
        /// The real column items behind this column. The board's own comes first.
        let sources: [Node]
        let cards: [Node]
        var id: String { title.lowercased() }
    }

    /// Children of a board that are boards themselves.
    func sections(of board: Node) -> [Node] {
        children(of: board.id).filter(\.isBoard)
    }

    /// Children of an item that act as its board columns (everything that is not a section).
    func columnItems(in container: Node) -> [Node] {
        children(of: container.id).filter { $0.kind == .item && !$0.isBoard }
    }

    /// The board's columns. With no `section`, the board's own columns plus every section's, merged by title.
    func columns(for board: Node, section: Node? = nil) -> [BoardColumn] {
        let containers = section.map { [$0] } ?? [board] + sections(of: board)
        var order: [String] = []
        var groups: [String: [Node]] = [:]
        for container in containers {
            for column in columnItems(in: container) {
                let key = column.title.trimmingCharacters(in: .whitespaces).lowercased()
                if groups[key] == nil { order.append(key) }
                groups[key, default: []].append(column)
            }
        }
        return order.compactMap { key in
            guard let sources = groups[key], let first = sources.first else { return nil }
            return BoardColumn(
                title: first.title,
                type: first.columnType,
                sources: sources,
                cards: sources.flatMap { children(of: $0.id) }
            )
        }
    }

    func cardCount(of board: Node) -> Int {
        columns(for: board).reduce(0) { $0 + $1.cards.count }
    }

    // MARK: Writes

    func add(kind: NodeKind, title: String, parentID: UUID?, status: TaskStatus? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        perform { _ = try store.create(kind: kind, title: title, parentID: parentID, status: status) }
    }

    func save(_ node: Node) {
        perform { try store.update(node) }
    }

    func rename(_ node: Node, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != node.title else { return }
        var changed = node
        changed.title = title
        save(changed)
    }

    /// Sets the status. If the item is a board card, it also moves to a column that fits,
    /// so every view agrees (ticking done moves it to the Done column).
    func setStatus(_ node: Node, _ status: TaskStatus?) {
        var changed = node
        changed.status = status
        save(changed)
        moveToFittingColumn(changed)
    }

    func toggleDone(_ node: Node) {
        setStatus(node, node.status == .done ? .todo : .done)
    }

    /// Switching an empty item to a board gives it Todo, Doing, Done columns.
    func setView(_ item: Node, _ view: PageView) {
        var changed = item
        changed.view = view
        save(changed)
        if view == .board, children(of: item.id).isEmpty {
            perform { try store.addDefaultColumns(to: item.id) }
        }
    }

    // MARK: Folders

    /// New folder with the next preset color.
    func addFolder(_ title: String, parentID: UUID?) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let siblingFolders = children(of: parentID).filter(\.isFolder).count
        perform {
            try store.create(
                kind: .item, title: title, parentID: parentID,
                view: .folder, color: FolderPalette.preset(after: siblingFolders).hex
            )
        }
    }

    /// Turns a node into a list, checklist, board, folder or note. Pass nil as `view` for a note.
    /// Only an empty item can become a note, since notes can't hold items. Folders get a color and lose their status.
    func setType(_ node: Node, view: PageView?) {
        var changed = node
        if let view {
            if node.kind == .note {
                changed.kind = .item
                changed.view = .list
                save(changed)
            }
            if view == .folder {
                changed.status = nil
                if changed.color == nil {
                    let siblingFolders = children(of: node.parentID).filter(\.isFolder).count
                    changed.color = FolderPalette.preset(after: siblingFolders).hex
                }
                save(changed)
            }
            setView(changed, view)
        } else {
            guard node.kind == .item, children(of: node.id).isEmpty else { return }
            changed.kind = .note
            changed.view = nil
            changed.status = nil
            save(changed)
        }
    }

    func setColor(_ node: Node, hex: String) {
        guard node.color != hex else { return }
        var changed = node
        changed.color = hex
        save(changed)
    }

    /// Folders `node` can move into: every folder except itself, anything inside it, and where it already is.
    func folderDestinations(for node: Node) -> [Node] {
        var all: [Node] = []
        var queue: [UUID?] = [nil]
        while !queue.isEmpty {
            let kids = children(of: queue.removeFirst())
            all += kids
            queue += kids.filter { $0.kind == .item }.map(\.id)
        }
        let inside = Set(((try? store.descendants(of: node.id)) ?? []).map(\.id) + [node.id])
        return all.filter { $0.isFolder && !inside.contains($0.id) && $0.id != node.parentID }
    }

    /// Moves a node to the end of another parent. nil is the top level.
    func move(_ node: Node, to parentID: UUID?) {
        guard node.parentID != parentID else { return }
        var moved = node
        moved.parentID = parentID
        perform {
            moved.position = try store.endPosition(in: parentID, excluding: node.id)
            try store.update(moved)
        }
    }

    func delete(_ ids: [UUID]) {
        perform { for id in ids { try store.delete(id: id) } }
    }

    /// Matches SwiftUI's `onMove`: `destination` is an index in the list before the move.
    func move(in parentID: UUID?, from source: IndexSet, to destination: Int) {
        let siblings = children(of: parentID)
        guard let from = source.first, siblings.indices.contains(from) else { return }
        let target = destination > from ? destination - 1 : destination
        perform { try store.move(id: siblings[from].id, toIndex: target) }
    }

    // MARK: Board writes

    /// A section is a child board with its own Todo, Doing, Done columns.
    func addSection(_ title: String, to boardID: UUID?) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var section: Node?
        perform { section = try store.create(kind: .item, title: title, parentID: boardID) }
        if let section { setView(section, .board) }
    }

    /// New card at the bottom of a column. Goes into the first real column behind it.
    func addCard(_ title: String, to column: BoardColumn) {
        guard let source = column.sources.first else { return }
        add(kind: .item, title: title, parentID: source.id, status: ColumnRules.statusOnDrop(into: column.type, from: nil))
    }

    /// Drop a card into a column. It stays in its own section; if that section
    /// has no column with this title yet, one is created.
    func drop(_ card: Node, into column: BoardColumn) {
        guard let currentColumn = card.parentID.flatMap({ node(id: $0) }),
              let container = currentColumn.parentID else { return }
        var target = column.sources.first { $0.parentID == container }
        if target == nil {
            perform {
                target = try store.create(kind: .item, title: column.title, parentID: container, columnType: column.type)
            }
        }
        guard let target else { return }
        var changed = card
        changed.status = ColumnRules.statusOnDrop(into: target.columnType, from: card.status)
        if target.id != card.parentID {
            changed.parentID = target.id
            changed.position = endPosition(in: target.id, excluding: card.id)
        }
        save(changed)
    }

    /// One row in the column editor. `id` is nil for a new column.
    struct ColumnDraft: Identifiable {
        var id: UUID?
        var title: String
        var type: TaskStatus?
        let key = UUID()
    }

    func columnDrafts(in container: Node) -> [ColumnDraft] {
        columnItems(in: container).map { ColumnDraft(id: $0.id, title: $0.title, type: $0.columnType) }
    }

    /// Applies the column editor. Removed columns hand their cards to the first remaining column.
    func saveColumns(_ drafts: [ColumnDraft], in container: Node) {
        guard !drafts.isEmpty else { return }
        let existing = columnItems(in: container)
        perform {
            var kept: [Node] = []
            for (index, draft) in drafts.enumerated() {
                let title = draft.title.trimmingCharacters(in: .whitespaces)
                let finalTitle = title.isEmpty ? (draft.type?.label ?? "Column") : title
                if let id = draft.id, var column = existing.first(where: { $0.id == id }) {
                    column.title = finalTitle
                    column.columnType = draft.type
                    column.position = Double(index + 1)
                    try store.update(column)
                    kept.append(column)
                } else {
                    var column = try store.create(kind: .item, title: finalTitle, parentID: container.id, columnType: draft.type)
                    column.position = Double(index + 1)
                    try store.update(column)
                    kept.append(column)
                }
            }
            let removed = existing.filter { old in !kept.contains { $0.id == old.id } }
            if let first = kept.first {
                for column in removed {
                    for card in try store.children(of: column.id) {
                        var moved = card
                        moved.parentID = first.id
                        moved.position = endPosition(in: first.id, excluding: card.id)
                        moved.status = ColumnRules.statusOnDrop(into: first.columnType, from: card.status)
                        try store.update(moved)
                    }
                    try store.delete(id: column.id)
                }
            }
        }
        // Cards that came from a removed column may now sit in a column that doesn't fit.
        for column in columnItems(in: container) {
            for card in children(of: column.id) { moveToFittingColumn(card) }
        }
    }

    // MARK: Helpers

    private func moveToFittingColumn(_ card: Node) {
        perform { try store.moveToFittingColumn(card) }
    }

    private func endPosition(in parentID: UUID, excluding id: UUID) -> Double {
        (try? store.endPosition(in: parentID, excluding: id)) ?? 1
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
        revision += 1
        onChange()
    }
}
