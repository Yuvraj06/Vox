import SwiftUI

/// A row that opens an item or a note.
/// Tasks get a checkbox you can tap without opening the row.
struct NodeRow: View {
    let node: Node
    @Environment(NotesModel.self) private var model

    var body: some View {
        let hasChildren = !model.children(of: node.id).isEmpty
        let isContainer = node.kind == .note || hasChildren || node.view != .list

        // Hidden link under a custom row, so the chevron stays inside the glass card.
        ZStack {
            NavigationLink(value: node) { EmptyView() }.opacity(0)
            HStack(spacing: 12) {
                if node.isTask {
                    StatusCheckbox(node: node)
                } else {
                    Image(systemName: isContainer ? node.icon : "circle.fill")
                        .font(isContainer ? .title3 : .caption2)
                        .foregroundStyle(node.columnType?.tint ?? (isContainer ? .primary : .secondary))
                        .frame(width: 28)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.title)
                        .font(isContainer ? .body.weight(.medium) : .body)
                        .strikethrough(node.status == .done)
                        .foregroundStyle(node.status == .done ? .secondary : .primary)
                    if let subtitle {
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
        if node.kind == .note {
            return node.body?.split(separator: "\n").first.map(String.init)
        }
        var parts: [String] = []
        if !node.details.isEmpty { parts.append(node.detailsSummary) }
        if node.isBoard {
            let cards = model.cardCount(of: node)
            parts.append("Board · \(cards == 1 ? "1 card" : "\(cards) cards")")
        } else if let progress = model.progress(of: node.id) {
            parts.append("\(progress.done)/\(progress.total) done")
        } else {
            let count = model.children(of: node.id).count
            if count > 0 { parts.append(count == 1 ? "1 item" : "\(count) items") }
        }
        if let due = node.dueAt { parts.append("Due \(due.formatted(.relative(presentation: .named)))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Tap to toggle done. Plain items become tasks the first time.
struct StatusCheckbox: View {
    let node: Node
    /// No status color, for cards in neutral columns.
    var plain = false
    @Environment(NotesModel.self) private var model

    var body: some View {
        Button {
            model.toggleDone(node)
        } label: {
            Image(systemName: icon)
                .imageScale(.large)
                .foregroundStyle(plain ? AnyShapeStyle(.secondary) : node.status.map { AnyShapeStyle($0.tint) } ?? AnyShapeStyle(.secondary))
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
            .background(TaskStatus.doing.tint.opacity(0.2), in: .capsule)
            .foregroundStyle(TaskStatus.doing.tint)
    }
}

/// Long-press menu shared by every row.
struct NodeMenu: View {
    let node: Node
    let rename: () -> Void
    @Environment(NotesModel.self) private var model

    var body: some View {
        if node.kind == .item {
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
        case .item: view?.icon ?? "list.bullet"
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
        case .item: "Item"
        case .note: "Note"
        }
    }

    var addIcon: String {
        switch self {
        case .item: "circle"
        case .note: "note.text"
        }
    }
}
