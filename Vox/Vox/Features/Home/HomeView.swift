import SwiftUI

/// The home screen: a countdown to the next reminder or alarm, Today and Tomorrow,
/// the next few reminders, and every top level note, list, board and folder.
struct HomeView: View {
    @Environment(NotesModel.self) private var notes
    @Environment(RemindersModel.self) private var reminders
    @Environment(\.openNode) private var openNode
    @Environment(SyncEngine.self) private var sync

    @State private var editingReminder: Reminder?
    @State private var prompt: NodePrompt?
    /// Edit mode: note rows get a delete button.
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                HStack(alignment: .top, spacing: 14) {
                    DayBox(title: "Today", entries: today, open: open)
                    DayBox(title: "Tomorrow", entries: tomorrow, open: open)
                }
                allReminders
                allNotes
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        .scrollIndicators(.hidden)
        // Pull down to sync now, when signed in.
        .refreshable { await sync.syncNow() }
        .overScenery()
        .navigationTitle("Vox")
        // Home draws its own header, so the buttons sit next to the title.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingReminder) { ReminderEditor(reminder: $0) }
        .nodePrompt($prompt) { prompt, title in
            switch prompt {
            case .add(let kind): notes.add(kind: kind, title: title, parentID: nil)
            case .addFolder: notes.addFolder(title, parentID: nil)
            default: break
            }
        }
    }

    // MARK: Header

    /// THURSDAY, OCT 29 over a big "Vox", with Edit, Add and Settings on the right.
    /// The countdown to the next reminder sits just under it.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Vox")
                        .font(.system(size: 34, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    editButton
                    addMenu
                    NavigationLink(value: Route.settings) { SettingsIcon() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                }
                // Never squeezed, so "Edit" always fits.
                .fixedSize()
                // Lines the buttons up with "Vox", under the date.
                .padding(.top, 15)
            }
            CountdownPill(open: open)
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }

    /// Its own button, so editing is one tap away. Lit while editing.
    private var editButton: some View {
        Button {
            withAnimation(.snappy) { editing.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: editing ? "checkmark" : "pencil")
                    .contentTransition(.symbolEffect(.replace))
                Text(editing ? "Done" : "Edit")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(editing ? Color.voxInk : .white)
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background {
                if editing { Capsule().fill(Color.voxAccent) }
            }
            .voxGlass(in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(editing ? "Done editing" : "Edit notes")
    }

    private var addMenu: some View {
        Menu {
            Button("Reminder", systemImage: ReminderKind.reminder.icon) { editingReminder = newReminder(.reminder) }
            Button("Alarm", systemImage: ReminderKind.alarm.icon) { editingReminder = newReminder(.alarm) }
            Divider()
            Button("Item", systemImage: "circle") { prompt = .add(.item) }
            Button("Note", systemImage: "note.text") { prompt = .add(.note) }
            Button("Folder", systemImage: "folder") { prompt = .addFolder }
        } label: {
            GlassCircleIcon(systemName: "plus")
        }
        // Menus tint their label with the accent color. Keep it white like the other buttons.
        .tint(.white)
        .accessibilityLabel("Add")
    }

    // MARK: Days

    /// All of today, including what already passed. The box starts scrolled to what is next.
    private var today: [RemindersModel.Entry] {
        reminders.entries(on: .now)
    }

    private var tomorrow: [RemindersModel.Entry] {
        reminders.entries(on: Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now)
    }

    // MARK: All Reminders

    private var allReminders: some View {
        let upcoming = reminders.upcoming()
        let todos = notes.reminderTodos()
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: Route.allReminders) {
                CardHeader(title: "Reminders", count: upcoming.count + todos.count)
            }
            .buttonStyle(.plain)
            if upcoming.isEmpty && todos.isEmpty {
                Text("Say \"remind me…\" or tap + to add one.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            ForEach(Array(upcoming.prefix(6).enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(.white.opacity(0.08)) }
                Button { open(entry) } label: { DatedRow(entry: entry) }
                    .buttonStyle(.plain)
            }
            if !todos.isEmpty {
                Text("TO DO")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.top, upcoming.isEmpty ? 8 : 14)
                    .padding(.bottom, 2)
                TodoList(todos: todos, limit: 3)
            }
        }
        .animation(.snappy, value: todos.map(\.id))
        .voxCard()
    }

    // MARK: All Notes

    private var allNotes: some View {
        let kids = notes.children(of: nil)
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: Route.allNotes) {
                CardHeader(title: "Notes", count: kids.count)
            }
            .buttonStyle(.plain)
            if kids.isEmpty {
                Text("Nothing yet. Tap + or just say what to make.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            ForEach(Array(kids.enumerated()), id: \.element.id) { index, node in
                if index > 0 { Divider().overlay(.white.opacity(0.08)) }
                HStack(spacing: 10) {
                    if editing {
                        Button("Delete \(node.title)", systemImage: "minus.circle.fill", role: .destructive) {
                            withAnimation { notes.delete([node.id]) }
                        }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.red)
                        .transition(.scale.combined(with: .opacity))
                    }
                    HomeNoteRow(node: node).nodeGestures(node)
                }
            }
        }
        .voxCard()
    }

    // MARK: Actions

    /// Opens the linked item, or the editor for a reminder that stands alone.
    private func open(_ entry: RemindersModel.Entry) {
        switch entry.source {
        case .deadline(let node):
            openNode(node)
        case .reminder(let reminder):
            if let node = reminder.nodeID.flatMap(reminders.node(id:)) { openNode(node) } else { editingReminder = reminder }
        }
    }

    /// In an hour, on the hour.
    private func newReminder(_ kind: ReminderKind) -> Reminder {
        let start = Calendar.current.nextDate(after: .now.addingTimeInterval(3600 - 60), matching: DateComponents(minute: 0), matchingPolicy: .nextTime) ?? .now
        return Reminder(title: "", fireAt: start, kind: kind)
    }
}

