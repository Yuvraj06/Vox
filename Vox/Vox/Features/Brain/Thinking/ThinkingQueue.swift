import Foundation
import Observation

/// Commands that get a slower, careful look, by Gemini or the full on-device Brain.
/// Shown in Thinking, newest first.
@Observable
final class ThinkingQueue {
    private(set) var jobs: [ThinkingJob] = []
    /// Does the actual work. Weak, because the Brain owns this queue.
    weak var brain: Brain?

    /// Jobs still working, so the brain button can pulse.
    var activeCount: Int { jobs.filter { $0.state == .working }.count }

    /// Jobs waiting for the user to choose, for the count on the brain button.
    var waitingCount: Int {
        jobs.filter { job in
            switch job.state {
            case .suggests, .ready: true
            default: false
            }
        }.count
    }

    func add(_ job: ThinkingJob) {
        jobs.insert(job, at: 0)
    }

    /// Swaps the applied fast plan for the careful one, or applies the careful one if nothing was applied yet.
    func accept(_ job: ThinkingJob) {
        brain?.accept(job)
    }

    /// Keeps what was applied and ignores the suggestion.
    func keep(_ job: ThinkingJob) {
        job.state = .kept
        job.discardSuggestion()
    }

    func remove(_ job: ThinkingJob) {
        job.discardSuggestion()
        jobs.removeAll { $0.id == job.id }
    }

    /// Removes everything that is not working or waiting for a choice.
    func clearFinished() {
        jobs.removeAll { !$0.state.isOpen }
    }
}

/// One command in the Thinking tab.
@Observable
final class ThinkingJob: Identifiable {
    enum State: Equatable {
        case working
        /// The careful look agrees with what was applied.
        case agrees
        /// The careful look would do this instead of what was applied.
        case suggests([PlanStep])
        /// Nothing was applied yet. This is the careful plan, waiting for Apply.
        case ready([PlanStep])
        /// The suggestion or plan was applied. Lines say what happened.
        case applied([String])
        /// The user kept the fast version.
        case kept
        case unclear(String)
        case failed(String)

        /// Still working, or waiting for the user to choose.
        var isOpen: Bool {
            switch self {
            case .working, .suggests, .ready: true
            default: false
            }
        }
    }

    let id = UUID()
    let transcript: String
    let createdAt = Date.now
    /// What the fast path applied, if anything.
    let fastSteps: [PlanStep]
    /// Log entry of what is applied right now for this command. Undone when a suggestion is accepted.
    var appliedLogID: UUID?
    /// Live lines, like: Searching "movies watched".
    private(set) var log: [String] = []
    var state: State = .working
    /// The careful plan's actions, kept by the Brain until the user chooses.
    @ObservationIgnored var suggestion: (actions: [BrainAction], context: BrainContext)?

    init(transcript: String, fastSteps: [PlanStep] = [], appliedLogID: UUID? = nil) {
        self.transcript = transcript
        self.fastSteps = fastSteps
        self.appliedLogID = appliedLogID
    }

    func note(_ line: String) {
        log.append(line)
    }

    func discardSuggestion() {
        suggestion = nil
    }
}
