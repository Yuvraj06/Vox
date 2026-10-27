import Foundation

/// One applied command. Same shape as the `action_log` table in Supabase.
struct ActionLogEntry: Identifiable, Hashable, Sendable {
    var id: UUID
    var userID: UUID?
    var createdAt: Date
    /// What was said (or typed).
    var transcript: String
    /// The actions that were applied, as JSON. Matches the `actions` jsonb column.
    var actionsJSON: String
    /// Steps that put everything back. Matches the `inverse` jsonb column.
    var inverse: [InverseStep]
    /// Short text for the keychain screen, about 21 characters.
    var summary: String
    var undone: Bool

    init(
        id: UUID = UUID(),
        userID: UUID? = nil,
        createdAt: Date = .now,
        transcript: String,
        actionsJSON: String,
        inverse: [InverseStep],
        summary: String,
        undone: Bool = false
    ) {
        self.id = id
        self.userID = userID
        self.createdAt = createdAt
        self.transcript = transcript
        self.actionsJSON = actionsJSON
        self.inverse = inverse
        self.summary = summary
        self.undone = undone
    }
}

/// One step of an undo.
enum InverseStep: Codable, Hashable, Sendable {
    /// The node did not exist before. Undo deletes it.
    case remove(UUID)
    /// The node looked like this before. Undo puts this copy back.
    case restore(Node)
    /// A reminder or alarm made by the command. Undo deletes it. Nodes ignore this step.
    case removeReminder(UUID)
}

extension NodeStore {
    /// Applies undo steps. Removes first, then restores, so a node moved
    /// under a removed node still comes back.
    func apply(_ steps: [InverseStep]) throws {
        for case .remove(let id) in steps {
            try delete(id: id)
        }
        for case .restore(let node) in steps {
            try update(node)
        }
    }
}
