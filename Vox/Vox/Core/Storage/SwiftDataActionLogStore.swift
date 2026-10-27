import Foundation
import SwiftData

/// SwiftData row for an action log entry. Only this file knows it exists.
@Model
final class ActionLogEntity {
    @Attribute(.unique) var id: UUID
    var userID: UUID?
    var createdAt: Date
    var transcript: String
    var actionsJSON: String
    /// JSON array of inverse steps. Matches the `inverse` jsonb column.
    var inverseJSON: String
    var summary: String
    var undone: Bool

    init(_ entry: ActionLogEntry) {
        id = entry.id
        userID = entry.userID
        createdAt = entry.createdAt
        transcript = entry.transcript
        actionsJSON = entry.actionsJSON
        inverseJSON = (try? JSONEncoder().encode(entry.inverse)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        summary = entry.summary
        undone = entry.undone
    }

    var value: ActionLogEntry {
        ActionLogEntry(
            id: id,
            userID: userID,
            createdAt: createdAt,
            transcript: transcript,
            actionsJSON: actionsJSON,
            inverse: (try? JSONDecoder().decode([InverseStep].self, from: Data(inverseJSON.utf8))) ?? [],
            summary: summary,
            undone: undone
        )
    }
}

final class SwiftDataActionLogStore: ActionLogStore {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    func append(_ entry: ActionLogEntry) throws {
        context.insert(ActionLogEntity(entry))
        try context.save()
    }

    func entry(id: UUID) throws -> ActionLogEntry? {
        try entity(id: id)?.value
    }

    func recent(limit: Int) throws -> [ActionLogEntry] {
        var descriptor = FetchDescriptor<ActionLogEntity>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(\.value)
    }

    func markUndone(id: UUID) throws {
        guard let entity = try entity(id: id) else { return }
        entity.undone = true
        try context.save()
    }

    private func entity(id: UUID) throws -> ActionLogEntity? {
        var descriptor = FetchDescriptor<ActionLogEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
