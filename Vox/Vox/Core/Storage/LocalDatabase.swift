import SwiftData

/// The one SwiftData container. Every local store shares it.
enum LocalDatabase {
    static let models: [any PersistentModel.Type] = [NodeEntity.self, ActionLogEntity.self, ReminderEntity.self]

    /// On disk, for the real app.
    static func persistent() throws -> ModelContainer {
        try ModelContainer(for: Schema(models))
    }

    /// Throwaway, for tests and previews.
    static func inMemory() throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
