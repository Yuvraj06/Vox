import Foundation
import SwiftData

/// Rows on their way to or from Supabase, deleted ones included.
struct SyncBatch: Equatable {
    var nodes: [Node] = []
    var reminders: [Reminder] = []
    var log: [ActionLogEntry] = []

    var isEmpty: Bool { nodes.isEmpty && reminders.isEmpty && log.isEmpty }
}

/// What sync needs from the local data. Only Sync uses it.
protocol SyncStore {
    /// Everything changed on this phone since it was last uploaded.
    func unpushed() throws -> SyncBatch
    /// These were uploaded. Their marks clear, unless a row changed again meanwhile.
    func markPushed(_ batch: SyncBatch) throws
    /// Rows from Supabase. The newer `updatedAt` wins. A newer change on this phone that isn't
    /// uploaded yet stays. History entries only ever gain "undone". Returns true if anything changed.
    @discardableResult
    func merge(_ batch: SyncBatch) throws -> Bool
}

final class SwiftDataSyncStore: SyncStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    func unpushed() throws -> SyncBatch {
        SyncBatch(
            nodes: try context.fetch(FetchDescriptor<NodeEntity>(predicate: #Predicate { $0.needsPush })).map(\.value),
            reminders: try context.fetch(FetchDescriptor<ReminderEntity>(predicate: #Predicate { $0.needsPush })).map(\.value),
            log: try context.fetch(FetchDescriptor<ActionLogEntity>(predicate: #Predicate { $0.needsPush })).map(\.value)
        )
    }

    func markPushed(_ batch: SyncBatch) throws {
        for node in batch.nodes {
            if let row = try nodeEntity(node.id), row.updatedAt == node.updatedAt { row.needsPush = false }
        }
        for reminder in batch.reminders {
            if let row = try reminderEntity(reminder.id), row.updatedAt == reminder.updatedAt { row.needsPush = false }
        }
        for entry in batch.log {
            if let row = try logEntity(entry.id), row.undone == entry.undone { row.needsPush = false }
        }
        try context.save()
    }

    @discardableResult
    func merge(_ batch: SyncBatch) throws -> Bool {
        var changed = false
        for node in batch.nodes {
            if let row = try nodeEntity(node.id) {
                guard Self.remoteWins(remote: node.updatedAt, local: row.updatedAt) else { continue }
                row.apply(node)
                row.needsPush = false
            } else {
                let row = NodeEntity(node)
                row.needsPush = false
                context.insert(row)
            }
            changed = true
        }
        for reminder in batch.reminders {
            if let row = try reminderEntity(reminder.id) {
                guard Self.remoteWins(remote: reminder.updatedAt, local: row.updatedAt) else { continue }
                row.copy(from: reminder)
                row.needsPush = false
            } else {
                let row = ReminderEntity(reminder)
                row.needsPush = false
                context.insert(row)
            }
            changed = true
        }
        for entry in batch.log {
            if let row = try logEntity(entry.id) {
                // Undo can't be taken back, so undone on either side means undone.
                guard entry.undone, !row.undone else { continue }
                row.undone = true
            } else {
                let row = ActionLogEntity(entry)
                row.needsPush = false
                context.insert(row)
            }
            changed = true
        }
        if changed { try context.save() }
        return changed
    }

    /// Last write wins. Same time means it is our own upload coming back, so nothing to do.
    /// An older copy never replaces a newer one, uploaded or not.
    static func remoteWins(remote: Date, local: Date) -> Bool {
        remote > local
    }

    private func nodeEntity(_ id: UUID) throws -> NodeEntity? {
        var descriptor = FetchDescriptor<NodeEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func reminderEntity(_ id: UUID) throws -> ReminderEntity? {
        var descriptor = FetchDescriptor<ReminderEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func logEntity(_ id: UUID) throws -> ActionLogEntity? {
        var descriptor = FetchDescriptor<ActionLogEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
