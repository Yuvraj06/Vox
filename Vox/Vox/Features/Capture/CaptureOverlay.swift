import SwiftUI

/// Sits over every screen. Dims the app while you talk, shows live captions above the mic,
/// and shows what happened afterwards.
struct CaptureOverlay: View {
    @Environment(CaptureModel.self) private var capture
    @State private var typing = false
    @State private var draft = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // Dim the app behind, darkest at the bottom where the cards are.
            if capture.isFocused {
                LinearGradient(
                    colors: [.black.opacity(0.35), .black.opacity(0.55), .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }

            VStack(spacing: 18) {
                message
                scopeLabel
                VStack(spacing: 10) {
                    HStack {
                        // Same width as the keyboard button, so the mic stays centered.
                        Color.clear.frame(width: 48, height: 48)
                        Spacer()
                        MicButton()
                        Spacer()
                        keyboardButton
                    }
                    .padding(.horizontal, 40)
                    hint
                }
            }
            .padding(.bottom, 4)
        }
        .animation(.smooth(duration: 0.35), value: capture.phase)
        .animation(.smooth(duration: 0.25), value: capture.cancelArmed)
        .task { await capture.prepare() }
        .alert("Type a command", isPresented: $typing) {
            TextField("Add Dune to movies I watched", text: $draft)
            Button("Send") {
                let text = draft
                draft = ""
                Task { await capture.send(text) }
            }
            Button("Cancel", role: .cancel) { draft = "" }
        }
    }

    // MARK: Above the button

    @ViewBuilder
    private var message: some View {
        switch capture.phase {
        case .listening:
            CaptionCard(thinking: false)
                .transition(.blurReplace)
        case .thinking:
            VStack(spacing: 14) {
                CaptionCard(thinking: true)
                if !capture.liveSteps.isEmpty {
                    PreviewCard(steps: capture.liveSteps)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .transition(.blurReplace)
        case .preview(let plan):
            PreviewCard(steps: plan.steps, plan: plan)
                .transition(.blurReplace)
        case .queued:
            NoticeCard(
                icon: "brain.fill",
                tint: TaskStatus.doing.tint,
                text: "This one needs more thought. Tap the brain at the top right to follow along."
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        case .finished(let outcome):
            ResultCard(outcome: outcome)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        case .idle:
            if let error = capture.micError {
                ResultCard(outcome: .failed(message: error))
                    .transition(.opacity)
            }
        }
    }

    /// Which screen the mic is talking about, like "In Orbit". Hidden on the home screen and while busy.
    @ViewBuilder
    private var scopeLabel: some View {
        if let scope = capture.scope, capture.phase == .idle, capture.micError == nil {
            Label("In \(scope.title)", systemImage: scope.kind == .note ? "doc.text" : "scope")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .voxGlass(in: .capsule)
                .padding(.horizontal, 36)
                .transition(.opacity)
                .accessibilityLabel("Commands only change \(scope.title)")
        }
    }

    /// Small words under the mic: what holding does, or how to cancel.
    @ViewBuilder
    private var hint: some View {
        let text: String? = switch capture.phase {
        case .idle: "Hold to talk"
        case .listening: capture.cancelArmed ? "Let go to cancel" : "Slide up to cancel"
        default: nil
        }
        Text(text ?? " ")
            .font(.caption.weight(.medium))
            .foregroundStyle(capture.cancelArmed ? Color.red : Color.white.opacity(0.6))
            .opacity(text == nil ? 0 : 1)
            .contentTransition(.opacity)
            .accessibilityHidden(true)
    }

    private var keyboardButton: some View {
        Button {
            typing = true
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 48, height: 48)
                .voxGlass(in: .circle, interactive: true)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .opacity(capture.isFocused ? 0 : 1)
        .disabled(capture.isFocused)
        .accessibilityLabel("Type a command")
    }
}

/// Live words in a glass card. Settled words are white, words still being worked out are faded.
/// While listening it shows a timer and a waveform of your voice.
private struct CaptionCard: View {
    let thinking: Bool
    @Environment(CaptureModel.self) private var capture
    @State private var started = Date.now
    /// Recent mic levels, oldest first, for the waveform.
    @State private var levels = [CGFloat](repeating: 0, count: 28)

    private static let listeningRed = Color(red: 1, green: 0.42, blue: 0.4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if thinking {
                    ProgressView().controlSize(.mini).tint(Color.voxAmber)
                } else {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                }
                Text(status)
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(statusColor)
                Spacer()
                if !thinking {
                    TimelineView(.periodic(from: started, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(started)), format: .time(pattern: .minuteSecond))
                    }
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            words
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(6)
                // Keep the newest words in view when it gets long.
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth(duration: 0.2), value: capture.caption)
            if !thinking {
                Waveform(levels: levels)
            }
        }
        .voxCard(radius: 28, padding: 20)
        .padding(.horizontal, 16)
        .onChange(of: capture.transcriber.level) { _, level in
            levels.removeFirst()
            levels.append(CGFloat(level))
        }
    }

    @ViewBuilder
    private var words: some View {
        let transcriber = capture.transcriber
        if thinking {
            Text(capture.sentText)
        } else if transcriber.text.isEmpty {
            Text("Listening...").foregroundStyle(.white.opacity(0.4))
        } else {
            Text("\(Text(transcriber.finalText))\(Text(transcriber.partialText).foregroundStyle(.white.opacity(0.4)))")
        }
    }

    private var status: String {
        if thinking { return "THINKING" }
        return capture.cancelArmed ? "LET GO TO CANCEL" : "LISTENING"
    }

    private var statusColor: Color {
        if thinking { return .voxAmber }
        return capture.cancelArmed ? .red : Self.listeningRed
    }
}

/// Amber bars of recent mic levels, newest on the right.
private struct Waveform: View {
    let levels: [CGFloat]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.voxAmber.opacity(0.35 + 0.65 * Double(index) / Double(levels.count)))
                    .frame(width: 4, height: 4 + min(levels[index] * 1.6, 1) * 30)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 34)
        .animation(.easeOut(duration: 0.1), value: levels)
        .accessibilityHidden(true)
    }
}

