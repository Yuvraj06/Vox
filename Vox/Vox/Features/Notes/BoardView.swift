import SwiftUI

/// A board: the item's children are columns, their children are cards.
/// Child boards are sections; their columns merge into this board by title.
struct BoardView: View {
    let board: Node
    /// Section to show alone. nil shows the board's own columns plus every section's.
    @Binding var sectionID: UUID?
    @Binding var editingColumns: Bool
    @Environment(NotesModel.self) private var model

    var body: some View {
        let sections = model.sections(of: board)
        let section = sectionID.flatMap { id in sections.first { $0.id == id } }
        let columns = model.columns(for: board, section: section)

        VStack(spacing: 14) {
            if !sections.isEmpty {
                filterBar(sections)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns) { column in
                        BoardColumnView(
                            board: board,
                            column: column,
                            showsSection: section == nil && !sections.isEmpty
                        )
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.76 }
                    }
                    editColumnsTile(isEmpty: columns.isEmpty)
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .padding(.top, 8)
        // A section that was deleted elsewhere should not stay selected.
        .onChange(of: sections.map(\.id)) { _, ids in
            if let sectionID, !ids.contains(sectionID) { self.sectionID = nil }
        }
    }

    private func editColumnsTile(isEmpty: Bool) -> some View {
        Button {
            editingColumns = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: isEmpty ? "plus" : "slider.horizontal.3").font(.title2)
                Text(isEmpty ? "Add columns" : "Edit columns").font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(width: 130, height: 160)
        }
        .buttonStyle(.plain)
        .voxGlass(in: .rect(cornerRadius: 24), interactive: true)
    }

    private func filterBar(_ sections: [Node]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip("All", selected: sectionID == nil) { sectionID = nil }
                ForEach(sections) { sub in
                    chip(sub.title, selected: sectionID == sub.id) { sectionID = sub.id }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        // The app keeps room at the bottom of scroll views for the mic. Here it would make the chip row
        // that much taller and push the columns down.
        .contentMargins(.bottom, 0, for: .scrollContent)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The picked section is solid white with dark text. The others are glass.
    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? Color(white: 0.1) : .white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if selected { Capsule().fill(.white.opacity(0.92)) }
                }
                .voxGlass(in: .capsule, interactive: true)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .animation(.snappy, value: selected)
    }
}

private struct BoardColumnView: View {
    let board: Node
    let column: NotesModel.BoardColumn
    let showsSection: Bool
    @Environment(NotesModel.self) private var model
    @State private var isTargeted = false
    @State private var addingCard = false
    @State private var newCard = ""

    var body: some View {
        let tint = column.type?.tint

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(tint ?? .secondary).frame(width: 8, height: 8)
                Text(column.title).font(.system(size: 15, weight: .semibold))
                Text("\(column.cards.count)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Button("Add card", systemImage: "plus") { addingCard = true }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(column.cards) { card in
                        TaskCard(
                            card: card,
                            tint: tint,
                            sectionName: showsSection ? sectionName(of: card) : nil
                        )
                    }
                    Button {
                        addingCard = true
                    } label: {
                        Label("Add card", systemImage: "plus")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        // The column stays neutral glass. Only the cards carry the tint.
        .background(.white.opacity(isTargeted ? 0.12 : 0), in: .rect(cornerRadius: 24))
        .voxGlass(in: .rect(cornerRadius: 24))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init(uuidString:)) {
                if let card = model.node(id: id) { model.drop(card, into: column) }
            }
            Haptics.thud()
            return true
        } isTargeted: { isTargeted = $0 }
        .padding(.bottom, 8)
        .alert("New card in \(column.title)", isPresented: $addingCard) {
            TextField("Title", text: $newCard)
            Button("Add") {
                model.addCard(newCard, to: column)
                newCard = ""
            }
            Button("Cancel", role: .cancel) { newCard = "" }
        }
    }

    /// The section a card belongs to, unless it sits in the board's own column.
    private func sectionName(of card: Node) -> String? {
        guard let source = column.sources.first(where: { $0.id == card.parentID }),
              let sectionID = source.parentID, sectionID != board.id else { return nil }
        return model.node(id: sectionID)?.title
    }
}

private struct TaskCard: View {
    let card: Node
    /// The column's tint. nil in neutral columns.
    let tint: Color?
    let sectionName: String?
    @Environment(NotesModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            StatusCheckbox(node: card, plain: tint == nil)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let typeIcon {
                        Image(systemName: typeIcon)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(card.title)
                        .strikethrough(card.status == .done)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 10) {
                    if let sectionName {
                        Label(sectionName, systemImage: "square.stack")
                    }
                    if let progress = model.progress(of: card.id) {
                        Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                    }
                    if let due = card.dueAt {
                        Label(due.formatted(.dateTime.day().month()), systemImage: "calendar")
                            .foregroundStyle(Color.voxAmber)
                            .fontWeight(.medium)
                    }
                    if !card.details.isEmpty {
                        Text(card.detailsSummary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .labelStyle(TightLabel())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card: tint)
        .nodeGestures(card)
        .draggable(card.id.uuidString) {
            Text(card.title)
                .padding(10)
                .background(card: tint)
        }
    }

    /// What kind of thing the card is: a board, checklist, folder, note, or a list with items inside.
    /// A plain card with nothing inside gets no icon.
    private var typeIcon: String? {
        if card.kind == .note || card.view == .board || card.view == .checklist || card.isFolder { return card.icon }
        return model.children(of: card.id).isEmpty ? nil : card.icon
    }
}

private extension View {
    /// A card's soft fill and edge in its column's tint. Neutral columns get faint white.
    func background(card tint: Color?) -> some View {
        let color = tint ?? .white
        let shape = RoundedRectangle(cornerRadius: 16)
        return background(color.opacity(tint == nil ? 0.06 : 0.16), in: shape)
            .overlay { shape.strokeBorder(color.opacity(tint == nil ? 0.15 : 0.35), lineWidth: 1) }
            .contentShape(shape)
    }
}

/// Icon and text close together, for the small facts under a card title.
private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
        }
    }
}

/// Add, rename, retype, reorder and remove the columns of one board or section.
struct BoardColumnsEditor: View {
    let container: Node
    @Environment(NotesModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [NotesModel.ColumnDraft] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($drafts, id: \.key) { $draft in
                        HStack(spacing: 12) {
                            Circle().fill(draft.type?.tint ?? .secondary).frame(width: 10, height: 10)
                            TextField("Column name", text: $draft.title)
                            Picker("Type", selection: $draft.type) {
                                Text("Neutral").tag(TaskStatus?.none)
                                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag(TaskStatus?.some($0)) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(draft.type?.tint ?? .secondary)
                        }
                        .deleteDisabled(drafts.count == 1)
                    }
                    .onMove { drafts.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { drafts.remove(atOffsets: $0) }

                    Button("Add column", systemImage: "plus") {
                        drafts.append(NotesModel.ColumnDraft(id: nil, title: "", type: nil))
                    }
                } header: {
                    Text("Columns of \(container.title)")
                } footer: {
                    Text("The type sets the card color. Done columns count as finished. Neutral columns stay uncolored. Removing a column moves its cards to the first column.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Columns")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.saveColumns(drafts, in: container)
                        dismiss()
                    }
                    .disabled(drafts.isEmpty)
                }
            }
        }
        .onAppear {
            drafts = model.columnDrafts(in: container)
            if drafts.isEmpty {
                drafts = TaskStatus.allCases.map { NotesModel.ColumnDraft(id: nil, title: $0.label, type: $0) }
            }
        }
    }
}
