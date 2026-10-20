import SwiftUI

/// Task entries in a page and its sub-pages, in Todo / Doing / Done columns.
/// Drag a card to another column to change its status.
struct BoardView: View {
    let page: Node
    /// Sub-page to filter by. nil shows every task under `page`.
    @Binding var filterID: UUID?
    @Environment(NotesModel.self) private var model

    var body: some View {
        let subpages = model.children(of: page.id).filter { $0.kind == .page }
        let tasks = model.boardEntries(under: filterID ?? page.id)

        VStack(spacing: 14) {
            if !subpages.isEmpty {
                filterBar(subpages)
            }

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        BoardColumn(
                            page: page,
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
            Button(title, action: action).buttonStyle(.glassProminent)
        } else {
            Button(title, action: action).buttonStyle(.glass)
        }
    }
}

private struct BoardColumn: View {
    let page: Node
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
                        TaskCard(task: task, subpageName: subpageName(of: task))
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

    /// Shows which sub-page a task lives in, unless it sits directly in the board page.
    private func subpageName(of task: Node) -> String? {
        guard let parentID = task.parentID, parentID != page.id else { return nil }
        return model.node(id: parentID)?.title
    }
}

private struct TaskCard: View {
    let task: Node
    let subpageName: String?
    @Environment(NotesModel.self) private var model

    var body: some View {
        NavigationLink(value: task) {
            HStack(alignment: .top, spacing: 10) {
                StatusCheckbox(node: task)

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
