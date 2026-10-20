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

    // MARK: Writes

    func add(kind: NodeKind, title: String, parentID: UUID?) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        perform { _ = try store.create(kind: kind, title: title, parentID: parentID) }
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

    func setStatus(_ node: Node, _ status: TaskStatus) {
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
