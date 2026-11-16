import SwiftUI

/// Thinking: commands getting a careful second look, with every step shown live.
/// Opens as a sheet from Settings. Settings (Gemini key) are behind the gear.
struct ThinkingView: View {
    @Environment(ThinkingQueue.self) private var queue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(queue.jobs) { job in
                        JobCard(job: job)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(16)
                .animation(.smooth(duration: 0.3), value: queue.jobs.map(\.id))
            }
            .overlay {
                if queue.jobs.isEmpty {
                    ContentUnavailableView(
                        "Nothing to think about",
                        systemImage: "brain",
                        description: Text("Complex commands get a second look here.")
                    )
                }
            }
            .navigationTitle("Thinking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                if queue.jobs.contains(where: { !$0.state.isOpen }) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Clear") { queue.clearFinished() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        GeminiSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }
}

/// The brain. Pulses while something is being checked, with a count of how many wait for a choice.
struct ThinkingIcon: View {
    @Environment(ThinkingQueue.self) private var queue

    var body: some View {
        Image(systemName: "brain")
            .symbolEffect(.pulse, isActive: queue.activeCount > 0)
            .overlay(alignment: .topTrailing) {
                if queue.waitingCount > 0 {
                    Text("\(queue.waitingCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Color.voxAccent, in: .circle)
                        .offset(x: 9, y: -8)
                }
            }
    }
}

/// One command: what was said, the live steps, and the verdict.
private struct JobCard: View {
    let job: ThinkingJob
    @Environment(ThinkingQueue.self) private var queue

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            stepLog
            if !job.fastSteps.isEmpty {
                section("Applied", steps: job.fastSteps, dimmed: isSuggesting)
            }
            verdict
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .voxGlass(in: .rect(cornerRadius: 24))
        .animation(.smooth(duration: 0.25), value: job.state)
        .animation(.smooth(duration: 0.25), value: job.log)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) { queue.remove(job) }
        }
    }

    private var isSuggesting: Bool {
        if case .suggests = job.state { true } else { false }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\u{201C}\(job.transcript)\u{201D}")
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            badge
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch job.state {
        case .working:
            ProgressView().controlSize(.small)
        case .agrees:
            Badge(text: "Looks right", icon: "checkmark", tint: .voxAccent)
        case .suggests:
            Badge(text: "Better idea", icon: "lightbulb.fill", tint: .voxAccent)
        case .ready:
            Badge(text: "Ready", icon: "sparkles", tint: .voxAccent)
        case .applied:
            Badge(text: "Done", icon: "checkmark", tint: .white.opacity(0.7))
        case .kept:
            Badge(text: "Kept", icon: "hand.thumbsup", tint: .white.opacity(0.7))
        case .unclear:
            Badge(text: "Unsure", icon: "questionmark", tint: .white.opacity(0.7))
        case .failed:
            Badge(text: "Stuck", icon: "exclamationmark.triangle", tint: .voxError)
        }
    }

    /// Each tool call as it happens. The newest line pulses while working.
    private var stepLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(job.log.enumerated()), id: \.offset) { index, line in
                let isLast = index == job.log.count - 1
                HStack(spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(isLast && job.state == .working ? Color.voxAccent : Color.secondary.opacity(0.5))
                        .symbolEffect(.pulse, isActive: isLast && job.state == .working)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(isLast ? .primary : .secondary)
                }
                .transition(.push(from: .bottom))
            }
        }
    }

    @ViewBuilder
    private var verdict: some View {
        switch job.state {
        case .suggests(let steps):
            section("Suggested", steps: steps, dimmed: false)
            HStack {
                Button("Keep mine") { queue.keep(job) }
                    .buttonStyle(.glass)
                Spacer()
                Button("Use this") { queue.accept(job) }
                    .fontWeight(.semibold)
                    .buttonStyle(.glassProminent)
                    .tint(.voxAccent)
                    .foregroundStyle(Color.voxInk)
            }
        case .ready(let steps):
            section("Plan", steps: steps, dimmed: false)
            HStack {
                Button("Dismiss") { queue.remove(job) }
                    .buttonStyle(.glass)
                Spacer()
                Button("Apply") { queue.accept(job) }
                    .fontWeight(.semibold)
                    .buttonStyle(.glassProminent)
                    .tint(.voxAccent)
                    .foregroundStyle(Color.voxInk)
            }
        case .applied(let lines):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(lines, id: \.self) { Text($0).font(.subheadline) }
            }
        case .unclear(let message), .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .working, .agrees, .kept:
            EmptyView()
        }
    }

    private func section(_ title: String, steps: [PlanStep], dimmed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(steps) { PlanStepRow(step: $0) }
        }
        .opacity(dimmed ? 0.55 : 1)
    }
}

private struct Badge: View {
    let text: String
    let icon: String
    let tint: Color

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.16), in: .capsule)
    }
}
