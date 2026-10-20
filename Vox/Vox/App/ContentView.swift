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
                    switch node.kind {
                    case .item: NodeListView(parentID: node.id)
                    case .note: NoteEditorView(nodeID: node.id)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Speech test", systemImage: "waveform") { showSpeechTest = true }
                    }
                }
        }
        // One background for every screen. It stays still and blurs as you go deeper.
        .background { SceneryBackground(depth: path.count) }
        // Dark mode keeps text readable on glass over the scenery.
        .preferredColorScheme(.dark)
        #if DEBUG
        // Debug only: `-open "Orbit/Frontend"` jumps straight to a screen by titles, handy for screenshots.
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            guard let flag = args.firstIndex(of: "-open"), args.indices.contains(flag + 1) else { return }
            // `-openSlowly` pushes one screen per second, to watch the transitions.
            let slow = args.contains("-openSlowly")
            Task {
                var parentID: UUID?
                for title in args[flag + 1].split(separator: "/") {
                    guard let next = model.children(of: parentID).first(where: { $0.title == title }) else { break }
                    if slow { try? await Task.sleep(for: .seconds(1)) }
                    path.append(next)
                    parentID = next.id
                }
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