/// What a command will do, as trails of chips. With a plan it gets Next and Cancel;
/// without one it is the live view while the Brain is still writing.
private struct PreviewCard: View {
    let steps: [PlanStep]
    var plan: CommandPlan?
    @Environment(CaptureModel.self) private var capture

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let plan {
                HStack(spacing: 6) {
                    Image(systemName: plan.source == "Gemini" ? "sparkles" : "iphone")
                    Text(plan.source.isEmpty ? "Plan" : plan.source)
                    Spacer()
                    Text(steps.count == 1 ? "1 step" : "\(steps.count) steps")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.voxAmber)
                Text("\u{201C}\(plan.transcript)\u{201D}")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(3)
            }
            ForEach(steps) { step in
                PlanStepRow(step: step)
                    .transition(.asymmetric(insertion: .push(from: .bottom), removal: .opacity))
            }
            if let plan {
                if plan.needsCheck {
                    Label("I'll double check this in Thinking.", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button { capture.cancelPreview() } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .voxGlass(in: .rect(cornerRadius: 16), interactive: true)
                            .contentShape(.rect(cornerRadius: 16))
                    }
                    Button { capture.confirm() } label: {
                        HStack(spacing: 6) {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .foregroundStyle(Color(red: 0.12, green: 0.1, blue: 0.08))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Color.voxAmber, in: .rect(cornerRadius: 16))
                        .shadow(color: Color.voxAmber.opacity(0.4), radius: 8, y: 4)
                    }
                }
                .font(.system(size: 15, weight: .semibold))
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .voxCard(radius: 28, padding: 20)
        .padding(.horizontal, 16)
        .animation(.smooth(duration: 0.25), value: steps)
        .sensoryFeedback(.selection, trigger: steps.count)
    }
}

/// A short message with an icon, like when a command moved to the Thinking tab.
private struct NoticeCard: View {
    let icon: String
    let tint: Color
    let text: String
    @Environment(CaptureModel.self) private var capture

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(text)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .voxCard(radius: 22, padding: 16)
        .padding(.horizontal, 16)
        .onTapGesture { capture.dismiss() }
    }
}

