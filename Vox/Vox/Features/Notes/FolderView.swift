import SwiftUI

/// A folder's children as a grid of tiles. Folders inside show in their own color.
struct FolderView: View {
    let parentID: UUID?
    @Environment(NotesModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        let kids = model.children(of: parentID)

        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(kids) { node in
                    FolderTile(node: node)
                        .nodeGestures(node)
                }
            }
            .padding(16)
        }
        .overlay {
            if kids.isEmpty { EmptyGlassState() }
        }
    }
}

/// One square-ish tile: big icon, title, what is inside.
struct FolderTile: View {
    let node: Node
    @Environment(NotesModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: node.icon)
                .font(.system(size: 30))
                .foregroundStyle(node.isFolder ? node.tint : .primary)
            Spacer(minLength: 0)
            Text(node.title)
                .font(.headline)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .padding(16)
        .contentShape(.rect)
        .glassEffect(.regular.tint(node.isFolder ? node.tint.opacity(0.22) : .clear), in: .rect(cornerRadius: 22))
    }

    private var subtitle: String {
        if node.kind == .note { return "Note" }
        if node.isBoard { return "Board" }
        let count = model.children(of: node.id).count
        return count == 1 ? "1 item" : "\(count) items"
    }
}
