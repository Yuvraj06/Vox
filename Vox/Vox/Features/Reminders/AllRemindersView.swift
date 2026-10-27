import SwiftUI

/// Every upcoming reminder, alarm and deadline, with the month calendar on top.
/// Tap a day on the calendar to see just that day.
struct AllRemindersView: View {
    @Environment(RemindersModel.self) private var reminders
    @Environment(\.openNode) private var openNode
    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selectedDay: Date?
    @State private var editing: Reminder?

    var body: some View {
        let entries = selectedDay.map { reminders.entries(on: $0) } ?? reminders.upcoming()

        ScrollView {
            VStack(spacing: 14) {
                MonthCalendar(month: $month, selectedDay: $selectedDay, busyDays: reminders.busyDays(in: monthInterval))
                VStack(alignment: .leading, spacing: 0) {
                    Text(selectedDay.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide)) } ?? "Coming up")
                        .font(.headline)
                        .padding(.bottom, 6)
                    if entries.isEmpty {
                        Text("Nothing planned").font(.subheadline).foregroundStyle(.secondary).padding(.top, 6)
                    }
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { Divider().overlay(.white.opacity(0.08)) }
                        Button { open(entry) } label: { DatedRow(entry: entry) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if case .reminder(let reminder) = entry.source {
                                    Button("Edit", systemImage: "pencil") { editing = reminder }
                                    Button("Delete", systemImage: "trash", role: .destructive) { reminders.delete(reminder) }
                                }
                            }
                    }
                }
                .voxCard()
            }
            .padding(.horizontal, 16)
            .animation(.smooth, value: selectedDay)
        }
        .scrollIndicators(.hidden)
        .overScenery()
        .navigationTitle("All Reminders")
        .sheet(item: $editing) { ReminderEditor(reminder: $0) }
    }

    private var monthInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 31 * 86_400)
    }

    private func open(_ entry: RemindersModel.Entry) {
        switch entry.source {
        case .deadline(let node): openNode(node)
        case .reminder(let reminder):
            if let node = reminder.nodeID.flatMap(reminders.node(id:)) { openNode(node) } else { editing = reminder }
        }
    }
}
