import SwiftUI

/// Root navigation: the notes tree, starting at the top level.
/// The brain button at the top right opens Thinking. The mic floats over everything.
struct ContentView: View {
    @Environment(NotesModel.self) private var model
    @Environment(CaptureModel.self) private var capture
    @State private var path: [Route] = []

    var body: some View {
        @Bindable var model = model

        NavigationStack(path: $path) {
            HomeView()
                .thinkingButton()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .node(let node) where node.kind == .note: NoteEditorView(nodeID: node.id).thinkingButton()
                    case .node(let node): NodeListView(parentID: node.id).thinkingButton()
                    case .allNotes: NodeListView(parentID: nil).thinkingButton()
                    case .allReminders: AllRemindersView().thinkingButton()
                    }
                }
        }
        // Rows and cards open their screen through this, so a hold can open settings instead.
        .environment(\.openNode, OpenNodeAction { path.append(.node($0)) })
        // Room at the bottom so the last rows can scroll above the mic.
        .contentMargins(.bottom, 140, for: .scrollContent)
        // One background for every screen. It stays still and blurs as you go deeper.
        .background { SceneryBackground(depth: path.count) }
        // Darkens the bottom so the mic stands out over the last cards.
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 200)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { CaptureOverlay() }
        // The mic only talks about the open screen.
        .onChange(of: path, initial: true) {
            if case .node(let node)? = path.last { capture.scope = node } else { capture.scope = nil }
        }
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
                    path.append(.node(next))
                    parentID = next.id
                }
            }
        }
        #endif
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
        .environment(CaptureModel(runner: PreviewRunner()))
        .environment(ThinkingQueue())
        .environment(GeminiSettings())
        .environment(RemindersModel(
            store: try! SwiftDataReminderStore.inMemory(),
            nodes: try! SwiftDataNodeStore.inMemory(),
            scheduler: FakeReminderScheduler()
        ))
}

/// Previews only: answers every command without the model.
private struct PreviewRunner: CommandRunner {
    func plan(_ text: String, scope: UUID?, progress: @escaping ([PlanStep]) -> Void) async -> PlanOutcome {
        let step = PlanStep(id: 0, verb: .add, path: ["Movies Watched"], title: text, note: nil)
        return .ready(CommandPlan(transcript: text, steps: [step], needsCheck: false))
    }

    func apply(_ plan: CommandPlan) -> CommandOutcome {
        .applied(summary: "+ \(plan.transcript)", lines: ["Added \(plan.transcript)"], logID: UUID())
    }

    func discard(_ plan: CommandPlan) {}

    func undo(_ logID: UUID) throws {}
}
