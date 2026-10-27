import SwiftUI

/// Sits over every screen. Blurs the app while you talk, shows live captions above the mic,
/// and shows what happened afterwards.
struct CaptureOverlay: View {
    @Environment(CaptureModel.self) private var capture
    @State private var typing = false
    @State private var draft = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // Blur the app behind, so the captions stand out.
            if capture.isFocused {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay { Color.black.opacity(0.25) }
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack(spacing: 22) {
                message
                scopeLabel
                HStack {
                    // Same width as the keyboard button, so the mic stays centered.
                    Color.clear.frame(width: 56, height: 56)
                    Spacer()
                    MicButton()
                    Spacer()
                    keyboardButton
                }
                .padding(.horizontal, 36)
            }
            .padding(.bottom, 8)
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
            Captions(text: capture.caption, placeholder: "Listening...", hint: capture.cancelArmed ? "Release to cancel" : "Slide up to cancel", warning: capture.cancelArmed)
                .transition(.blurReplace)
        case .thinking:
            VStack(spacing: 18) {
                Captions(text: capture.caption, placeholder: "", hint: "Thinking", warning: false, showsProgress: true)
                if !capture.liveSteps.isEmpty {
                    PreviewCard(steps: capture.liveSteps)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .transition(.blurReplace)
        case .preview(let plan):
            VStack(spacing: 14) {
                Text(plan.transcript)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 28)
                PreviewCard(steps: plan.steps, plan: plan)
            }
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
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, 36)
                .transition(.opacity)
                .accessibilityLabel("Commands only change \(scope.title)")
        }
    }

    private var keyboardButton: some View {
        Button {
            typing = true
        } label: {
            Image(systemName: "keyboard")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .opacity(capture.isFocused ? 0 : 1)
        .disabled(capture.isFocused)
        .accessibilityLabel("Type a command")
    }
}

/// Live words, big and centered, floating over the blurred app.
private struct Captions: View {
    let text: String
    let placeholder: String
    let hint: String
    let warning: Bool
    var showsProgress = false

    var body: some View {
        VStack(spacing: 14) {
            Text(text.isEmpty ? placeholder : text)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
                .multilineTextAlignment(.center)
                .lineLimit(6)
                // Keep the newest words in view when it gets long.
                .truncationMode(.head)
                .contentTransition(.interpolate)
                .animation(.smooth(duration: 0.2), value: text)
            HStack(spacing: 6) {
                if showsProgress { ProgressView().controlSize(.small) }
                Text(hint)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(warning ? Color.red : Color.secondary)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity)
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
            ForEach(steps) { step in
                PlanStepRow(step: step)
                    .transition(.asymmetric(insertion: .push(from: .bottom), removal: .opacity))
            }
            if let source = plan?.source, !source.isEmpty {
                Label(source, systemImage: source == "Gemini" ? "sparkles" : "iphone")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
            if let plan {
                if plan.needsCheck {
                    Label("I'll double check this in Thinking.", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Cancel", role: .cancel) { capture.cancelPreview() }
                        .buttonStyle(.glass)
                    Spacer()
                    Button { capture.confirm() } label: {
                        Label("Next", systemImage: "arrow.right")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(TaskStatus.done.tint.opacity(0.8))
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
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
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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
                Button("Undo") { capture.undo(logID) }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.glass)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
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

/// The round mic. Hold to talk, let go to send, slide up to cancel.
struct MicButton: View {
    @Environment(CaptureModel.self) private var capture
    /// True once the finger has stayed down long enough to record.
    @State private var holding = false
    /// Waits for `holdDelay` after the finger goes down. A quick tap cancels it, so nothing starts.
    @State private var holdTask: Task<Void, Never>?

    private let size: CGFloat = 88
    private let cancelDistance: CGFloat = -80
    /// The mic's darker glass, #3A4450.
    private static let micFill = Color(red: 0.23, green: 0.27, blue: 0.31).opacity(0.7)
    /// How long to hold before recording starts. Shorter taps are ignored.
    private let holdDelay: Duration = .milliseconds(250)

    var body: some View {
        let listening = capture.phase == .listening
        let thinking = capture.phase == .thinking

        ZStack {
            if listening || thinking {
                GlowRing(level: CGFloat(capture.transcriber.level), cancel: capture.cancelArmed, calm: thinking)
                    .frame(width: size, height: size)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Image(systemName: capture.cancelArmed ? "xmark" : "mic.fill")
                .font(.system(size: 32, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .glassEffect(.regular.tint(listening ? Color.voxAmber.opacity(0.35) : Self.micFill), in: .circle)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                .scaleEffect(holding ? 1.12 : 1)
                .opacity(thinking ? 0.6 : 1)
        }
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
}

/// Spinning ring of scenery colors that swells with your voice.
private struct GlowRing: View {
    let level: CGFloat
    let cancel: Bool
    /// Thinking: slower, no voice.
    let calm: Bool

    private var colors: [Color] {
        cancel
            ? [.red, .red.opacity(0.4), .red]
            : [TaskStatus.doing.tint, TaskStatus.todo.tint, TaskStatus.done.tint, TaskStatus.doing.tint]
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let seconds = timeline.date.timeIntervalSinceReferenceDate
            let angle = Angle.degrees(seconds * (calm ? 90 : 160)).degrees.truncatingRemainder(dividingBy: 360)
            let swell = calm ? 0.06 + 0.04 * sin(seconds * 3) : level * 0.35
            let gradient = AngularGradient(colors: colors, center: .center, angle: .degrees(angle))

            ZStack {
                // Soft outer glow.
                Circle()
                    .stroke(gradient, lineWidth: 14)
                    .blur(radius: 14)
                    .opacity(0.9)
                // Crisp ring.
                Circle()
                    .stroke(gradient, lineWidth: 3.5)
            }
            .scaleEffect(1.16 + swell)
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .allowsHitTesting(false)
    }
}
