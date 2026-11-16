import Foundation
import Testing
@testable import Vox

/// Answers commands from a script, and remembers what it was sent.
@MainActor
final class ScriptedRunner: CommandRunner {
    var outcomes: [PlanOutcome]
    var applyOutcome: CommandOutcome = .applied(summary: "", lines: ["Done"], logID: UUID())
    private(set) var sent: [String] = []

    init(_ outcomes: [PlanOutcome]) {
        self.outcomes = outcomes
    }

    func plan(_ text: String, scope: UUID?, progress: @escaping ([PlanStep]) -> Void) async -> PlanOutcome {
        sent.append(text)
        return outcomes.isEmpty ? .failed(message: "No script left") : outcomes.removeFirst()
    }

    func apply(_ plan: CommandPlan) -> CommandOutcome { applyOutcome }
    func discard(_ plan: CommandPlan) {}
    func undo(_ logID: UUID) throws {}
}

/// A command that fails or is unclear waits for an answer instead of going away.
@MainActor
struct ClarifyTests {
    private let plan = CommandPlan(transcript: "x", steps: [], needsCheck: false, source: "Test")

    @Test func unclearWaitsAndTheAnswerGoesWithTheCommand() async {
        let runner = ScriptedRunner([.unclear(question: "Which list?"), .ready(plan)])
        let capture = CaptureModel(runner: runner)

        await capture.send("add dune")
        #expect(capture.phase == .clarify(.init(command: "add dune", prompt: "Which list?", isQuestion: true)))
        // No timeout: dismissing does nothing to it.
        capture.dismiss()
        #expect(capture.clarifying != nil)

        await capture.send("movies I watched")
        #expect(runner.sent.last == "add dune. Which list? movies I watched")
        #expect(capture.phase == .preview(plan))
        #expect(capture.clarifying == nil)
    }

    @Test func failureAsksAgainAndKeepsEverythingSaid() async {
        let runner = ScriptedRunner([.failed(message: "I couldn't understand the time."), .failed(message: "Still no.")])
        let capture = CaptureModel(runner: runner)

        await capture.send("remind me to call mom at blah")
        await capture.send("tomorrow 6pm")
        #expect(runner.sent.last == "remind me to call mom at blah. tomorrow 6pm")
        #expect(capture.clarifying?.command == "remind me to call mom at blah. tomorrow 6pm")
        #expect(capture.clarifying?.prompt == "Still no.")
    }

    @Test func failedApplyAsksAgain() async {
        let runner = ScriptedRunner([.ready(plan)])
        runner.applyOutcome = .failed(message: "That plan expired.")
        let capture = CaptureModel(runner: runner)
        await capture.send("add dune")
        capture.confirm()
        #expect(capture.clarifying == .init(command: "x", prompt: "That plan expired.", isQuestion: false))
    }

    @Test func cancelDropsIt() async {
        let capture = CaptureModel(runner: ScriptedRunner([.unclear(question: "Which?")]))
        await capture.send("add dune")
        capture.cancelClarify()
        #expect(capture.phase == .idle && capture.clarifying == nil)
    }

    @Test func backgroundQuestionWaitsForABusyScreen() async {
        let capture = CaptureModel(runner: ScriptedRunner([.ready(plan)]))
        await capture.send("add dune")
        capture.askAgain(.init(command: "make orbit", prompt: "Which sections?", isQuestion: true))
        #expect(capture.phase == .preview(plan))
        capture.cancelPreview()
        #expect(capture.clarifying?.command == "make orbit")
    }
}
