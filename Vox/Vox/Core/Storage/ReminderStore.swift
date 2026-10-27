import Foundation

/// The only way features read and write reminders and alarms.
/// Reads never return soft-deleted ones.
protocol ReminderStore {
    func reminder(id: UUID) throws -> Reminder?
    /// Every reminder, soonest first.
    func all() throws -> [Reminder]
    /// Saves all fields and bumps `updatedAt`. Inserts it if it is new.
    func save(_ reminder: Reminder) throws
    /// Soft deletes it.
    func delete(id: UUID) throws
}

extension ReminderStore {
    /// The ones linked to a node, soonest first.
    func reminders(for nodeID: UUID) throws -> [Reminder] {
        try all().filter { $0.nodeID == nodeID }
    }
}
