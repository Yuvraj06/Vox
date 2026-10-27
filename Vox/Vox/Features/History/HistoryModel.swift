import Foundation
import Observation

/// Every applied command, newest first, with undo for any of them.
/// An older command waits while a newer one still depends on what it changed.
@Observable
final class HistoryModel {
    /// How many commands the screen shows.
    static let limit = 300

    private(set) var entries: [ActionLogEntry] = []
    var errorMessage: String?

    private let log: any ActionLogStore
    /// Ids of a node's parent, grandparent and so on, up to the top.
    private let ancestors: (UUID) -> [UUID]
    private let undoCommand: (UUID) throws -> Void

    init(log: any ActionLogStore, ancestors: @escaping (UUID) -> [UUID], undo: @escaping (UUID) throws -> Void) {
        self.log = log
        self.ancestors = ancestors
        self.undoCommand = undo
    }

    func reload() {
        entries = (try? log.recent(limit: Self.limit)) ?? []
    }

    /// The newest command that still depends on this one, so it must be undone first. Nil when this one is free.
    /// Depends means it changed the same things, or something inside them, like an item added to a list this one made.
    func blocker(for entry: ActionLogEntry) -> ActionLogEntry? {
        let mine = entry.touchedIDs
        return entries
            .filter { !$0.undone && $0.createdAt > entry.createdAt }
            .filter { !reach(of: $0).isDisjoint(with: mine) }
            .max { $0.createdAt < $1.createdAt }
    }

    func undo(_ entry: ActionLogEntry) {
        guard !entry.undone else { return }
        if let blocker = blocker(for: entry) {
            errorMessage = "Undo \u{201C}\(blocker.transcript)\u{201D} first. It changed the same things."
            return
        }
        do {
            try undoCommand(entry.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        reload()
    }

    /// What a command changed, plus everything those things sit inside.
    private func reach(of entry: ActionLogEntry) -> Set<UUID> {
        let ids = entry.touchedIDs
        return ids.union(ids.flatMap(ancestors))
    }
}
