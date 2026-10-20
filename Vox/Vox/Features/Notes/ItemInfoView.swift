import SwiftUI

/// Sheet for an item's own properties: title, status, column type, details, deadline, notes.
/// Its children are shown on the item's screen, not here.
struct ItemInfoView: View {
    let itemID: UUID
    @Environment(NotesModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var text = ""
    @State private var details: [NodeDetail] = []
    @State private var hasDue = false
    @State private var due = Date.now.addingTimeInterval(86_400)
    @State private var columnType: TaskStatus?

    var body: some View {
        let item = model.node(id: itemID)
        let parent = item?.parentID.flatMap { model.node(id: $0) }
        let isColumn = parent?.isBoard == true && item?.isBoard == false

        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title3.bold())
                }

                if let item {
                    Section("Status") {
                        Picker("Status", selection: Binding(
                            get: { item.status },
                            set: { model.setStatus(item, $0) }
                        )) {
                            Text("None").tag(TaskStatus?.none)
                            ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag(TaskStatus?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if isColumn {
                    Section {
                        Picker("Column type", selection: $columnType) {
                            Text("Neutral").tag(TaskStatus?.none)
                            ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag(TaskStatus?.some($0)) }
                        }
                        .tint(columnType?.tint ?? .secondary)
                    } footer: {
                        Text("This item is a column on \(parent?.title ?? "the board"). Its type sets the card color.")
                    }
                }

                Section("Details") {
                    ForEach(details.indices, id: \.self) { index in
                        HStack {
                            TextField("Name", text: $details[index].key)
                                .frame(maxWidth: 120)
                                .foregroundStyle(.secondary)
                            TextField("Value", text: $details[index].value)
                        }
                    }
                    .onDelete { details.remove(atOffsets: $0) }
                    Button("Add detail", systemImage: "plus") {
                        details.append(NodeDetail(key: "", value: ""))
                    }
                    if !details.contains(where: { $0.key.lowercased() == "rating" }) {
                        Button("Add rating", systemImage: "star") {
                            details.append(NodeDetail(key: "rating", value: ""))
                        }
                    }
                }

                Section("Deadline") {
                    Toggle("Has a deadline", isOn: $hasDue)
                    if hasDue {
                        DatePicker("Due", selection: $due)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $text)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private func load() {
        guard let item = model.node(id: itemID) else { return }
        title = item.title
        text = item.body ?? ""
        details = item.details
        hasDue = item.dueAt != nil
        if let dueAt = item.dueAt { due = dueAt }
        columnType = item.columnType
    }

    private func save() {
        guard let item = model.node(id: itemID) else { return }
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = details
            .map { NodeDetail(key: $0.key.trimmingCharacters(in: .whitespaces), value: $0.value.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.key.isEmpty && !$0.value.isEmpty }

        var changed = item
        if !newTitle.isEmpty { changed.title = newTitle }
        changed.body = text.isEmpty ? nil : text
        changed.details = cleaned
        changed.dueAt = hasDue ? due : nil
        changed.columnType = columnType
        guard changed != item else { return }
        model.save(changed)
    }
}
