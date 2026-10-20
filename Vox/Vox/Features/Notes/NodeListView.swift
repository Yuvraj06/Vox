import SwiftUI

/// The top level (`parentID` nil) or one page, shown as a list, checklist, or board.
struct NodeListView: View {
    let parentID: UUID?
    @Environment(NotesModel.self) private var model

    @State private var prompt: NodePrompt?
    @State private var boardFilter: UUID?
    @State private var editingColumns = false

    var body: some View {
        let page = parentID.flatMap { model.node(id: $0) }
        let view = page?.view ?? .list

        Group {
            switch view {
            case .board:
                if let page { BoardView(page: page, filterID: $boardFilter) }
            case .checklist:
                ChecklistView(parentID: parentID)
            case .list:
                list
            }
        }
        .sceneryBackground()
        .navigationTitle(page?.title ?? "Vox")
        .toolbar {
            if let page {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("View", systemImage: view.icon) {
                        Picker("View", selection: Binding(get: { view }, set: { model.setView(page, $0) })) {
                            ForEach(PageView.allCases, id: \.self) { option in
                                Label(option.label, systemImage: option.icon)
                            }
                        }
                        if view == .board {
                            Button("Edit columns", systemImage: "slider.horizontal.3") { editingColumns = true }
                        }
                    }
                }
            }
            if view == .list {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Add", systemImage: "plus") {
                    ForEach(NodeKind.addable(inside: page?.kind), id: \.self) { kind in
                        Button(kind.name, systemImage: kind.addIcon) { prompt = .add(kind) }
                    }
                }
            }
        }
        .sheet(isPresented: $editingColumns) {
            if let page { BoardColumnsEditor(page: page) }
        }
        .nodePrompt($prompt) { kind, title in
            // Checklists and boards are for tasks, so new items start as Todo there.
            let status: TaskStatus? = kind == .entry && view != .list ? .todo : nil
            // On a filtered board, new things go into the selected sub-page.
            model.add(kind: kind, title: title, parentID: boardFilter ?? parentID, status: status)
        }
    }

    private var list: some View {
        let kids = model.children(of: parentID)

        return List {
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
        }
        .listStyle(.plain)
        .overlay {
            if kids.isEmpty { EmptyGlassState() }
        }
    }
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
    case rename(Node)

    var id: String {
        switch self {
        case .add(let kind): "add-\(kind.rawValue)"
        case .rename(let node): "rename-\(node.id)"
        }
    }

    var title: String {
        switch self {
        case .add(let kind): "New \(kind.name.lowercased())"
        case .rename: "Rename"
        }
    }
}

private struct NodePromptModifier: ViewModifier {
    @Binding var prompt: NodePrompt?
    let onAdd: (NodeKind, String) -> Void
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
        case .add(let kind): onAdd(kind, draft)
        case .rename(let node): model.rename(node, to: draft)
        case nil: break
        }
        prompt = nil
    }
}

extension View {
    /// Text prompt for adding or renaming a node.
    func nodePrompt(_ prompt: Binding<NodePrompt?>, onAdd: @escaping (NodeKind, String) -> Void) -> some View {
        modifier(NodePromptModifier(prompt: prompt, onAdd: onAdd))
    }
}
