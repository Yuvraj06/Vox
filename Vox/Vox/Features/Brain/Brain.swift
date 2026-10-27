import Foundation
import FoundationModels

/// Turns a command into actions, applies them, and writes the action log.
///
/// - Gemini (when the user added a key) and the on-device fast path start together.
///   Gemini sees an outline of every title, so it is the most accurate.
/// - If Gemini answers within 3 seconds, its plan is shown. If not, the on-device plan is shown,
///   and Gemini's answer checks it in Thinking when it arrives.
/// - Without Gemini, complex on-device plans are checked by the full on-device Brain with tools.
final class Brain: CommandRunner {
    typealias GeminiTask = Task<[BrainAction], Error>

    /// How long Gemini gets before the on-device plan is shown instead.
    static let geminiWindow: Duration = .seconds(3)

    private let nodes: any NodeStore
    private let log: any ActionLogStore
    private let gemini: GeminiSettings?
    /// Where voice reminders and alarms are saved.
    private let reminders: (any ReminderStore)?
    /// Called after nodes change, so screens can redraw.
    private let onChange: () -> Void
    /// Called with reminders a command made, and ids an undo removed, so they go on or off the clock.
    private let onReminders: (_ added: [Reminder], _ removed: [UUID]) -> Void
    let thinking = ThinkingQueue()

    /// Planned but not applied yet, by plan id.
    private var pending: [UUID: Pending] = [:]
    /// A fast session made and warmed up ahead of time, so the next command starts right away.
    private var readySession: LanguageModelSession?

    private struct Pending {
        var actions: [BrainAction]
        var context: BrainContext
        /// Gemini, still working when the on-device plan was shown. Its answer checks this plan.
        var gemini: GeminiTask?
    }

    /// Who checks a plan in Thinking.
    private enum Checker {
        /// The full on-device Brain with tools.
        case apple
        /// A Gemini answer that is on its way. Its ids belong to `context`.
        case gemini(GeminiTask, context: BrainContext)
    }

    init(
        nodes: any NodeStore,
        log: any ActionLogStore,
        gemini: GeminiSettings? = nil,
        reminders: (any ReminderStore)? = nil,
        onChange: @escaping () -> Void = {},
        onReminders: @escaping (_ added: [Reminder], _ removed: [UUID]) -> Void = { _, _ in }
    ) {
        self.nodes = nodes
        self.log = log
        self.gemini = gemini
        self.reminders = reminders
        self.onChange = onChange
        self.onReminders = onReminders
        thinking.brain = self
    }

    /// Loads the model early so the first command is faster.
    func prewarm() {
        guard SystemLanguageModel.default.isAvailable else { return }
        let session = LanguageModelSession(instructions: BrainInstructions.fast)
        session.prewarm()
        readySession = session
    }

    // MARK: Planning

    func plan(_ text: String, scope: UUID?, progress: @escaping ([PlanStep]) -> Void) async -> PlanOutcome {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failed(message: "I didn't hear anything.") }

        let context = makeContext(scope: scope)
        let geminiTask = startGemini(text, context: context)
        let appleProblem = Self.unavailableMessage()
        if geminiTask == nil, let appleProblem { return .failed(message: appleProblem) }
        // On device starts right away too, so its plan is ready if Gemini is slow.
        let apple: Task<FastResult, Never>? = appleProblem == nil
            ? Task { await self.fastPlan(text, context: context, progress: progress) }
            : nil

        // Gemini still working after its window. Its answer will check the on-device plan.
        var lateGemini: GeminiTask?
        if let geminiTask {
            let window = apple == nil ? Duration.seconds(30) : Self.geminiWindow
            switch await Self.first(geminiTask, within: window) {
            case .success(let actions)?:
                if let outcome = outcome(for: actions, text: text, context: context, source: "Gemini", gemini: nil, needsCheck: { _ in false }) {
                    apple?.cancel()
                    return outcome
                }
            case .failure(let error)?:
                Self.debugLog("gemini failed: \(error)")
                if apple == nil { return .failed(message: error.localizedDescription) }
            case nil:
                Self.debugLog("gemini slower than \(window), showing the on-device plan")
                lateGemini = geminiTask
            }
        }
        guard let apple else { return .failed(message: "I couldn't work that out. Try saying it another way.") }

