import Foundation
import Observation

/// What the Notes screens talk to. Wraps a `NodeStore` and tells SwiftUI to refresh after every write.
@Observable
final class NotesModel {
    private let store: any NodeStore
    /// Bumped after every write. Reads touch it so views redraw.
    private var revision = 0
    var errorMessage: String?

    init(store: any NodeStore) {
        self.store = store
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

    /// Board cards: task entries in this page and its sub-pages.
    /// Sub-entries are not cards; they show up as progress on their parent card.
    func boardEntries(under pageID: UUID) -> [Node] {
        _ = revision
        var result: [Node] = []
        var pages = [pageID]
        while !pages.isEmpty {
            for child in children(of: pages.removeFirst()) {
                if child.kind == .page { pages.append(child.id) }
                if child.isTask { result.append(child) }
            }
        }
        return result
    }

    /// Done vs total for an entry's direct sub-tasks. nil when it has none.
    func progress(of entryID: UUID) -> (done: Int, total: Int)? {
        let tasks = children(of: entryID).filter(\.isTask)
        guard !tasks.isEmpty else { return nil }
        return (tasks.filter { $0.status == .done }.count, tasks.count)
    }

    // MARK: Writes

    /// A page's board columns, or the defaults if it has none yet.
    func columns(of page: Node) -> [BoardColumnDef] {
        page.columns.isEmpty ? BoardColumnDef.defaults : page.columns
    }

    func setColumns(_ page: Node, _ columns: [BoardColumnDef]) {
        guard !columns.isEmpty else { return }
        var changed = page
        changed.columns = columns
        save(changed)
    }

    /// Drop a card into a column: it takes that column and the column's status.
    func move(_ entry: Node, to column: BoardColumnDef) {
        var changed = entry
        changed.columnID = column.id
        changed.status = column.status
        save(changed)
    }

    func setView(_ page: Node, _ view: PageView) {
        var changed = page
        changed.view = view
        save(changed)
    }

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

    func setStatus(_ node: Node, _ status: TaskStatus?) {
        var changed = node
        changed.status = status
        save(changed)
    }

    func toggleDone(_ node: Node) {
        setStatus(node, node.status == .done ? .todo : .done)
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

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            errorMessage = error.localizedDescription
        }
        revision += 1
    }
}
