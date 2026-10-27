import Foundation
import SwiftData

/// SwiftData row for a reminder. Only this file knows it exists.
@Model
final class ReminderEntity {
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var nodeID: UUID?
    var title: String
    var fireAt: Date
    /// `reminder` or `alarm`.
    var kind: String
    /// `daily`, `weekly:mon`, or nil for once.
    var repeatRule: String?
    var done: Bool
    var updatedAt: Date
    var deleted: Bool

    init(_ reminder: Reminder) {
        id = reminder.id
        userID = reminder.userID
        nodeID = reminder.nodeID
        title = reminder.title
        fireAt = reminder.fireAt
        kind = reminder.kind.rawValue
        repeatRule = reminder.repeatRule?.text
        done = reminder.done
        updatedAt = reminder.updatedAt
        deleted = reminder.deleted
    }

    func copy(from reminder: Reminder) {
        userID = reminder.userID
        nodeID = reminder.nodeID
        title = reminder.title
        fireAt = reminder.fireAt
        kind = reminder.kind.rawValue
        repeatRule = reminder.repeatRule?.text
        done = reminder.done
        updatedAt = reminder.updatedAt
        deleted = reminder.deleted
    }

    var value: Reminder {
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

final class SwiftDataReminderStore: ReminderStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    /// Throwaway, for tests and previews.
    static func inMemory() throws -> SwiftDataReminderStore {
        SwiftDataReminderStore(container: try LocalDatabase.inMemory())
    }

    func reminder(id: UUID) throws -> Reminder? {
        try entity(id: id).flatMap { $0.deleted ? nil : $0.value }
    }

    func all() throws -> [Reminder] {
        let descriptor = FetchDescriptor<ReminderEntity>(
            predicate: #Predicate { !$0.deleted },
            sortBy: [SortDescriptor(\.fireAt)]
        )
        return try context.fetch(descriptor).map(\.value)
    }

    func save(_ reminder: Reminder) throws {
        var reminder = reminder
        reminder.updatedAt = .now
        if let existing = try entity(id: reminder.id) {
            existing.copy(from: reminder)
        } else {
            context.insert(ReminderEntity(reminder))
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        guard let entity = try entity(id: id) else { return }
        entity.deleted = true
        entity.updatedAt = .now
        try context.save()
    }

    private func entity(id: UUID) throws -> ReminderEntity? {
        var descriptor = FetchDescriptor<ReminderEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