/// What the Brain did, or what it needs to know.
private struct ResultCard: View {
    let outcome: CommandOutcome
    @Environment(CaptureModel.self) private var capture

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { line in
                    Text(line).font(.subheadline)
                }
                if case .applied = outcome, capture.doubleChecking {
                    Label("Double checking in Thinking", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if case .applied(_, _, let logID) = outcome {
                Button {
                    capture.undo(logID)
                    Haptics.success()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .voxCard(radius: 22, padding: 16)
        .padding(.horizontal, 16)
        .onTapGesture { capture.dismiss() }
    }

    private var lines: [String] {
        switch outcome {
        case .applied(_, let lines, _): lines
        case .unclear(let question): [question]
        case .failed(let message): [message]
        }
    }

    private var icon: String {
        switch outcome {
        case .applied: "checkmark.circle.fill"
        case .unclear: "questionmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch outcome {
        case .applied: TaskStatus.done.tint
        case .unclear: TaskStatus.todo.tint
        case .failed: TaskStatus.doing.tint
        }
    }
}

/// The round amber mic. Hold to talk, let go to send, slide up to cancel.
struct MicButton: View {
    @Environment(CaptureModel.self) private var capture
    /// True once the finger has stayed down long enough to record.
    @State private var holding = false
    /// Waits for `holdDelay` after the finger goes down. A quick tap cancels it, so nothing starts.
    @State private var holdTask: Task<Void, Never>?

    private let size: CGFloat = 72
    private let cancelDistance: CGFloat = -80
    /// How long to hold before recording starts. Shorter taps are ignored.
    private let holdDelay: Duration = .milliseconds(250)
    /// Dark brown, so the icon reads on amber.
    private static let ink = Color(red: 0.12, green: 0.1, blue: 0.08)

    var body: some View {
        let listening = capture.phase == .listening
        let thinking = capture.phase == .thinking

        ZStack {
            // Soft amber light around the button.
            Circle()
                .fill(RadialGradient(
                    colors: [fillTop.opacity(listening ? 0.7 : 0.5), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.85
                ))
                .frame(width: size * 1.7, height: size * 1.7)
                .allowsHitTesting(false)
            if listening || thinking {
                PulseRings(level: CGFloat(capture.transcriber.level), color: capture.cancelArmed ? .red : .voxAmber, calm: thinking)
                    .frame(width: size, height: size)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Image(systemName: capture.cancelArmed ? "xmark" : "mic.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Self.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(LinearGradient(colors: [fillTop, fillBottom], startPoint: .top, endPoint: .bottom))
                )
                .shadow(color: fillBottom.opacity(0.5), radius: 12, y: 6)
                .scaleEffect(holding ? 1.28 : 1)
                .opacity(thinking ? 0.6 : 1)
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.3, bounce: 0.4), value: holding)
        .contentShape(.circle)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if holdTask == nil {
                        holdTask = Task {
                            try? await Task.sleep(for: holdDelay)
                            guard !Task.isCancelled else { return }
                            holding = true
                            capture.pressBegan()
                        }
                    }
                    if holding { capture.cancelArmed = drag.translation.height < cancelDistance }
                }
                .onEnded { _ in
                    holdTask?.cancel()
                    holdTask = nil
                    // A quick tap never started recording, so there is nothing to stop.
                    guard holding else { return }
                    holding = false
                    capture.pressEnded()
                }
        )
        .allowsHitTesting(!thinking)
        .sensoryFeedback(.impact(weight: .medium), trigger: holding) { _, new in new }
        .sensoryFeedback(.warning, trigger: capture.cancelArmed) { _, new in new }
        .accessibilityLabel("Hold to talk")
    }

    private var fillTop: Color {
        capture.cancelArmed ? Color(red: 1, green: 0.5, blue: 0.48) : Color(red: 1, green: 0.78, blue: 0.42)
    }

    private var fillBottom: Color {
        capture.cancelArmed ? Color(red: 0.86, green: 0.25, blue: 0.24) : Color(red: 0.93, green: 0.58, blue: 0.2)
    }
}

/// Two thin rings around the mic that swell with your voice.
private struct PulseRings: View {
    let level: CGFloat
    let color: Color
    /// Thinking: a slow breath, no voice.
    let calm: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let swell = calm ? 0.05 * sin(seconds * 3) : min(level * 1.6, 1) * 0.3

            ZStack {
                Circle()
                    .stroke(color.opacity(0.35), lineWidth: 2)
                    .scaleEffect(1.55 + swell)
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 2)
                    .scaleEffect(1.95 + swell * 1.4)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .allowsHitTesting(false)
    }
}
