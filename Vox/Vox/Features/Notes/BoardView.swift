import SwiftUI

/// All tasks under a folder, in Todo / Doing / Done columns.
/// Drag a card to another column to change its status.
struct BoardView: View {
    let folder: Node
    /// Subfolder to filter by. nil shows every task under `folder`.
    @Binding var filterID: UUID?
    @Environment(NotesModel.self) private var model

    var body: some View {
        let subfolders = model.children(of: folder.id).filter { $0.kind == .folder }
        let tasks = model.tasks(under: filterID ?? folder.id)

        VStack(spacing: 14) {
            if !subfolders.isEmpty {
                filterBar(subfolders)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        BoardColumn(
                            folder: folder,
                            status: status,
                            tasks: tasks.filter { $0.status == status }
                        )
                        .containerRelativeFrame(.horizontal) { width, _ in width * 0.8 }
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 16)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
        .padding(.top, 8)
    }

    private func filterBar(_ subfolders: [Node]) -> some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip("All", selected: filterID == nil) { filterID = nil }
                    ForEach(subfolders) { sub in
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
            Button(title, action: action).buttonStyle(.glassProminent)
        } else {
            Button(title, action: action).buttonStyle(.glass)
        }
    }
}

private struct BoardColumn: View {
    let folder: Node
    let status: TaskStatus
    let tasks: [Node]
    @Environment(NotesModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(status.label).font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        TaskCard(task: task, subfolderName: subfolderName(of: task))
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
        .glassEffect(
            isTargeted ? .regular.tint(.white.opacity(0.2)) : .regular,
            in: .rect(cornerRadius: 26)
        )
        .dropDestination(for: String.self) { ids, _ in
            for id in ids.compactMap(UUID.init(uuidString:)) {
                if let task = model.node(id: id), task.status != status {
                    model.setStatus(task, status)
                }
            }
            return true
        } isTargeted: { isTargeted = $0 }
        .padding(.bottom, 8)
    }

    /// Shows which subfolder a task lives in, unless it sits directly in the board folder.
    private func subfolderName(of task: Node) -> String? {
        guard let parentID = task.parentID, parentID != folder.id else { return nil }
        return model.node(id: parentID)?.title
    }
}

private struct TaskCard: View {
    let task: Node
    let subfolderName: String?
    @Environment(NotesModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                model.toggleDone(task)
            } label: {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle(task.status == .done ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .strikethrough(task.status == .done)
                if let subfolderName {
                    Label(subfolderName, systemImage: "folder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        .draggable(task.id.uuidString) {
            Text(task.title)
                .padding(10)
                .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .contextMenu {
            ForEach(TaskStatus.allCases.filter { $0 != task.status }, id: \.self) { status in
                Button("Move to \(status.label)") { model.setStatus(task, status) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { model.delete([task.id]) }
        }
    }
}
