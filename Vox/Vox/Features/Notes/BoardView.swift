import SwiftUI

/// Task entries in a page and its sub-pages, in the page's own columns.
/// Drag a card to another column to move it there.
struct BoardView: View {
    let page: Node
    /// Sub-page to filter by. nil shows every task under `page`.
    @Binding var filterID: UUID?
    @Environment(NotesModel.self) private var model
    @State private var editingColumns = false

    var body: some View {
        let subpages = model.children(of: page.id).filter { $0.kind == .page }
        let tasks = model.boardEntries(under: filterID ?? page.id)
        let columns = model.columns(of: page)
        let placed = Dictionary(grouping: tasks) { BoardColumnDef.placement(of: $0, in: columns) }

        VStack(spacing: 14) {
            if !subpages.isEmpty {
                filterBar(subpages)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(columns) { column in
                        BoardColumn(page: page, column: column, allColumns: columns, tasks: placed[column.id] ?? [])
                            .containerRelativeFrame(.horizontal) { width, _ in width * 0.8 }
                    }
                    addColumnButton
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .padding(.top, 8)
        .sheet(isPresented: $editingColumns) { BoardColumnsEditor(page: page) }
    }

    private var addColumnButton: some View {
        Button {
            editingColumns = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3").font(.title2)
                Text("Edit columns").font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(width: 130, height: 160)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 26))
    }

    private func filterBar(_ subpages: [Node]) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("All", selected: filterID == nil) { filterID = nil }
                    ForEach(subpages) { sub in
                        chip(sub.title, selected: filterID == sub.id) { filterID = sub.id }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        if selected {
            Button(title, action: action)
                .buttonStyle(.glassProminent)
                .tint(TaskStatus.doing.tint.opacity(0.8))
        } else {
            Button(title, action: action).buttonStyle(.glass)
        }
    }
}

private struct BoardColumn: View {
    let page: Node
    let column: BoardColumnDef
    let allColumns: [BoardColumnDef]
    let tasks: [Node]
    @Environment(NotesModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        let tint = column.status?.tint

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(tint ?? .secondary).frame(width: 9, height: 9)
                Text(column.title).font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tint ?? .secondary)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        TaskCard(task: task, tint: tint, columns: allColumns, subpageName: subpageName(of: task))
                    }
                    if tasks.isEmpty {
                        Text("Drop tasks here")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 80)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        // The column stays neutral glass. Only the cards carry the tint.
        .glassEffect(.regular.tint(isTargeted ? .white.opacity(0.12) : nil), in: .rect(cornerRadius: 26))
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init(uuidString:)) {
                if let task = model.node(id: id) { model.move(task, to: column) }
            }
            return true
        } isTargeted: { isTargeted = $0 }
        .padding(.bottom, 8)
    }

    /// Shows which sub-page a task lives in, unless it sits directly in the board page.
    private func subpageName(of task: Node) -> String? {
        guard let parentID = task.parentID, parentID != page.id else { return nil }
        return model.node(id: parentID)?.title
    }
}

private struct TaskCard: View {
    let task: Node
    /// The column's tint. nil in neutral columns.
    let tint: Color?
    /// For the "Move to" menu.
    let columns: [BoardColumnDef]
    let subpageName: String?
    @Environment(NotesModel.self) private var model

    var body: some View {
        NavigationLink(value: task) {
            HStack(alignment: .top, spacing: 10) {
                StatusCheckbox(node: task, plain: tint == nil)

                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .strikethrough(task.status == .done)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 10) {
                        if let subpageName {
                            Label(subpageName, systemImage: "doc")
                        }
                        if let progress = model.progress(of: task.id) {
                            Label("\(progress.done)/\(progress.total)", systemImage: "checklist")
                        }
                        if let due = task.dueAt {
                            Label(due.formatted(.dateTime.day().month()), systemImage: "calendar")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint?.opacity(0.32)).interactive(), in: .rect(cornerRadius: 16))
        .draggable(task.id.uuidString) {
            Text(task.title)
                .padding(10)
                .glassEffect(.regular.tint(tint?.opacity(0.32)), in: .rect(cornerRadius: 12))
        }
        .contextMenu {
            ForEach(columns) { column in
                Button("Move to \(column.title)") { model.move(task, to: column) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete([task.id]) }
        }
    }
}

/// Add, rename, retype, reorder and remove a board's columns.
struct BoardColumnsEditor: View {
    let page: Node
    @Environment(NotesModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var columns: [BoardColumnDef] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($columns) { $column in
                        HStack(spacing: 12) {
                            Circle().fill(column.status?.tint ?? .secondary).frame(width: 10, height: 10)
                            TextField("Column name", text: $column.title)
                            Picker("Type", selection: $column.status) {
                                Text("Neutral").tag(TaskStatus?.none)
                                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag(TaskStatus?.some($0)) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .tint(column.status?.tint ?? .secondary)
                        }
                        .deleteDisabled(columns.count == 1)
                    }
                    .onMove { columns.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { columns.remove(atOffsets: $0) }

                    Button("Add column", systemImage: "plus") {
                        columns.append(BoardColumnDef(title: "", status: nil))
                    }
                } footer: {
                    Text("The type sets the card color. Done columns count as finished. Neutral columns stay uncolored and hold unfinished tasks.")
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
                    Button("Save", action: save)
                }
            }
        }
        .onAppear { columns = model.columns(of: page) }
    }

    private func save() {
        let cleaned = columns.map { column in
            var column = column
            column.title = column.title.trimmingCharacters(in: .whitespaces)
            if column.title.isEmpty { column.title = column.status?.label ?? "Column" }
            return column
        }
        // Read the page fresh so we don't overwrite changes made while the sheet was open.
        if let current = model.node(id: page.id) { model.setColumns(current, cleaned) }
        dismiss()
    }
}
