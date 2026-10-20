import SwiftUI

/// The top level (`parentID` nil) or one item, with its children shown as a list, checklist, or board.
struct NodeListView: View {
    let parentID: UUID?
    @Environment(NotesModel.self) private var model

    @State private var prompt: NodePrompt?
    @State private var sectionFilter: UUID?
    @State private var editingColumns = false
    @State private var showingInfo = false

    var body: some View {
        let item = parentID.flatMap { model.node(id: $0) }
        let view = item?.view ?? .list
        let section = sectionFilter.flatMap { model.node(id: $0) }

        Group {
            switch view {
            case .board:
                if let item { BoardView(board: item, sectionID: $sectionFilter, editingColumns: $editingColumns) }
            case .checklist:
                ChecklistView(parentID: parentID)
            case .list:
                list(item)
            }
        }
        .overScenery()
        .navigationTitle(item?.title ?? "Vox")
        .toolbar {
            if let item {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("View", systemImage: view.icon) {
                        Picker("View", selection: Binding(get: { view }, set: { model.setView(item, $0) })) {
                            ForEach(PageView.allCases, id: \.self) { option in
                                Label(option.label, systemImage: option.icon)
                            }
                        }
                        if view == .board {
                            Button("Edit columns", systemImage: "slider.horizontal.3") { editingColumns = true }
                        }
                        Button("Info", systemImage: "info.circle") { showingInfo = true }
                    }
                }
            }
            if view == .list {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Add", systemImage: "plus") {
                    if view == .board {
                        Button("Column", systemImage: "rectangle.split.3x1") { prompt = .addColumn }
                        Button("Section", systemImage: "square.stack") { prompt = .addSection }
                    } else {
                        Button("Item", systemImage: "circle") { prompt = .add(.item) }
                        Button("Note", systemImage: "note.text") { prompt = .add(.note) }
                    }
                }
            }
        }
        .sheet(isPresented: $editingColumns) {
            if let item { BoardColumnsEditor(container: section ?? item) }
        }
        .sheet(isPresented: $showingInfo) {
            if let item { ItemInfoView(itemID: item.id) }
        }
        .nodePrompt($prompt) { prompt, title in
            switch prompt {
            case .add(let kind):
                // Checklist items start as tasks.
                let status: TaskStatus? = kind == .item && view == .checklist ? .todo : nil
                model.add(kind: kind, title: title, parentID: parentID, status: status)
            case .addColumn:
                // On a filtered board, the column goes into that section.
                model.add(kind: .item, title: title, parentID: sectionFilter ?? parentID)
            case .addSection:
                model.addSection(title, to: parentID)
            case .rename:
                break
            }
        }
    }

    private func list(_ item: Node?) -> some View {
        let kids = model.children(of: parentID)

        return List {
            if let item, item.hasInfo {
                Button { showingInfo = true } label: { ItemHeader(item: item) }
                    .buttonStyle(.plain)
                    .glassRow()
            }
            ForEach(kids) { node in
                NodeRow(node: node)
                    .glassRow()
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.delete([node.id])
                        }
                        Button("Rename", systemImage: "pencil") { prompt = .rename(node) }
                    }
                    .contextMenu { NodeMenu(node: node) { prompt = .rename(node) } }
            }
            .onMove { model.move(in: parentID, from: $0, to: $1) }
            .onDelete { offsets in model.delete(offsets.map { kids[$0].id }) }
            // With a header on screen, a small hint fits better than the big empty box.
            if kids.isEmpty, item?.hasInfo == true {
                Label("Nothing inside yet. Tap + to add.", systemImage: "tray")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .glassRow()
            }
        }
        .listStyle(.plain)
        .overlay {
            if kids.isEmpty, item?.hasInfo != true { EmptyGlassState() }
        }
    }
}

/// Compact summary of an item's own info, shown above its children.
struct ItemHeader: View {
    let item: Node

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if let status = item.status {
                    Text(status.label)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(status.tint.opacity(0.2), in: .capsule)
                        .foregroundStyle(status.tint)
                }
                if !item.details.isEmpty {
                    Text(item.detailsSummary).font(.subheadline)
                }
                Spacer()
                Image(systemName: "info.circle").foregroundStyle(.secondary)
            }
            if let due = item.dueAt {
                Label("Due \(due.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let body = item.body, !body.isEmpty {
                Text(body).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}

extension Node {
    /// Has something worth showing in the header.
    var hasInfo: Bool { status != nil || !details.isEmpty || dueAt != nil || !(body ?? "").isEmpty }
}

struct EmptyGlassState: View {
    var body: some View {
        ContentUnavailableView(
            "Nothing here yet",
            systemImage: "tray",
            description: Text("Tap + to add something.")
        )
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(32)
    }
}

// MARK: Add / rename prompt

enum NodePrompt {
    case add(NodeKind)
    case addColumn
    case addSection
    case rename(Node)

    var id: String {
        switch self {
        case .add(let kind): "add-\(kind.rawValue)"
        case .addColumn: "add-column"
        case .addSection: "add-section"
        case .rename(let node): "rename-\(node.id)"
        }
    }

    var title: String {
        switch self {
        case .add(let kind): "New \(kind.name.lowercased())"
        case .addColumn: "New column"
        case .addSection: "New section"
        case .rename: "Rename"
        }
    }
}

private struct NodePromptModifier: ViewModifier {
    @Binding var prompt: NodePrompt?
    let onAdd: (NodePrompt, String) -> Void
    @Environment(NotesModel.self) private var model
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert(prompt?.title ?? "", isPresented: Binding(
                get: { prompt != nil },
                set: { if !$0 { prompt = nil } }
            )) {
                TextField("Title", text: $draft)
                Button(isRename ? "Save" : "Add", action: commit)
                Button("Cancel", role: .cancel) {}
            }
            // Fill the text box each time a new prompt opens.
            .onChange(of: prompt?.id) {
                if case .rename(let node) = prompt { draft = node.title } else { draft = "" }
            }
    }

    private var isRename: Bool {
        if case .rename = prompt { true } else { false }
    }

    private func commit() {
        switch prompt {
        case .rename(let node): model.rename(node, to: draft)
        case let prompt?: onAdd(prompt, draft)
        case nil: break
        }
        prompt = nil
    }
}

extension View {
    /// Text prompt for adding or renaming a node.
    func nodePrompt(_ prompt: Binding<NodePrompt?>, onAdd: @escaping (NodePrompt, String) -> Void) -> some View {
        modifier(NodePromptModifier(prompt: prompt, onAdd: onAdd))
    }
}
