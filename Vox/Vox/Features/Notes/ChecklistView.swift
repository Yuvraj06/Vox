import SwiftUI

/// Items with checkboxes, and their children as a foldable tree.
struct ChecklistView: View {
    let parentID: UUID?
    @Environment(NotesModel.self) private var model

    @State private var collapsed: Set<UUID> = []
    @State private var prompt: NodePrompt?
    /// Where "Add sub-item" puts the new item.
    @State private var addTarget: UUID?

    private struct Row: Identifiable {
        let node: Node
        let depth: Int
        let hasChildren: Bool
        var id: UUID { node.id }
    }

    var body: some View {
        let rows = flatten(parentID, depth: 0)

        List {
            ForEach(rows) { row in
                Group {
                    if row.node.kind == .item {
                        entryRow(row)
                    } else {
                        NodeRow(node: row.node)
                    }
                }
                .glassRow(indent: CGFloat(row.depth) * 22)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { model.delete([row.node.id]) }
                    if row.node.kind == .item {
                        Button("Sub-item", systemImage: "plus") {
                            addTarget = row.node.id
                            prompt = .add(.item)
                        }
                    }
                }
                .statusSwipe(row.node)
            }
        }
        .listStyle(.plain)
        .overlay {
            if rows.isEmpty { EmptyGlassState() }
        }
        .nodePrompt($prompt) { _, title in
            if let addTarget {
                model.add(kind: .item, title: title, parentID: addTarget, status: .todo)
                collapsed.remove(addTarget)
            }
            addTarget = nil
        }
    }

    private func entryRow(_ row: Row) -> some View {
        HStack(spacing: 10) {
            if row.hasChildren {
                Button {
                    withAnimation(.snappy) { toggle(row.node.id) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .rotationEffect(.degrees(collapsed.contains(row.node.id) ? 0 : 90))
                        .frame(width: 18, height: 28)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 18, height: 1)
            }

            StatusCheckbox(node: row.node)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.node.title)
                    .strikethrough(row.node.status == .done)
                    .foregroundStyle(row.node.status == .done ? .secondary : .primary)
                if let progress = model.progress(of: row.node.id) {
                    Text("\(progress.done)/\(progress.total) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if row.node.status == .doing { DoingBadge() }
        }
        .nodeGestures(row.node)
    }

    /// Turns the tree into rows, skipping the children of folded entries.
    private func flatten(_ id: UUID?, depth: Int) -> [Row] {
        model.children(of: id).flatMap { child -> [Row] in
            let kids = child.kind == .item ? model.children(of: child.id) : []
            let row = Row(node: child, depth: depth, hasChildren: !kids.isEmpty)
            guard !kids.isEmpty, !collapsed.contains(child.id) else { return [row] }
            return [row] + flatten(child.id, depth: depth + 1)
        }
    }

    private func toggle(_ id: UUID) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }
}
