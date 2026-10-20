import SwiftUI

/// Shows the children of one node, or the top level when `parentID` is nil.
struct NodeListView: View {
    let parentID: UUID?
    @Environment(NotesModel.self) private var model

    @State private var prompt: Prompt?
    @State private var draft = ""

    private enum Prompt {
        case add(NodeKind)
        case rename(Node)

        var title: String {
            switch self {
            case .add(let kind): "New \(kind.name.lowercased())"
            case .rename: "Rename"
            }
        }

        var confirm: String {
            switch self {
            case .add: "Add"
            case .rename: "Save"
            }
        }
    }

    var body: some View {
        let parent = parentID.flatMap { model.node(id: $0) }
        let kids = model.children(of: parentID)

        List {
            ForEach(kids) { node in
                row(node)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            model.delete([node.id])
                        }
                        Button("Rename", systemImage: "pencil") {
                            startPrompt(.rename(node))
                        }
                    }
                    .contextMenu { menu(for: node) }
            }
            .onMove { model.move(in: parentID, from: $0, to: $1) }
            .onDelete { offsets in model.delete(offsets.map { kids[$0].id }) }
        }
        .overlay {
            if kids.isEmpty {
                ContentUnavailableView(
                    "Nothing here yet",
                    systemImage: "tray",
                    description: Text("Tap + to add something.")
                )
            }
        }
        .navigationTitle(parent?.title ?? "Vox")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("Add", systemImage: "plus") {
                    ForEach(NodeKind.addable(inside: parent?.kind), id: \.self) { kind in
                        Button(kind.name, systemImage: kind.icon) { startPrompt(.add(kind)) }
                    }
                }
            }
        }
        .alert(prompt?.title ?? "", isPresented: isPrompting) {
            TextField("Title", text: $draft)
            Button(prompt?.confirm ?? "OK", action: commitPrompt)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ node: Node) -> some View {
        switch node.kind {
        case .folder, .list, .note:
            NavigationLink(value: node) {
                Label(node.title, systemImage: node.kind.icon)
            }
        case .task:
            TaskRow(node: node) { model.toggleDone(node) }
        case .item:
            Text(node.title)
        }
    }

    @ViewBuilder
    private func menu(for node: Node) -> some View {
        if node.kind == .task {
            Picker("Status", selection: Binding(
                get: { node.status ?? .todo },
                set: { model.setStatus(node, $0) }
            )) {
                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label) }
            }
        }
        Button("Rename", systemImage: "pencil") { startPrompt(.rename(node)) }
        Button("Delete", systemImage: "trash", role: .destructive) { model.delete([node.id]) }
    }

    // MARK: Prompt

    private var isPrompting: Binding<Bool> {
        Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })
    }

    private func startPrompt(_ newPrompt: Prompt) {
        if case .rename(let node) = newPrompt { draft = node.title } else { draft = "" }
        prompt = newPrompt
    }

    private func commitPrompt() {
        switch prompt {
        case .add(let kind): model.add(kind: kind, title: draft, parentID: parentID)
        case .rename(let node): model.rename(node, to: draft)
        case nil: break
        }
        prompt = nil
    }
}

/// A task with a tappable circle. Long press the row to pick Todo, Doing or Done.
private struct TaskRow: View {
    let node: Node
    let toggle: () -> Void

    var body: some View {
        HStack {
            Button(action: toggle) {
                Image(systemName: icon)
                    .foregroundStyle(node.status == .done ? .green : .secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)

            Text(node.title)
                .strikethrough(node.status == .done)
                .foregroundStyle(node.status == .done ? .secondary : .primary)

            Spacer()

            if node.status == .doing {
                Text("Doing")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.2), in: .capsule)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var icon: String {
        switch node.status {
        case .done: "checkmark.circle.fill"
        case .doing: "circle.lefthalf.filled"
        default: "circle"
        }
    }
}

extension NodeKind {
    var name: String {
        switch self {
        case .folder: "Folder"
        case .list: "List"
        case .item: "Item"
        case .task: "Task"
        case .note: "Note"
        }
    }

    var icon: String {
        switch self {
        case .folder: "folder"
        case .list: "list.bullet"
        case .item: "circle.fill"
        case .task: "checkmark.circle"
        case .note: "note.text"
        }
    }

    /// What the + menu offers inside a parent of this kind (nil = top level).
    static func addable(inside parent: NodeKind?) -> [NodeKind] {
        switch parent {
        case nil: [.folder, .list, .note]
        case .folder: [.folder, .list, .task, .note]
        case .list: [.item, .task]
        default: []
        }
    }
}
