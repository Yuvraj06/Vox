import SwiftUI

/// The home screen: a countdown to the next reminder or alarm, Today and Tomorrow,
/// the next few reminders, and every top level note, list, board and folder.
struct HomeView: View {
    @Environment(NotesModel.self) private var notes
    @Environment(RemindersModel.self) private var reminders
    @Environment(\.openNode) private var openNode

    @State private var editingReminder: Reminder?
    @State private var prompt: NodePrompt?
    /// Edit mode: note rows get a delete button.
    @State private var editing = false
    @State private var showingThinking = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                CountdownCard(open: open)
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
        .overScenery()
        .navigationTitle("Vox")
        // Home draws its own header, so the buttons sit next to the title.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editingReminder) { ReminderEditor(reminder: $0) }
        .sheet(isPresented: $showingThinking) { ThinkingView() }
        .nodePrompt($prompt) { prompt, title in
            switch prompt {
            case .add(let kind): notes.add(kind: kind, title: title, parentID: nil)
            case .addFolder: notes.addFolder(title, parentID: nil)
            default: break
            }
        }
    }

    // MARK: Header

    /// TUESDAY, OCT 27 over a big "Vox", with Thinking and Add on the right.
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.55))
                Text("Vox")
                    .font(.system(size: 34, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            NavigationLink(value: Route.history) { GlassCircleIcon(systemName: "clock.arrow.circlepath") }
                .buttonStyle(.plain)
                .accessibilityLabel("History")
            Button { showingThinking = true } label: {
                ThinkingIcon()
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .voxGlass(in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Thinking")
            Menu {
                Button("Reminder", systemImage: ReminderKind.reminder.icon) { editingReminder = newReminder(.reminder) }
                Button("Alarm", systemImage: ReminderKind.alarm.icon) { editingReminder = newReminder(.alarm) }
                Divider()
                Button("Item", systemImage: "circle") { prompt = .add(.item) }
                Button("Note", systemImage: "note.text") { prompt = .add(.note) }
                Button("Folder", systemImage: "folder") { prompt = .addFolder }
                Divider()
                Button(editing ? "Done editing" : "Edit notes", systemImage: editing ? "checkmark" : "pencil") {
                    withAnimation(.snappy) { editing.toggle() }
                }
            } label: {
                GlassCircleIcon(systemName: "plus")
            }
            // Menus tint their label with the accent color. Keep it white like the brain.
            .tint(.white)
            .accessibilityLabel("Add")
        }
        .padding(.horizontal, 4)
        .padding(.top, 2)
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
        return VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: Route.allReminders) {
                CardHeader(title: "Reminders", count: upcoming.count)
            }
            .buttonStyle(.plain)
            if upcoming.isEmpty {
                Text("Say \"remind me…\" or tap + to add one.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
            ForEach(Array(upcoming.prefix(4).enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider().overlay(.white.opacity(0.08)) }
                Button { open(entry) } label: { DatedRow(entry: entry) }
                    .buttonStyle(.plain)
            }
        }
        .voxCard()
    }

    // MARK: All Notes

    private var allNotes: some View {
        let kids = notes.children(of: nil)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                NavigationLink(value: Route.allNotes) {
                    CardHeader(title: "Notes", count: kids.count)
                }
                .buttonStyle(.plain)
                if editing {
                    Button("Done") { withAnimation(.snappy) { editing = false } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.voxAmber)
                        .transition(.opacity)
                }
            }
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

/// Big live timer to the next reminder or alarm, with a thin bar for how much of the wait has passed.
private struct CountdownCard: View {
    let open: (RemindersModel.Entry) -> Void
    @Environment(RemindersModel.self) private var reminders

    var body: some View {
        // Finds the next one every 30 seconds. Only the clock below ticks every second.
        TimelineView(.periodic(from: .now, by: 30)) { slow in
            let next = reminders.nextTimed(after: slow.date)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                card(next, now: context.date)
            }
        }
    }

    private func card(_ next: (entry: RemindersModel.Entry, since: Date)?, now: Date) -> some View {
        Button { if let next { open(next.entry) } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(label(next?.entry), systemImage: next?.entry.icon ?? "alarm.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color.voxAmber)
                Text(next.map { Self.clock($0.entry.date.timeIntervalSince(now)) } ?? "--:--:--")
                    .font(.system(size: 60, weight: .thin).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText(countsDown: true))
                Text(next.map { subtitle($0.entry) } ?? "Say \"remind me…\" or \"set an alarm…\"")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                ProgressBar(value: next.map { progress($0, now: now) } ?? 0)
                    .padding(.top, 8)
            }
            .voxCard(radius: 26, padding: 18)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.3), value: now)
    }

    private func label(_ entry: RemindersModel.Entry?) -> String {
        guard let entry else { return "NOTHING COMING UP" }
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        let kind = if case .deadline = entry.source { "DEADLINE" } else if entry.isAlarm { "NEXT ALARM" } else { "NEXT REMINDER" }
        return "\(kind) · \(time)"
    }

    private func subtitle(_ entry: RemindersModel.Entry) -> String {
        let calendar = Calendar.current
        let day = calendar.isDateInToday(entry.date) ? "today"
            : calendar.isDateInTomorrow(entry.date) ? "tomorrow"
            : entry.date.formatted(.dateTime.weekday(.wide))
        return "\(entry.title) · \(day)"
    }

    private func progress(_ next: (entry: RemindersModel.Entry, since: Date), now: Date) -> Double {
        let total = next.entry.date.timeIntervalSince(next.since)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(next.since) / total, 0), 1)
    }

    /// 00:29:42. Hours keep counting past 24.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.up)), 0)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.12))
                Capsule().fill(Color.voxAmber).frame(width: geo.size.width * value)
            }
        }
        .frame(height: 4)
        .accessibilityValue("\(Int(value * 100)) percent of the wait has passed")
    }
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
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.white.opacity(0.12), in: .capsule)
            }
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

/// A reminder with a date chip: amber month over the day number.
struct DatedRow: View {
    let entry: RemindersModel.Entry

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(entry.date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.voxAmber)
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
            }
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.08), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            Image(systemName: entry.icon).font(.subheadline).foregroundStyle(entry.tint)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
    }

    private var detail: String {
        let time = entry.date.formatted(date: .omitted, time: .shortened)
        if case .reminder(let reminder) = entry.source, let rule = reminder.repeatRule { return "\(time) · \(rule.label)" }
        if case .deadline = entry.source { return "Due \(time)" }
        return time
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
                .background(tint.opacity(0.18), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.25))
        }
        .padding(.vertical, 10)
    }

    /// Folders keep their own color. Lists are orange, boards green, notes white.
    private var tint: Color {
        if node.isFolder { return node.color.flatMap(Color.init(hex:)) ?? .voxFolder }
        if node.kind == .note { return .white.opacity(0.8) }
        return node.isBoard ? .voxBoard : .voxList
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
