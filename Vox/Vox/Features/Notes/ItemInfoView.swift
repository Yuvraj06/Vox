import SwiftUI

/// Sheet for an item's own properties: title, status, column type, details, deadline, notes, move and delete.
/// Opens from the Info button, or by holding any row or card. Its children are shown on the item's screen, not here.
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
    @State private var color: String?
    @State private var editingReminder: Reminder?

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

                if let item, !isColumn {
                    Section {
                        Picker("Type", selection: Binding(
                            get: { item.kind == .note ? nil : item.view ?? .list },
                            set: { view in
                                model.setType(item, view: view)
                                color = model.node(id: itemID)?.color
                            }
                        )) {
                            ForEach(PageView.allCases, id: \.self) { option in
                                Label(option.label, systemImage: option.icon).tag(PageView?.some(option))
                            }
                            Label("Note", systemImage: "note.text").tag(PageView?.none)
                                .selectionDisabled(item.kind == .item && !model.children(of: item.id).isEmpty)
                        }
                    } footer: {
                        if item.kind == .item, !model.children(of: item.id).isEmpty {
                            Text("Only an empty item can become a note.")
                        }
                    }
                }

                if let item, item.isFolder {
                    Section("Color") {
                        FolderColorPicker(selection: $color)
                    }
                } else if let item, item.kind == .item, !isColumn {
                    Section {
                        StatusButtons(node: item)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    } header: {
                        Text("Status")
                    } footer: {
                        Text("Tap the lit one again to clear it.")
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

                if let item, !isColumn {
                    ReminderSection(node: item, editing: $editingReminder)
                }

                if let item {
                    Section {
                        let destinations = model.folderDestinations(for: item)
                        if !destinations.isEmpty || item.parentID != nil {
                            Menu {
                                if item.parentID != nil {
                                    Button("Top level", systemImage: "house") { model.move(item, to: nil) }
                                }
                                ForEach(destinations) { folder in
                                    Button(folder.title, systemImage: "folder.fill") { model.move(item, to: folder.id) }
                                }
                            } label: {
                                Label("Move to", systemImage: "folder")
                            }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.delete([item.id])
                            dismiss()
                        }
                    }
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
        .sheet(item: $editingReminder) { ReminderEditor(reminder: $0) }
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
        color = item.color
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
        changed.color = color
        guard changed != item else { return }
        model.save(changed)
    }
}

/// Preset swatches, plus a custom color picker for anything else.
struct FolderColorPicker: View {
    @Binding var selection: String?

    var body: some View {
        let selected = selection.flatMap(Color.init(hex:)) ?? FolderPalette.presets[0].color
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 36), spacing: 12)], spacing: 12) {
                ForEach(FolderPalette.presets) { preset in
                    Button {
                        selection = preset.hex
                    } label: {
                        Circle()
                            .fill(preset.color)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if selection == preset.hex {
                                    Image(systemName: "checkmark").font(.footnote.bold()).foregroundStyle(.black.opacity(0.7))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.name)
                }
            }
            ColorPicker("Custom color", selection: Binding(
                get: { selected },
                set: { selection = $0.hex }
            ), supportsOpacity: false)
        }
        .padding(.vertical, 4)
    }
}
