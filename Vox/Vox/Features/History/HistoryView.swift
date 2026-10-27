import SwiftUI

/// Everything you said, grouped by day, newest first. Undo works on any of them.
struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(CaptureModel.self) private var capture
    /// Counts undos, for the haptic.
    @State private var undos = 0

    var body: some View {
        List {
            ForEach(days, id: \.day) { group in
                Section {
                    ForEach(group.entries) { entry in
                        HistoryRow(entry: entry) {
                            history.undo(entry)
                            if history.errorMessage == nil { undos += 1 }
                        }
                        .glassRow()
                    }
                } header: {
                    Text(title(for: group.day))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .listStyle(.plain)
        .overScenery()
        .navigationTitle("History")
        .overlay {
            if history.entries.isEmpty {
                ContentUnavailableView(
                    "No commands yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Everything you say shows up here, and any of it can be undone.")
                )
                .padding(24)
                .voxGlass(in: .rect(cornerRadius: 28))
                .padding(32)
            }
        }
        .onAppear { history.reload() }
        // A command or an undo from the mic changes the log too.
        .onChange(of: capture.phase) { history.reload() }
        .sensoryFeedback(.success, trigger: undos)
        .alert(
            "Can't undo yet",
            isPresented: Binding(get: { history.errorMessage != nil }, set: { if !$0 { history.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(history.errorMessage ?? "")
        }
    }

    /// Entries are newest first, so each day's list stays newest first too.
    private var days: [(day: Date, entries: [ActionLogEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.entries) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}

/// What was said, what it did, when, and Undo.
private struct HistoryRow: View {
    let entry: ActionLogEntry
    let undo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\u{201C}\(entry.transcript)\u{201D}")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(entry.undone ? .secondary : .primary)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(entry.summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(entry.undone ? Color.secondary : Color.voxAmber)
                        .strikethrough(entry.undone)
                        .lineLimit(1)
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if entry.undone {
                Text("Undone")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                Button(action: undo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.white.opacity(0.14), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo \(entry.transcript)")
            }
        }
    }
}
