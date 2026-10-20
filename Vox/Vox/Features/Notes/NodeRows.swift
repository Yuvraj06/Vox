import SwiftUI

/// A row that opens a node: pages, notes, and entries.
/// Tasks get a checkbox you can tap without opening the row.
struct NodeRow: View {
    let node: Node
    @Environment(NotesModel.self) private var model

    var body: some View {
        // Hidden link under a custom row, so the chevron stays inside the glass card.
        ZStack {
            NavigationLink(value: node) { EmptyView() }.opacity(0)
            HStack(spacing: 12) {
                if node.isTask {
                    StatusCheckbox(node: node)
                } else {
                    Image(systemName: node.icon)
                        .font(node.kind == .entry ? .caption2 : .title3)
                        .foregroundStyle(node.kind == .entry ? .secondary : .primary)
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(node.kind == .entry ? .body : .body.weight(.medium))
                        .strikethrough(node.status == .done)
                        .foregroundStyle(node.status == .done ? .secondary : .primary)
                    if let subtitle = subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if node.status == .doing { DoingBadge() }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var subtitle: String? {
        switch node.kind {
        case .note:
            return node.body?.split(separator: "\n").first.map(String.init)
        case .page:
            if node.view == .board {
                return "Board · \(model.boardEntries(under: node.id).count) tasks"
            }
            let count = model.children(of: node.id).count
            return count == 1 ? "1 item" : "\(count) items"
        case .entry:
            var parts: [String] = []
            if !node.details.isEmpty { parts.append(node.detailsSummary) }
            if let progress = model.progress(of: node.id) {
                parts.append("\(progress.done)/\(progress.total) done")
            } else {
                let count = model.children(of: node.id).count
                if count > 0 { parts.append(count == 1 ? "1 sub-item" : "\(count) sub-items") }
            }
            if let due = node.dueAt { parts.append("Due \(due.formatted(.relative(presentation: .named)))") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }
}

/// Tap to toggle done. Plain entries become tasks the first time.
struct StatusCheckbox: View {
    let node: Node
    @Environment(NotesModel.self) private var model

    var body: some View {
        Button {
            model.toggleDone(node)
        } label: {
            Image(systemName: icon)
                .imageScale(.large)
                .foregroundStyle(node.status == .done ? .green : .secondary)
                .frame(width: 28)
        }
        .buttonStyle(.plain)
    }

    private var icon: String {
        switch node.status {
        case .done: "checkmark.circle.fill"
        case .doing: "circle.lefthalf.filled"
        default: "circle"
        }
    }
}

struct DoingBadge: View {
    var body: some View {
        Text("Doing")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.orange.opacity(0.2), in: .capsule)
            .foregroundStyle(.orange)
    }
}

/// Long-press menu shared by every row.
struct NodeMenu: View {
    let node: Node
    let rename: () -> Void
    @Environment(NotesModel.self) private var model

    var body: some View {
        if node.kind == .entry {
            Picker("Status", selection: Binding(
                get: { node.status },
                set: { model.setStatus(node, $0) }
            )) {
                Text("No status").tag(TaskStatus?.none)
                ForEach(TaskStatus.allCases, id: \.self) { Text($0.label).tag(TaskStatus?.some($0)) }
            }
        }
        Button("Rename", systemImage: "pencil", action: rename)
        Button("Delete", systemImage: "trash", role: .destructive) { model.delete([node.id]) }
    }
}

extension Node {
    var icon: String {
        switch kind {
        case .page: view?.icon ?? "doc"
        case .entry: "circle.fill"
        case .note: "note.text"
        }
    }

    /// "★ 4 · x 120 · y 64". A numeric rating gets a star.
    var detailsSummary: String {
        details.map { detail in
            if detail.key.lowercased() == "rating" { return "★ \(detail.value)" }
            return "\(detail.key) \(detail.value)"
        }
        .joined(separator: " · ")
    }
}

extension PageView {
    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .checklist: "checklist"
        case .board: "rectangle.split.3x1"
        }
    }
}

extension NodeKind {
    /// Name shown in the + menu.
    var name: String {
        switch self {
        case .page: "Page"
        case .entry: "Item"
        case .note: "Note"
        }
    }

    var addIcon: String {
        switch self {
        case .page: "doc"
        case .entry: "circle"
        case .note: "note.text"
        }
    }

    /// What the + menu offers inside a parent of this kind (nil = top level).
    static func addable(inside parent: NodeKind?) -> [NodeKind] {
        switch parent {
        case nil: [.page, .note]
        case .page: [.entry, .page, .note]
        case .entry: [.entry]
        case .note: []
        }
    }
}
