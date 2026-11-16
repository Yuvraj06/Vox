import SwiftUI

/// The Reminders part of an item's settings: its reminders and alarms, plus buttons to add more.
/// The screen holding it shows the editor for `editing`. A popup attached inside a Form row often won't open.
struct ReminderSection: View {
    let node: Node
    @Binding var editing: Reminder?
    @Environment(RemindersModel.self) private var reminders

    var body: some View {
        Section {
            ForEach(reminders.reminders(for: node.id)) { reminder in
                Button { editing = reminder } label: { ReminderRow(reminder: reminder) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            reminders.delete(reminder)
                            Haptics.thud()
                            Haptics.thud()
                        }
                    }
            }
            Button("Add reminder", systemImage: ReminderKind.reminder.icon) { editing = newReminder(.reminder) }
            Button("Add alarm", systemImage: ReminderKind.alarm.icon) { editing = newReminder(.alarm) }
        } header: {
            Text("Reminders and alarms")
        } footer: {
            Text("Alarms ring even when the phone is on silent.")
        }
    }

    /// Starts at the deadline if there is one, otherwise in an hour, on the hour.
    private func newReminder(_ kind: ReminderKind) -> Reminder {
        let inAnHour = Calendar.current.nextDate(after: .now.addingTimeInterval(3600 - 60), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
        let start = node.dueAt.flatMap { $0 > .now ? $0 : nil } ?? inAnHour
        return Reminder(nodeID: node.id, title: node.title, fireAt: start, kind: kind)
    }
}

/// One reminder: icon, time, and how it repeats.
struct ReminderRow: View {
    let reminder: Reminder

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.kind.icon)
                .foregroundStyle(reminder.kind == .alarm ? Color.voxAccent : Color.white.opacity(0.6))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.repeatRule == nil
                    ? reminder.fireAt.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute())
                    : reminder.fireAt.formatted(date: .omitted, time: .shortened))
                if let rule = reminder.repeatRule {
                    Text(rule.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(reminder.kind.label).font(.caption).foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

/// Add or change one reminder or alarm.
struct ReminderEditor: View {
    @State var reminder: Reminder
    @Environment(RemindersModel.self) private var reminders
    @Environment(\.dismiss) private var dismiss

    /// The repeat choices, as a simple picker value.
    private enum Repeat: Hashable { case never, daily, weekly }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $reminder.kind) {
                        ForEach(ReminderKind.allCases, id: \.self) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("Title", text: $reminder.title)
                }
                Section {
                    DatePicker("Time", selection: $reminder.fireAt)
                    Picker("Repeat", selection: repeatChoice) {
                        Text("Never").tag(Repeat.never)
                        Text("Every day").tag(Repeat.daily)
                        Text("Every \(reminder.fireAt.formatted(.dateTime.weekday(.wide)))").tag(Repeat.weekly)
                    }
                }
                if reminders.isSaved(reminder.id) {
                    Section {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            reminders.delete(reminder)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(reminder.kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if case .weekly = reminder.repeatRule { reminder.repeatRule = .weekly(weekday) }
                        reminders.save(reminder)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(reminder.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var weekday: Int { Calendar.current.component(.weekday, from: reminder.fireAt) }

    private var repeatChoice: Binding<Repeat> {
        Binding {
            switch reminder.repeatRule {
            case nil: .never
            case .daily: .daily
            case .weekly: .weekly
            }
        } set: { choice in
            reminder.repeatRule = switch choice {
            case .never: nil
            case .daily: .daily
            case .weekly: .weekly(weekday)
            }
        }
    }
}

/// A month grid. Busy days get a dot. Tap a day to see what's on it.
struct MonthCalendar: View {
    @Binding var month: Date
    @Binding var selectedDay: Date?
    let busyDays: Set<Date>

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button("Previous month", systemImage: "chevron.left") { shift(-1) }
                Button("Next month", systemImage: "chevron.right") { shift(1) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdayLetters.enumerated()), id: \.offset) { _, letter in
                    Text(letter).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 38) }
                }
            }
        }
        .voxCard(radius: 26, padding: 16)
    }

    private func dayCell(_ day: Date) -> some View {
        let isToday = calendar.isDateInToday(day)
        let isSelected = selectedDay.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let isPast = day < calendar.startOfDay(for: .now)
        return Button {
            selectedDay = isSelected ? nil : day
        } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                    .foregroundStyle(isPast ? .secondary : .primary)
                Circle()
                    .fill(Color.voxAccent)
                    .frame(width: 5, height: 5)
                    .opacity(busyDays.contains(calendar.startOfDay(for: day)) ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .background {
                if isSelected {
                    Circle().fill(.white.opacity(0.18))
                } else if isToday {
                    Circle().stroke(Color.voxAccent, lineWidth: 1.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (busyDays.contains(calendar.startOfDay(for: day)) ? ", has plans" : ""))
    }

    /// Blank cells before the 1st so it lands under the right weekday, then every day of the month.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let count = calendar.range(of: .day, in: .month, for: month)?.count else { return [] }
        let offset = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        return Array(repeating: nil, count: offset) + days
    }

    private var weekdayLetters: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func shift(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { month = next }
        selectedDay = nil
    }
}

extension RemindersModel.Entry {
    var title: String {
        switch source {
        case .reminder(let reminder): reminder.title
        case .deadline(let node): node.title
        }
    }

    /// Amber alarm clock for alarms, white bell for reminders, flag for deadlines.
    var icon: String {
        switch source {
        case .reminder(let reminder): reminder.kind.icon
        case .deadline: "flag.fill"
        }
    }

    var tint: Color {
        switch source {
        case .reminder(let reminder): reminder.kind == .alarm ? .voxAccent : .white.opacity(0.55)
        case .deadline: .white.opacity(0.55)
        }
    }

    var isAlarm: Bool {
        if case .reminder(let reminder) = source { reminder.kind == .alarm } else { false }
    }
}

/// A todo from the Reminders list: tick it off, or tap to open it.
struct TodoRow: View {
    let node: Node

    var body: some View {
        HStack(spacing: 10) {
            StatusCheckbox(node: node)
            Text(node.title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .nodeGestures(node)
    }
}

/// The open todos, with a count of any that don't fit.
struct TodoList: View {
    let todos: [Node]
    var limit = Int.max

    var body: some View {
        ForEach(Array(todos.prefix(limit).enumerated()), id: \.element.id) { index, node in
            if index > 0 { Divider().overlay(.white.opacity(0.08)) }
            TodoRow(node: node)
                .transition(.opacity.combined(with: .move(edge: .leading)))
        }
        if todos.count > limit {
            Text("+\(todos.count - limit) more to do")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 6)
        }
    }
}