        switch await apple.value {
        case .actions(let actions):
            let outcome = outcome(for: actions, text: text, context: context, source: "On device", gemini: lateGemini) { result in
                lateGemini != nil || actions.count > 2 || result.guessedRef || result.maybeDuplicate
            }
            return outcome ?? queue(text, scope: scope, checker: lateGemini.map { .gemini($0, context: context) } ?? .apple)
        case .refused(let message):
            return .failed(message: message)
        case .failed:
            return queue(text, scope: scope, checker: lateGemini.map { .gemini($0, context: context) } ?? .apple)
        }
    }

    /// Turns a model's actions into a plan to preview. Nil when they can't be used as they are.
    private func outcome(
        for actions: [BrainAction],
        text: String,
        context: BrainContext,
        source: String,
        gemini: GeminiTask?,
        needsCheck: (PlanPreview.Result) -> Bool
    ) -> PlanOutcome? {
        let actions = PlanRepair.all(actions, command: text, context: context)
        if let unclear = actions.first(where: { $0.type == .unclear }) {
            // If Gemini is still working, let it try instead of asking.
            return gemini == nil ? .unclear(question: unclear.question ?? "Sorry, what should I do?") : nil
        }
        guard !actions.isEmpty else { return nil }
        do {
            let result = try PlanPreview(context: context).steps(for: actions)
            let plan = CommandPlan(transcript: text, steps: result.steps, needsCheck: needsCheck(result), source: source)
            pending[plan.id] = Pending(actions: actions, context: context, gemini: gemini)
            return .ready(plan)
        } catch .unsupported(let message) {
            return .failed(message: message)
        } catch {
            // A ref points at nothing. A careful look can search for it.
            return nil
        }
    }

    private func startGemini(_ text: String, context: BrainContext) -> GeminiTask? {
        guard let client = gemini?.client else { return nil }
        let outline = context.outline()
        let here = context.hereLine()
        return Task {
            let start = ContinuousClock.now
            defer { Self.debugLog("gemini answered in \(ContinuousClock.now - start)") }
            return try await client.plan(command: text, outline: outline, here: here)
        }
    }

    // MARK: On-device fast path

    private enum FastResult {
        case actions([BrainAction])
        /// The model won't do it. Retrying elsewhere won't help.
        case refused(String)
        case failed
    }

    /// Swift searches the notes, then one short model call with no tools. Streams steps as they come.
    private func fastPlan(_ text: String, context: BrainContext, progress: @escaping ([PlanStep]) -> Void) async -> FastResult {
        let preview = PlanPreview(context: context)
        let found = context.candidates(for: text)
        let matches = found.map(context.describe)
        let others = context.topLists(excluding: found).map(context.describe)
        let here = context.hereLine()
        let session = readySession ?? LanguageModelSession(instructions: BrainInstructions.fast)
        readySession = nil
        defer {
            Self.debugPrint(session, label: "fast")
            prewarm()
        }

        let start = ContinuousClock.now
        do {
            let stream = session.streamResponse(
                to: BrainInstructions.fastPrompt(command: text, matches: matches, others: others, here: here),
                generating: BrainPlan.self,
                options: GenerationOptions(samplingMode: .greedy)
            )
            var last: GeneratedContent?
            for try await snapshot in stream {
                try Task.checkCancellation()
                last = snapshot.rawContent
                let partial = (snapshot.content.actions ?? []).compactMap(BrainAction.init(partial:))
                progress(preview.partialSteps(for: partial))
            }
            guard let last else { return .failed }
            Self.debugLog("fast plan in \(ContinuousClock.now - start)")
            return .actions(try BrainPlan(last).actions)
        } catch let error as LanguageModelError {
            Self.debugLog("fast model error: \(error)")
            switch error {
            case .guardrailViolation, .refusal, .unsupportedLanguageOrLocale: return .refused(Self.message(for: error))
            default: return .failed
            }
        } catch {
            Self.debugLog("fast error: \(error)")
            return .failed
        }
    }

    // MARK: Applying

    func apply(_ plan: CommandPlan) -> CommandOutcome {
        guard let planned = pending.removeValue(forKey: plan.id) else {
            return .failed(message: "That plan expired. Try the command again.")
        }
        do {
            let (entry, result) = try commit(planned.actions, context: planned.context, transcript: plan.transcript)
            onChange()
            if plan.needsCheck {
                // Hide what this command made, so the second look sees the notes as they were before.
                let made = Set(result.inverse.compactMap { step in
                    if case .remove(let id) = step { id } else { nil }
                })
                let job = ThinkingJob(transcript: plan.transcript, fastSteps: plan.steps, appliedLogID: entry.id)
                let checker: Checker = planned.gemini.map { .gemini($0, context: planned.context) } ?? .apple
                startThinking(job, scope: planned.context.scope, checker: checker, hidden: made)
            }
            return .applied(summary: result.summary, lines: result.lines, logID: entry.id)
        } catch ActionExecutor.Failure.unclear(let question) {
            return .unclear(question: question)
        } catch {
            onChange()
            return .failed(message: error.localizedDescription)
        }
    }

    func discard(_ plan: CommandPlan) {
        pending.removeValue(forKey: plan.id)?.gemini?.cancel()
    }

    func undo(_ logID: UUID) throws {
        guard let entry = try log.entry(id: logID), !entry.undone else { return }
        try nodes.apply(entry.inverse)
        let removed = entry.inverse.compactMap { step in
            if case .removeReminder(let id) = step { id } else { nil }
        }
        for id in removed { try reminders?.delete(id: id) }
        try log.markUndone(id: logID)
        if !removed.isEmpty { onReminders([], removed) }
        onChange()
    }

    // MARK: Careful path (Thinking tab)

    /// The fast path couldn't do it. Hands the command to Thinking.
    private func queue(_ text: String, scope: UUID?, checker: Checker) -> PlanOutcome {
        startThinking(ThinkingJob(transcript: text), scope: scope, checker: checker, hidden: [])
        return .queued
    }

    private func startThinking(_ job: ThinkingJob, scope: UUID?, checker: Checker, hidden: Set<UUID>) {
        thinking.add(job)
        Task { await think(job, scope: scope, checker: checker, hidden: hidden) }
    }

    /// Gets a careful plan (from Gemini, or the full on-device Brain), then compares it with what was applied.
    /// `scope` is the screen that was open when the command was said.
    private func think(_ job: ThinkingJob, scope: UUID?, checker: Checker, hidden: Set<UUID>) async {
        let context: BrainContext
        do {
            let actions: [BrainAction]
            switch checker {
            case .gemini(let task, let planContext):
                context = planContext
                context.hidden = hidden
                job.note("Waiting for Gemini")
                actions = try await task.value
                job.note("Gemini answered")
            case .apple:
                context = makeContext(scope: scope)
                context.hidden = hidden
                context.onStep = { [weak job] line in job?.note(line) }
                job.note(job.fastSteps.isEmpty ? "Working it out" : "Double checking")
                let session = LanguageModelSession(
                    tools: [FindNodesTool(context: context), ListChildrenTool(context: context), CurrentDateTool(context: context)],
                    instructions: BrainInstructions.text
                )
                defer { Self.debugPrint(session, label: "careful") }
                actions = try await session.respond(
                    to: BrainInstructions.carefulPrompt(command: job.transcript, here: context.hereLine()),
                    generating: BrainPlan.self,
                    options: GenerationOptions(samplingMode: .greedy)
                ).content.actions
            }
            try judge(job, actions: PlanRepair.all(actions, command: job.transcript, context: context), context: context)
        } catch PlanPreview.Problem.unsupported(let message) {
            job.state = .failed(message)
        } catch is PlanPreview.Problem {
            job.state = .failed(job.fastSteps.isEmpty
                ? "I couldn't work that out. Try saying it another way."
                : "I couldn't double check this one. What was applied stays.")
        } catch let error as LanguageModelError {
            Self.debugLog("careful model error: \(error)")
            job.state = .failed(Self.message(for: error))
        } catch let error as URLError {
            job.state = .failed("Couldn't reach Gemini: \(error.localizedDescription)")
        } catch {
            job.state = .failed(error.localizedDescription)
        }
    }

    /// Sets the job's verdict: agrees, a better idea, or a plan ready to apply.
    private func judge(_ job: ThinkingJob, actions: [BrainAction], context: BrainContext) throws {
        if let unclear = actions.first(where: { $0.type == .unclear }) {
            job.state = .unclear(unclear.question ?? "Sorry, what should I do?")
            return
        }
        let steps = try PlanPreview(context: context).steps(for: actions).steps
        guard !steps.isEmpty else { throw PlanPreview.Problem.unknownRef("") }
        if job.fastSteps.isEmpty {
            job.suggestion = (actions, context)
            job.note("Plan ready")
            job.state = .ready(steps)
        } else if Self.same(steps, job.fastSteps) {
            job.note("Looks right")
            job.state = .agrees
        } else {
            job.suggestion = (actions, context)
            job.note("Found a better way")
            job.state = .suggests(steps)
        }
    }

    /// Applies the careful plan. If the fast plan was applied, it is undone first.
    func accept(_ job: ThinkingJob) {
        guard let suggestion = job.suggestion else { return }
        job.discardSuggestion()
        let replacing = job.appliedLogID != nil
        do {
            if let logID = job.appliedLogID {
                try undo(logID)
                job.appliedLogID = nil
            }
            let (entry, result) = try commit(suggestion.actions, context: suggestion.context, transcript: job.transcript)
            job.appliedLogID = entry.id
            job.state = .applied(result.lines)
        } catch {
            let message = error.localizedDescription
            job.state = .failed(replacing ? "Undid the first try, but the fix failed: \(message)" : message)
        }
        onChange()
    }

    // MARK: Helpers

    private func makeContext(scope: UUID?) -> BrainContext {
        let context = BrainContext(store: nodes, scope: scope)
        context.reminders = reminders
        return context
    }

    /// Applies actions and writes the action log entry.
    private func commit(
        _ actions: [BrainAction],
        context: BrainContext,
        transcript: String
    ) throws -> (ActionLogEntry, ActionExecutor.Result) {
        let result = try ActionExecutor(context: context).apply(actions)
        if !result.reminders.isEmpty { onReminders(result.reminders, []) }
        let entry = ActionLogEntry(
            transcript: transcript,
            actionsJSON: Self.json(actions),
            inverse: result.inverse,
            summary: result.summary
        )
        try log.append(entry)
        return (entry, result)
    }

    /// Gemini's answer if it comes within `limit`, or nil. Gemini keeps working either way.
    private static func first(_ task: GeminiTask, within limit: Duration) async -> Result<[BrainAction], Error>? {
        let race = Race()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { race.finish(await task.result) }
            Task {
                try? await Task.sleep(for: limit)
                race.finish(nil)
            }
        }
    }

    /// Resumes once, with whichever side finishes first.
    private final class Race {
        var continuation: CheckedContinuation<Result<[BrainAction], Error>?, Never>?

        func finish(_ value: Result<[BrainAction], Error>?) {
            continuation?.resume(returning: value)
            continuation = nil
        }
    }

    private static func same(_ a: [PlanStep], _ b: [PlanStep]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.sameChange(as: $1) }
    }

    private static func unavailableMessage() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings to use commands."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading. Try again in a bit."
        case .unavailable(.deviceNotEligible): "This device can't run Apple Intelligence."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    private static func message(for error: LanguageModelError) -> String {
        switch error {
        case .contextSizeExceeded: "That was too long for me. Try a shorter command."
        case .guardrailViolation, .refusal: "I can't help with that one."
        case .unsupportedLanguageOrLocale: "I only understand English for now."
        case .rateLimited, .timeout: "I'm busy. Try again in a moment."
        default: "I couldn't work that out. Try saying it another way."
        }
    }

    private static func debugLog(_ line: String) {
        #if DEBUG
        print("[Brain]", line)
        #endif
    }

    /// Prints what the model did (tool calls, results, answer) to the Xcode console in debug builds.
    private static func debugPrint(_ session: LanguageModelSession, label: String) {
        #if DEBUG
        print("[Brain] \(label) transcript:")
        for entry in session.transcript {
            print("[Brain]", entry)
        }
        #endif
    }

    private static func json(_ actions: [BrainAction]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(actions)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }
}