// MARK: Countdown

/// A small live timer to the next reminder or alarm, with a short bar for how much of the wait has passed.
/// Hidden when nothing is coming up.
private struct CountdownPill: View {
    let open: (RemindersModel.Entry) -> Void
    @Environment(RemindersModel.self) private var reminders

    var body: some View {
        // Finds the next one every 30 seconds. Only the clock below ticks every second.
        TimelineView(.periodic(from: .now, by: 30)) { slow in
            if let next = reminders.nextTimed(after: slow.date) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    pill(next, now: context.date)
                }
                .transition(.blurReplace)
            }
        }
    }

    private func pill(_ next: (entry: RemindersModel.Entry, since: Date), now: Date) -> some View {
        let clock = Self.clock(next.entry.date.timeIntervalSince(now))
        return Button { open(next.entry) } label: {
            HStack(spacing: 6) {
                Image(systemName: next.entry.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.voxAccent)
                Text(clock)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                Text(next.entry.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                ProgressBar(value: progress(next, now: now))
                    .frame(width: 24)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .voxGlass(in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.3), value: now)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label(next.entry)), \(next.entry.title), in \(clock)")
    }

    private func label(_ entry: RemindersModel.Entry) -> String {
        if case .deadline = entry.source { return "Deadline" }
        return entry.isAlarm ? "Next alarm" : "Next reminder"
    }

    private func progress(_ next: (entry: RemindersModel.Entry, since: Date), now: Date) -> Double {
        let total = next.entry.date.timeIntervalSince(next.since)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(next.since) / total, 0), 1)
    }

    /// 29:42 under an hour, 5:29:42 under a day, then 2d 4h.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        let hours = total / 3600, minutes = total / 60 % 60, secs = total % 60
        if hours >= 24 { return "\(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%02d:%02d", minutes, secs)
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(Color.voxAccent).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 3)
        .accessibilityValue("\(Int(value * 100)) percent of the wait has passed")
    }
}

/// The gear, with a small glowing dot while Thinking is checking something or waits for a choice.
private struct SettingsIcon: View {
    @Environment(ThinkingQueue.self) private var queue

    var body: some View {
        GlassCircleIcon(systemName: "gearshape")
            .overlay(alignment: .topTrailing) {
                if busy {
                    Circle()
                        .fill(Color.voxAccent)
                        .frame(width: 10, height: 10)
                        .overlay { Circle().stroke(Color.voxInk, lineWidth: 1.5) }
                        .shadow(color: .voxAccent.opacity(0.8), radius: 4)
                        .offset(x: -1, y: 1)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.snappy, value: busy)
            .accessibilityValue(busy ? "Thinking is busy" : "")
    }

    private var busy: Bool { queue.activeCount > 0 || queue.waitingCount > 0 }
}

// MARK: Today and Tomorrow

/// One day's reminders, alarms and deadlines in a box of fixed height.
/// Every one is in there: the box scrolls, and fades at an edge when more is hidden past it.
private struct DayBox: View {
    let title: String
    let entries: [RemindersModel.Entry]
    let open: (RemindersModel.Entry) -> Void

