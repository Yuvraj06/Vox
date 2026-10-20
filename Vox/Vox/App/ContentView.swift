import SwiftUI

/// Root navigation: the notes tree, starting at the top level.
struct ContentView: View {
    @Environment(NotesModel.self) private var model
    @State private var showSpeechTest = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            NodeListView(parentID: nil)
                .navigationDestination(for: Node.self) { node in
                    if node.kind == .note {
                        NoteEditorView(nodeID: node.id)
                    } else {
                        NodeListView(parentID: node.id)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Speech test", systemImage: "waveform") { showSpeechTest = true }
                    }
                }
        }
        .sheet(isPresented: $showSpeechTest) { SpeechTestView() }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

#Preview {
    ContentView()
        .environment(NotesModel(store: try! SwiftDataNodeStore.inMemory()))
}
