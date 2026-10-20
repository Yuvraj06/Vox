import SwiftUI

/// Root navigation: the notes tree, starting at the top level.
struct ContentView: View {
    @Environment(NotesModel.self) private var model
    @State private var showSpeechTest = false
    @State private var path: [Node] = []

    var body: some View {
        @Bindable var model = model

        NavigationStack(path: $path) {
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
        // Dark mode keeps text readable on glass over the scenery.
        .preferredColorScheme(.dark)
        #if DEBUG
        // Debug only: `-openFirstNode` jumps straight into the first item, handy for screenshots.
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openFirstNode"),
               let first = model.children(of: nil).first {
                path = [first]
            }
        }
        #endif
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
