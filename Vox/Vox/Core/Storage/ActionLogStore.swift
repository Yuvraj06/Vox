import Foundation

/// The only way features read and write the action log.
protocol ActionLogStore {
    func append(_ entry: ActionLogEntry) throws
    func entry(id: UUID) throws -> ActionLogEntry?
    /// Newest first.
    func recent(limit: Int) throws -> [ActionLogEntry]
    func markUndone(id: UUID) throws
    /// Rows made while signed out have no owner. Signing in gives them to that user.
    func claimUnowned(by userID: UUID) throws
}