    /// Which edges have rows hidden past them.
    @State private var hidden = HiddenEdges()
    @State private var position = ScrollPosition(idType: String.self)

    private static let height: CGFloat = 164

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if entries.isEmpty {
                Text("Nothing planned").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                rows
            }
        }
        .frame(height: Self.height, alignment: .top)
        .voxCard(radius: 22, padding: 12)
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(entries) { entry in
                    Button { open(entry) } label: { DayRow(entry: entry) }
                        .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 8)
        }
        .scrollPosition($position, anchor: .top)
        // Shows the scroll bar for a moment, so it is clear the box scrolls.
        .scrollIndicatorsFlash(onAppear: true)
        .scrollIndicatorsFlash(trigger: entries.count)
        .onScrollGeometryChange(for: HiddenEdges.self) { geo in
            HiddenEdges(
                top: geo.contentOffset.y > 1,
                bottom: geo.contentOffset.y + geo.containerSize.height < geo.contentSize.height - 1
            )
        } action: { _, edges in
            withAnimation(.easeOut(duration: 0.2)) { hidden = edges }
        }
        .mask { fade }
        .overlay(alignment: .bottom) {
            if hidden.bottom {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        // Start at what is next. The ones that already passed sit just above.
        .onAppear {
            if let next = entries.first(where: { $0.date >= .now }), next.id != entries.first?.id {
                position.scrollTo(id: next.id, anchor: .top)
            }
        }
    }

    /// Soft edges where rows are hidden.
    private var fade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: hidden.top ? 16 : 0)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: hidden.bottom ? 30 : 0)
        }
    }

    private struct HiddenEdges: Equatable {
        var top = false
        var bottom = false
    }
}

/// One line: icon, title, time. Ones that already passed are dimmed.
private struct DayRow: View {
    let entry: RemindersModel.Entry

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: entry.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(entry.tint)
                .frame(width: 12)
            Text(entry.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 4)
            // "9:30 p" instead of "9:30 PM", so the title gets the room.
            Text(entry.date, format: .dateTime.hour(.defaultDigits(amPM: .narrow)).minute())
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .opacity(entry.date < .now ? 0.4 : 1)
        .contentShape(.rect)
    }
}

// MARK: Rows

/// "All Reminders" 12 >
private struct CardHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Text("\(count)").font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.5))
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
        }
        .padding(.bottom, 6)
        .contentShape(.rect)
    }
}

/// A reminder with a date chip: month over the day number.
struct DatedRow: View {
    let entry: RemindersModel.Entry

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(entry.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.system(size: 18, weight: .semibold).monospacedDigit())
            }
            .frame(width: 44, height: 44)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 16, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    /// "7:00 AM · Alarm · Weekdays", "Due 10:00 AM".
    private var detail: String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        if case .deadline = entry.source { return "Due \(time)" }
        var parts = [time]
        if entry.isAlarm { parts.append("Alarm") }
        if case .reminder(let reminder) = entry.source, let rule = reminder.repeatRule { parts.append(rule.label) }
        return parts.joined(separator: " · ")
    }
}

/// A top level note, list, board or folder, with a tinted rounded icon.
private struct HomeNoteRow: View {
    let node: Node
    @Environment(NotesModel.self) private var notes

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: node.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(node.isFolder ? 0.18 : 0.1), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.25))
        }
        .padding(.vertical, 10)
    }

    /// Folders keep the color you picked. Everything else stays white, so color means something.
    private var tint: Color {
        if node.isFolder { return node.color.flatMap(Color.init(hex:)) ?? .voxFolder }
        return .white.opacity(0.85)
    }

    private var subtitle: String {
        if node.kind == .note { return node.body?.split(separator: "\n").first.map(String.init) ?? "Note" }
        if node.isBoard {
            let cards = notes.cardCount(of: node)
            return "Board · \(cards == 1 ? "1 task" : "\(cards) tasks")"
        }
        let count = notes.children(of: node.id).count
        return count == 1 ? "1 item" : "\(count) items"
    }
}
