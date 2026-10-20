import SwiftUI

/// One entry: title, status, details (rating, coordinates...), deadline, sub-items, notes.
/// Status and sub-items save right away. Text fields save when you leave the screen.
struct EntryDetailView: View {
    let entryID: UUID
    @Environment(NotesModel.self) private var model

    @State private var title = ""
    @State private var text = ""
    @State private var details: [NodeDetail] = []
    @State private var hasDue = false
    @State private var due = Date.now.addingTimeInterval(86_400)
    @State private var newSubItem = ""

    var body: some View {
        let entry = model.node(id: entryID)
        let kids = model.children(of: entryID)

        List {
            if let entry {
                header(entry).glassCardRow()
            }

            sectionTitle("Sub-items")
            ForEach(kids) { child in
                NodeRow(node: child)
                    .glassRow()
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete([child.id]) }
                    }
            }
            .onMove { model.move(in: entryID, from: $0, to: $1) }
            HStack {
                Image(systemName: "plus.circle").foregroundStyle(.secondary)
                TextField("Add sub-item", text: $newSubItem)
                    .submitLabel(.done)
                    .onSubmit(addSubItem)
            }
            .glassRow()

            sectionTitle("Details")
            detailsCard.glassCardRow()

            sectionTitle("Deadline")
            dueCard.glassCardRow()

            sectionTitle("Notes")
            TextEditor(text: $text)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .glassCardRow()
        }
        .listStyle(.plain)
        .sceneryBackground()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    // MARK: Cards

    private func header(_ entry: Node) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Title", text: $title, axis: .vertical)
                .font(.title2.bold())
            Picker("Status", selection: Binding(
                get: { entry.status },
                set: { model.setStatus(entry, $0) }
            )) {
                Text("None").tag(TaskStatus?.none)
                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag(TaskStatus?.some($0)) }
            }
            .pickerStyle(.segmented)
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(details.indices, id: \.self) { index in
                HStack {
                    TextField("Name", text: $details[index].key)
                        .frame(maxWidth: 120)
                        .foregroundStyle(.secondary)
                    TextField("Value", text: $details[index].value)
                    Button {
                        details.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                Divider()
            }
            HStack(spacing: 8) {
                Button("Add detail", systemImage: "plus") {
                    details.append(NodeDetail(key: "", value: ""))
                }
                if !details.contains(where: { $0.key.lowercased() == "rating" }) {
                    Button("Rating", systemImage: "star") {
                        details.append(NodeDetail(key: "rating", value: ""))
                    }
                }
            }
            .buttonStyle(.glass)
        }
    }

    private var dueCard: some View {
        VStack(alignment: .leading) {
            Toggle("Has a deadline", isOn: $hasDue)
            if hasDue {
                DatePicker("Due", selection: $due)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 22, bottom: 0, trailing: 16))
    }

    // MARK: Load / save

    private func addSubItem() {
        model.add(kind: .entry, title: newSubItem, parentID: entryID, status: .todo)
        newSubItem = ""
    }

    private func load() {
        guard let entry = model.node(id: entryID) else { return }
        title = entry.title
        text = entry.body ?? ""
        details = entry.details
        hasDue = entry.dueAt != nil
        if let dueAt = entry.dueAt { due = dueAt }
    }

    private func save() {
        guard var entry = model.node(id: entryID) else { return }
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = details
            .map { NodeDetail(key: $0.key.trimmingCharacters(in: .whitespaces), value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }

        var changed = entry
        if !newTitle.isEmpty { changed.title = newTitle }
        changed.body = text.isEmpty ? nil : text
        changed.details = cleaned
        changed.dueAt = hasDue ? due : nil
        guard changed != entry else { return }
        entry = changed
        model.save(entry)
    }
}

private extension View {
    /// A padded glass card inside a List row.
    func glassCardRow() -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}
