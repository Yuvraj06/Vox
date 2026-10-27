import SwiftUI

/// A row that opens an item or a note.
/// Tasks get a checkbox you can tap without opening the row.
struct NodeRow: View {
    let node: Node
    @Environment(NotesModel.self) private var model

    var body: some View {
        let hasChildren = !model.children(of: node.id).isEmpty
        let isContainer = node.kind == .note || hasChildren || node.view != .list

        HStack(spacing: 12) {
            if node.isTask {
                StatusCheckbox(node: node)
            } else {
                Image(systemName: isContainer ? node.icon : "circle.fill")
                    .font(isContainer ? .title3 : .caption2)
                    .foregroundStyle(node.columnType?.tint ?? (node.isFolder ? node.tint : (isContainer ? .primary : .secondary)))
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
        .nodeGestures(node)
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

/// Big Todo, Doing, Done buttons. Tap the lit one again to clear it.
/// On a board, the card moves to the column that fits.
struct StatusButtons: View {
    let node: Node
    @Environment(NotesModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TaskStatus.allCases, id: \.self) { status in
                let selected = node.status == status
                Button {
                    model.setStatus(node, selected ? nil : status)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: status.icon).font(.title2)
                        Text(status.label).font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .foregroundStyle(selected ? Color.black.opacity(0.8) : status.tint)
                    .background(status.tint.opacity(selected ? 1 : 0.18), in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: node.status)
    }
}

/// Opens a node: pushes its screen. Set by the root navigation.
struct OpenNodeAction {
    var open: (Node) -> Void = { _ in }
    func callAsFunction(_ node: Node) { open(node) }
}

extension EnvironmentValues {
    @Entry var openNode = OpenNodeAction()
}

/// Tap opens the node. Hold, then let go, opens its settings instead.
/// A board card that starts dragging never gets the release, so dragging still works.
private struct NodeGestures: ViewModifier {
    let node: Node
    @Environment(\.openNode) private var openNode
    @State private var showingSettings = false
    /// True once the finger has stayed down long enough. The release then opens settings.
    @State private var held = false

    func body(content: Content) -> some View {
        Button {
            if held { showingSettings = true } else { openNode(node) }
            held = false
        } label: {
            content.contentShape(.rect)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onChanged { _ in held = false }
                .onEnded { _ in held = true }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: held) { _, new in new }
        .sheet(isPresented: $showingSettings) {
            ItemInfoView(itemID: node.id)
        }
    }
}

/// Swipe right for Todo, Doing, Done. Folders, notes and board columns have no status.
private struct StatusSwipe: ViewModifier {
    let node: Node
    @Environment(NotesModel.self) private var model

    func body(content: Content) -> some View {
        let parent = node.parentID.flatMap { model.node(id: $0) }
        let isColumn = parent?.isBoard == true && !node.isBoard
        if node.kind == .item, !node.isFolder, !isColumn {
            content.swipeActions(edge: .leading, allowsFullSwipe: false) {
                // Swipe actions show right to left, so Done is listed first to end up on the outside.
                ForEach(TaskStatus.allCases.reversed(), id: \.self) { status in
                    Button(status.label, systemImage: node.status == status ? "checkmark" : status.icon) {
                        model.setStatus(node, node.status == status ? nil : status)
                    }
                    .tint(status.tint)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Tap opens the node, hold opens its settings.
    func nodeGestures(_ node: Node) -> some View { modifier(NodeGestures(node: node)) }

    /// Swipe right to set Todo, Doing or Done.
    func statusSwipe(_ node: Node) -> some View { modifier(StatusSwipe(node: node)) }
}

extension TaskStatus {
    var icon: String {
        switch self {
        case .todo: "circle"
        case .doing: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
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
        case .folder: "folder.fill"
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
