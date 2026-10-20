import SwiftUI

/// Edit a note's title and body. Saves when you leave the screen.
struct NoteEditorView: View {
    let nodeID: UUID
    @Environment(NotesModel.self) private var model

    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $title)
                .font(.title2.bold())
            Divider()
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(16)
        .overScenery()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear(perform: save)
    }

    private func load() {
        guard let node = model.node(id: nodeID) else { return }
        title = node.title
        text = node.body ?? ""
    }

    private func save() {
        guard var node = model.node(id: nodeID) else { return }
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let newBody = text.isEmpty ? nil : text
        guard (!newTitle.isEmpty && newTitle != node.title) || newBody != node.body else { return }
        if !newTitle.isEmpty { node.title = newTitle }
        node.body = newBody
        model.save(node)
    }
}
