import Foundation
import Observation

/// Push to talk: hold to record, release to send, slide up to cancel.
/// The Brain's plan shows as a preview first. Next applies it, Cancel throws it away.
/// Typed commands go through the same path.
@Observable
final class CaptureModel {
    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        /// Worked out, waiting for Next or Cancel.
        case preview(CommandPlan)
        /// Too hard for the fast path. Being worked on in the Thinking tab.
        case queued
        case finished(CommandOutcome)
    }

    private(set) var phase: Phase = .idle
    /// While holding: the finger slid up far enough that letting go cancels.
    var cancelArmed = false
    /// The words sent to the Brain, shown while it thinks.
    private(set) var sentText = ""
    /// Shown when the mic can't start.
    private(set) var micError: String?
    /// The plan's steps so far, while the Brain is still writing it.
    private(set) var liveSteps: [PlanStep] = []
    /// True when the last applied command is getting a second look in the Thinking tab.
    private(set) var doubleChecking = false
    /// The open folder, list or note. Commands only see it and what is inside it. Nil on the home screen.
    var scope: Node?

    let transcriber = LiveTranscriber()
    private let runner: any CommandRunner
    private var startTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    init(runner: any CommandRunner) {
        self.runner = runner
    }

    /// True while the screen behind should blur.
    var isFocused: Bool {
        switch phase {
        case .listening, .thinking, .preview: true
        default: false
        }
    }

    /// The words to show above the button.
    var caption: String { phase == .listening ? transcriber.text : sentText }

    /// Gets the mic and speech model ready early. Problems show up when the button is pressed instead.
    func prepare() async {
        try? await transcriber.prepare()
    }

    // MARK: Push to talk

    func pressBegan() {
        guard phase != .thinking, phase != .listening else { return }
        dismissTask?.cancel()
        // Talking again replaces a preview that wasn't sent.
        if case .preview(let plan) = phase { runner.discard(plan) }
        cancelArmed = false
        micError = nil
        phase = .listening
        startTask = Task {
            do {
                try await transcriber.start()
            } catch {
                micError = error.localizedDescription
                await transcriber.cancel()
                phase = .idle
            }
        }
    }

    func pressEnded() {
        guard phase == .listening else { return }
        let cancel = cancelArmed
        cancelArmed = false
        Task {
            // Let a slow start finish before stopping.
            await startTask?.value
            if cancel {
                await transcriber.cancel()
                phase = .idle
                return
            }
            let text = await transcriber.stop()
            guard !text.isEmpty else {
                phase = .idle
                return
            }
            await send(text)
        }
    }

    // MARK: Commands

    func send(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, phase != .thinking else { return }
        dismissTask?.cancel()
        if case .preview(let plan) = phase { runner.discard(plan) }
        sentText = text
        liveSteps = []
        phase = .thinking
        let outcome = await runner.plan(text, scope: scope?.id) { [weak self] steps in
            self?.liveSteps = steps
        }
        switch outcome {
        case .ready(let plan): phase = .preview(plan)
        case .unclear(let question): finish(.unclear(question: question))
        case .failed(let message): finish(.failed(message: message))
        case .queued:
            phase = .queued
            dismissLater(after: 4)
        }
    }

    /// Next: applies the previewed plan.
    func confirm() {
        guard case .preview(let plan) = phase else { return }
        doubleChecking = plan.needsCheck
        finish(runner.apply(plan))
    }

    /// Cancel: throws the previewed plan away. Nothing changes.
    func cancelPreview() {
        guard case .preview(let plan) = phase else { return }
        runner.discard(plan)
        phase = .idle
    }

    private func finish(_ outcome: CommandOutcome) {
        if case .applied = outcome {} else { doubleChecking = false }
        phase = .finished(outcome)
        // Results tuck away on their own. Questions and errors stay a bit longer.
        let seconds: Double = if case .applied = outcome { 5 } else { 8 }
        dismissLater(after: seconds)
    }

    private func dismissLater(after seconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    func undo(_ logID: UUID) {
        dismissTask?.cancel()
        do {
            try runner.undo(logID)
            phase = .idle
        } catch {
            phase = .finished(.failed(message: "Couldn't undo: \(error.localizedDescription)"))
        }
    }

    func dismiss() {
        switch phase {
        case .finished, .queued: phase = .idle
        default: break
        }
    }
}
