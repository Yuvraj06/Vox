import Foundation

/// How Capture (or the keychain) hands a command to the Brain.
/// A command is planned first and shown as a preview. Nothing changes until it is applied.
protocol CommandRunner {
    /// Works out what a command would do, without changing anything.
    /// `scope` is the open folder, list or note. Only it and what is inside it are sent to the Brain. Nil means everything.
    /// `progress` gets the steps found so far while the model is still writing.
    func plan(_ text: String, scope: UUID?, progress: @escaping ([PlanStep]) -> Void) async -> PlanOutcome
    /// Applies a plan from `plan`. Plans with `needsCheck` get a second look in Thinking afterwards.
    func apply(_ plan: CommandPlan) -> CommandOutcome
    /// Forgets a plan that was cancelled.
    func discard(_ plan: CommandPlan)
    /// Puts back everything one applied command changed.
    func undo(_ logID: UUID) throws
}

/// A command that is worked out but not applied yet.
struct CommandPlan: Identifiable, Equatable {
    var id = UUID()
    var transcript: String
    var steps: [PlanStep]
    /// True when the plan is complex or unsure. It gets a second look in the Thinking tab after it is applied.
    var needsCheck: Bool
    /// Who worked it out, like "Gemini" or "On device". Shown small on the preview.
    var source = ""
}

/// One change in a plan, shown as a trail like Todo -> Movies -> Dune.
struct PlanStep: Hashable, Identifiable {
    enum Verb: String, Hashable {
        case add, create, change, move, rename, delete

        var symbol: String {
            switch self {
            case .add: "plus"
            case .create: "sparkles"
            case .change: "pencil"
            case .move: "arrow.turn.down.right"
            case .rename: "character.cursor.ibeam"
            case .delete: "trash"
            }
        }
    }

    var id: Int
    var verb: Verb
    /// Titles from the top level down to where the change happens. Empty means the top level.
    var path: [String]
    /// The item being added or changed.
    var title: String
    /// Extra words, like "board", "Done" or "rating 4".
    var note: String?

    /// Same change, ignoring ids and letter case. Used to see if two plans agree.
    func sameChange(as other: PlanStep) -> Bool {
        verb == other.verb
            && path.map { $0.lowercased() } == other.path.map { $0.lowercased() }
            && title.lowercased() == other.title.lowercased()
    }
}

enum PlanOutcome: Equatable {
    case ready(CommandPlan)
    /// Nothing planned. The Brain needs more information.
    case unclear(question: String)
    /// The fast path couldn't do it. It is being worked on in Thinking.
    case queued
    /// Nothing planned. Something went wrong.
    case failed(message: String)
}

enum CommandOutcome: Equatable {
    /// Changes were made. `lines` is for the screen, `summary` for the keychain.
    case applied(summary: String, lines: [String], logID: UUID)
    /// Nothing changed. The Brain needs more information.
    case unclear(question: String)
    /// Nothing changed. Something went wrong.
    case failed(message: String)
}
