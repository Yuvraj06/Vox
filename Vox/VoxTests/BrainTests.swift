import Foundation
import FoundationModels
import Testing
@testable import Vox

@MainActor
struct ActionExecutorTests {
    let store: SwiftDataNodeStore
    let context: BrainContext

    init() throws {
        store = try .inMemory()
        context = BrainContext(store: store)
    }

    private func run(_ actions: [BrainAction]) throws -> ActionExecutor.Result {
        try ActionExecutor(context: context).apply(actions)
    }

    private func titles(_ parentID: UUID?) throws -> [String] {
        try store.children(of: parentID).map(\.title)
    }

    // MARK: Applying

    @Test func addToExistingListByHandle() throws {
        let movies = try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        let handle = context.handle(for: movies)

        let result = try run([BrainAction(type: .addItem, parent: handle, title: "Dune")])

        #expect(try titles(movies.id) == ["Dune"])
        #expect(result.summary == "+ Dune -> Movies")
        #expect(result.lines == ["Added Dune to Movies Watched"])
    }

    @Test func refsToNodesMadeEarlier() throws {
        try run([
            BrainAction(type: .createNode, parent: "top", title: "Movies Watched", kind: .item, view: .list),
            BrainAction(type: .addItem, parent: "#1", title: "Arrival"),
            BrainAction(type: .setDetail, target: "#2", key: "Rating", value: "4"),
        ])

        let movies = try #require(try store.children(of: nil).first)
        let arrival = try #require(try store.children(of: movies.id).first)
        #expect(arrival.title == "Arrival")
        #expect(arrival.details == [NodeDetail(key: "rating", value: "4")])
    }

    @Test func projectSetupMakesSectionsWithColumns() throws {
        let result = try run([
            BrainAction(type: .createNode, parent: "top", title: "Orbit", kind: .item, view: .board),
            BrainAction(type: .createNode, parent: "#1", title: "Frontend", kind: .item, view: .board),
            BrainAction(type: .createNode, parent: "#1", title: "Backend", kind: .item, view: .board),
        ])

        let orbit = try #require(try store.children(of: nil).first)
        #expect(orbit.isBoard)
        let kids = try store.children(of: orbit.id)
        #expect(kids.filter(\.isBoard).map(\.title) == ["Frontend", "Backend"])
        let frontend = try #require(kids.first { $0.title == "Frontend" })
        #expect(try titles(frontend.id) == ["Todo", "Doing", "Done"])
        #expect(result.summary == "+ Orbit +2")
    }

    @Test func cardOnBoardGoesIntoFittingColumn() throws {
        let board = try store.create(kind: .item, title: "Backend", parentID: nil, view: .board)
        try store.addDefaultColumns(to: board.id)
        let handle = context.handle(for: board)

        try run([BrainAction(type: .addItem, parent: handle, title: "Write docs", status: .doing)])

        let doing = try #require(try store.children(of: board.id).first { $0.title == "Doing" })
        let card = try #require(try store.children(of: doing.id).first)
        #expect(card.title == "Write docs")
        #expect(card.status == .doing)
    }

    @Test func doneMovesCardToDoneColumn() throws {
        let board = try store.create(kind: .item, title: "Backend", parentID: nil, view: .board)
        try store.addDefaultColumns(to: board.id)
        let todo = try #require(try store.children(of: board.id).first)
        let card = try store.create(kind: .item, title: "Auth", parentID: todo.id, status: .todo)

        try run([BrainAction(type: .setStatus, target: context.handle(for: card), status: .done)])

        let moved = try #require(try store.node(id: card.id))
        #expect(moved.status == .done)
        #expect(try store.node(id: try #require(moved.parentID))?.title == "Done")
    }

    @Test func titlePathFallback() throws {
        let orbit = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board)
        let backend = try store.create(kind: .item, title: "Backend", parentID: orbit.id, view: .board)
        try store.addDefaultColumns(to: backend.id)

        try run([BrainAction(type: .addItem, parent: "Orbit/Backend", title: "Sync")])

        let todo = try #require(try store.children(of: backend.id).first)
        #expect(try titles(todo.id) == ["Sync"])
    }

    @Test func dueDateFromPhrase() throws {
        let item = try store.create(kind: .item, title: "Report", parentID: nil, status: .todo)
        try run([BrainAction(type: .setDue, target: context.handle(for: item), timePhrase: "in 2 hours", estimateMinutes: 90)])

        let saved = try #require(try store.node(id: item.id))
        let due = try #require(saved.dueAt)
        #expect(abs(due.timeIntervalSinceNow - 7200) < 60)
        #expect(saved.estimateMinutes == 90)
    }

    @Test func unclearChangesNothing() throws {
        #expect(throws: ActionExecutor.Failure.self) {
            try run([
                BrainAction(type: .createNode, parent: "top", title: "Should not exist"),
                BrainAction(type: .unclear, question: "Which list?"),
            ])
        }
        #expect(try store.children(of: nil).isEmpty)
    }

    // MARK: All or nothing

    @Test func failureRollsBackEarlierActions() throws {
        let movies = try store.create(kind: .item, title: "Movies", parentID: nil)
        let handle = context.handle(for: movies)

        #expect(throws: ActionExecutor.Failure.self) {
            try run([
                BrainAction(type: .addItem, parent: handle, title: "Dune"),
                BrainAction(type: .renameNode, target: handle, title: "Films"),
                BrainAction(type: .setStatus, target: "n99", status: .done),
            ])
        }
        #expect(try titles(nil) == ["Movies"])
        #expect(try titles(movies.id).isEmpty)
    }

    // MARK: Undo

    @Test func undoRemovesWhatWasAdded() throws {
        let movies = try store.create(kind: .item, title: "Movies", parentID: nil)
        let result = try run([
            BrainAction(type: .addItem, parent: context.handle(for: movies), title: "Dune"),
            BrainAction(type: .createNode, parent: "top", title: "Books"),
        ])

        try store.apply(result.inverse)

        #expect(try titles(nil) == ["Movies"])
        #expect(try titles(movies.id).isEmpty)
    }

    @Test func undoBringsBackDeletedTree() throws {
        let movies = try store.create(kind: .item, title: "Movies", parentID: nil)
        try store.create(kind: .item, title: "Dune", parentID: movies.id)
        let result = try run([BrainAction(type: .deleteNode, target: context.handle(for: movies))])
        #expect(try titles(nil).isEmpty)

        try store.apply(result.inverse)

        #expect(try titles(nil) == ["Movies"])
        #expect(try titles(movies.id) == ["Dune"])
    }

    @Test func undoRestoresRenameStatusAndMove() throws {
        let a = try store.create(kind: .item, title: "Inbox", parentID: nil)
        let b = try store.create(kind: .item, title: "Archive", parentID: nil)
        let task = try store.create(kind: .item, title: "Call mom", parentID: a.id, status: .todo)
        let handle = context.handle(for: task)

        let result = try run([
            BrainAction(type: .renameNode, target: handle, title: "Call mum"),
            BrainAction(type: .setStatus, target: handle, status: .done),
            BrainAction(type: .moveNode, target: handle, parent: context.handle(for: b)),
        ])
        try store.apply(result.inverse)

        let back = try #require(try store.node(id: task.id))
        #expect(back.title == "Call mom")
        #expect(back.status == .todo)
        #expect(back.parentID == a.id)
    }

    @Test func inverseSurvivesJSON() throws {
        let result = try run([BrainAction(type: .createNode, parent: "top", title: "Ideas")])
        let data = try JSONEncoder().encode(result.inverse)
        #expect(try JSONDecoder().decode([InverseStep].self, from: data) == result.inverse)
    }

    @Test func summaryFitsKeychain() {
        #expect(ActionExecutor.summary(["+ A very long item title -> Movies"]).count <= 21)
        #expect(ActionExecutor.summary(["+ A very long item title", "x", "y"]).hasSuffix(" +2"))
    }
}

@MainActor
struct BrainLogTests {
    @Test func undoThroughBrainMarksLogEntry() throws {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let log = SwiftDataActionLogStore(container: container)
        let brain = Brain(nodes: nodes, log: log)

        let context = BrainContext(store: nodes)
        let result = try ActionExecutor(context: context).apply([BrainAction(type: .createNode, parent: "top", title: "Ideas")])
        let entry = ActionLogEntry(transcript: "make ideas", actionsJSON: "[]", inverse: result.inverse, summary: result.summary)
        try log.append(entry)

        try brain.undo(entry.id)

        #expect(try nodes.children(of: nil).isEmpty)
        #expect(try log.entry(id: entry.id)?.undone == true)
        #expect(try log.recent(limit: 5).map(\.id) == [entry.id])
    }
}

@MainActor
struct DatePhraseTests {
    let now = Date.now

    @Test func relativePhrases() throws {
        let inTwoHours = try #require(DatePhrase.date(from: "in 2 hours", now: now))
        #expect(abs(inTwoHours.timeIntervalSince(now) - 7200) < 1)
        let inTen = try #require(DatePhrase.date(from: "in ten minutes", now: now))
        #expect(abs(inTen.timeIntervalSince(now) - 600) < 1)
        #expect(DatePhrase.date(from: "in half an hour", now: now) != nil)
    }

    @Test func tomorrowAtTime() throws {
        let date = try #require(DatePhrase.date(from: "tomorrow 5pm", now: now))
        let calendar = Calendar.current
        #expect(calendar.isDateInTomorrow(date))
        #expect(calendar.component(.hour, from: date) == 17)
    }

    @Test func weekdayIsInTheFuture() throws {
        let date = try #require(DatePhrase.date(from: "Friday 5pm", now: now))
        #expect(date > now)
        #expect(Calendar.current.component(.weekday, from: date) == 6)
    }

    @Test func nonsenseGivesNil() {
        #expect(DatePhrase.date(from: "banana", now: now) == nil)
        #expect(DatePhrase.date(from: "", now: now) == nil)
    }
}

@MainActor
struct NodeSearchTests {
    @Test func findsListBySimilarWords() throws {
        let store = try SwiftDataNodeStore.inMemory()
        try store.create(kind: .item, title: "Books to read", parentID: nil)
        try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        let context = BrainContext(store: store)

        let first = NodeSearch.rank(query: "movies I watched", in: context.allNodes(), ancestors: context.ancestorTitles(of:)).first
        #expect(first?.title == "Movies Watched")
    }

    @Test func pathWordsPickTheRightSection() throws {
        let store = try SwiftDataNodeStore.inMemory()
        let orbit = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board)
        let vega = try store.create(kind: .item, title: "Vega", parentID: nil, view: .board)
        try store.create(kind: .item, title: "Backend", parentID: vega.id, view: .board)
        try store.create(kind: .item, title: "Backend", parentID: orbit.id, view: .board)
        let context = BrainContext(store: store)

        let first = NodeSearch.rank(query: "orbit backend", in: context.allNodes(), ancestors: context.ancestorTitles(of:)).first
        #expect(first?.parentID == orbit.id)
    }

    @Test func noMatchForUnrelatedWords() throws {
        let store = try SwiftDataNodeStore.inMemory()
        try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        let context = BrainContext(store: store)
        #expect(NodeSearch.rank(query: "groceries", in: context.allNodes(), ancestors: context.ancestorTitles(of:)).isEmpty)
    }
}

@MainActor
struct PlanPreviewTests {
    let store: SwiftDataNodeStore
    let context: BrainContext

    init() throws {
        store = try .inMemory()
        context = BrainContext(store: store)
    }

    @Test func trailShowsWhereAnItemGoes() throws {
        let movies = try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        let result = try PlanPreview(context: context).steps(for: [
            BrainAction(type: .addItem, parent: context.handle(for: movies), title: "Dune"),
        ])
        #expect(result.steps.map(\.path) == [["Movies Watched"]])
        #expect(result.steps.first?.title == "Dune")
        #expect(!result.guessedRef && !result.maybeDuplicate)
        // Nothing was changed.
        #expect(try store.children(of: movies.id).isEmpty)
    }

    @Test func cardOnBoardShowsItsColumn() throws {
        let board = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board)
        let steps = try PlanPreview(context: context).steps(for: [
            BrainAction(type: .addItem, parent: context.handle(for: board), title: "Fix login", status: .doing),
        ]).steps
        #expect(steps.first?.path == ["Orbit", "Doing"])
    }

    @Test func refsToEarlierActionsBuildThePath() throws {
        let steps = try PlanPreview(context: context).steps(for: [
            BrainAction(type: .createNode, parent: "top", title: "Orbit", kind: .item, view: .board),
            BrainAction(type: .createNode, parent: "#1", title: "Frontend", kind: .item, view: .board),
        ]).steps
        #expect(steps.map(\.path) == [[], ["Orbit"]])
        #expect(steps.map(\.note) == ["board", "board"])
    }

    @Test func unknownRefIsAProblem() {
        #expect(throws: PlanPreview.Problem.unknownRef("n9")) {
            try PlanPreview(context: context).steps(for: [BrainAction(type: .addItem, parent: "n9", title: "Dune")])
        }
    }

    @Test func titleRefAndLookalikeListAreFlagged() throws {
        try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        let guessed = try PlanPreview(context: context).steps(for: [
            BrainAction(type: .addItem, parent: "Movies Watched", title: "Dune"),
        ])
        #expect(guessed.guessedRef)
        let duplicate = try PlanPreview(context: context).steps(for: [
            BrainAction(type: .createNode, parent: "top", title: "Movies", kind: .item, view: .list),
        ])
        #expect(duplicate.maybeDuplicate)
    }

    @Test func plansAgreeIgnoringCase() {
        let a = PlanStep(id: 0, verb: .add, path: ["Movies Watched"], title: "Dune", note: nil)
        let b = PlanStep(id: 3, verb: .add, path: ["movies watched"], title: "dune", note: "Todo")
        #expect(a.sameChange(as: b))
        #expect(!a.sameChange(as: PlanStep(id: 0, verb: .add, path: [], title: "Dune", note: nil)))
    }
}

struct PlanRepairTests {
    @Test func itemGoesIntoTheListMadeBeforeIt() {
        let fixed = PlanRepair.itemsIntoNewList([
            BrainAction(type: .createNode, parent: "top", title: "Movies Watched", kind: .item, view: .list),
            BrainAction(type: .addItem, parent: "top", title: "Dune"),
        ])
        #expect(fixed.map(\.parent) == ["top", "#1"])
    }

    @Test func itemsWithoutANewListStayPut() {
        let actions = [BrainAction(type: .addItem, parent: "top", title: "Clean clothes", status: .todo)]
        #expect(PlanRepair.itemsIntoNewList(actions) == actions)
    }

    @MainActor
    @Test func existingListIsReusedAndRefsRenumbered() throws {
        let store = try SwiftDataNodeStore.inMemory()
        let movies = try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        let context = BrainContext(store: store)

        let fixed = PlanRepair.reuseExistingLists([
            BrainAction(type: .createNode, parent: "top", title: "Watched movies", kind: .item, view: .list),
            BrainAction(type: .addItem, parent: "#1", title: "Avengers Endgame"),
            BrainAction(type: .setDetail, target: "#2", key: "rating", value: "10/10"),
        ], context: context)

        let handle = context.handle(for: movies)
        #expect(fixed.map(\.type) == [.addItem, .setDetail])
        #expect(fixed[0].parent == handle)
        #expect(fixed[1].target == "#1")
        try ActionExecutor(context: context).apply(fixed)
        #expect(try store.children(of: nil).count == 1)
        #expect(try store.children(of: movies.id).map(\.title) == ["Avengers Endgame"])
    }

    @MainActor
    @Test func outlineShowsTreeWithIdsAndNoNoteText() throws {
        let store = try SwiftDataNodeStore.inMemory()
        let movies = try store.create(kind: .item, title: "Movies Watched", parentID: nil, view: .list)
        try store.create(kind: .item, title: "Dune", parentID: movies.id)
        let orbit = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board)
        try store.addDefaultColumns(to: orbit.id)
        var note = try store.create(kind: .note, title: "Ideas", parentID: nil)
        note.body = "secret text"
        try store.update(note)
        let context = BrainContext(store: store)

        let outline = context.outline()
        #expect(outline.contains("n1 Movies Watched (list)"))
        #expect(outline.contains("\n  n2 Dune"))
        #expect(outline.contains("Todo (column)"))
        #expect(outline.contains("Ideas (note)"))
        #expect(!outline.contains("secret"))
        // The ids work for the executor too.
        #expect(context.id(forHandle: "n1") == movies.id)
    }

    @MainActor
    @Test func topListsShowMainListsNotTasks() throws {
        let store = try SwiftDataNodeStore.inMemory()
        try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        try store.create(kind: .item, title: "Clean clothes", parentID: nil, status: .todo)
        try store.create(kind: .note, title: "Ideas", parentID: nil)
        let context = BrainContext(store: store)

        #expect(context.topLists(excluding: []).map(\.title) == ["Movies Watched"])
    }

    @Test func newNoteIsNotAList() {
        let fixed = PlanRepair.itemsIntoNewList([
            BrainAction(type: .createNode, parent: "top", title: "Trip ideas", kind: .note),
            BrainAction(type: .addItem, parent: "top", title: "Pack"),
        ])
        #expect(fixed[1].parent == "top")
    }
}

@MainActor
struct CandidateSearchTests {
    @Test func findsListsNamedInASentence() throws {
        let store = try SwiftDataNodeStore.inMemory()
        try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        try store.create(kind: .item, title: "Books to read", parentID: nil)
        let context = BrainContext(store: store)

        let found = context.candidates(for: "hey can you please add Dune to the movies I have watched recently").map(\.title)
        #expect(found == ["Movies Watched"])
    }

    @Test func boardColumnsAreLeftOut() throws {
        let store = try SwiftDataNodeStore.inMemory()
        let board = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board)
        try store.addDefaultColumns(to: board.id)
        let context = BrainContext(store: store)

        #expect(context.candidates(for: "add a todo to clean clothes").isEmpty)
    }

    @Test func hiddenNodesAreNotSeen() throws {
        let store = try SwiftDataNodeStore.inMemory()
        let movies = try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        let context = BrainContext(store: store)
        context.hidden = [movies.id]

        #expect(context.candidates(for: "movies watched").isEmpty)
    }

    @Test func repeatedToolCallsAreStopped() throws {
        let context = BrainContext(store: try SwiftDataNodeStore.inMemory())
        #expect(context.findNodes("movies") != BrainContext.stopMessage)
        #expect(context.findNodes("Movies") == BrainContext.stopMessage)
    }
}

/// Runs the real on-device model. Skipped where Apple Intelligence isn't available.
@MainActor
struct LiveBrainTests {
    @Test(.enabled(if: SystemLanguageModel.default.isAvailable))
    func addToMoviesWatched() async throws {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let movies = try nodes.create(kind: .item, title: "Movies Watched", parentID: nil)
        let brain = Brain(nodes: nodes, log: SwiftDataActionLogStore(container: container))

        let outcome = await brain.planAndApply("Add Dune to movies I watched")

        print("Outcome:", outcome)
        #expect(try nodes.children(of: movies.id).map(\.title) == ["Dune"])
    }

    @Test(.enabled(if: SystemLanguageModel.default.isAvailable))
    func projectSetup() async throws {
        let container = try LocalDatabase.inMemory()
        let nodes = SwiftDataNodeStore(container: container)
        let brain = Brain(nodes: nodes, log: SwiftDataActionLogStore(container: container))

        let outcome = await brain.planAndApply("Make a todo list for my project Orbit")

        print("Outcome:", outcome)
        let orbit = try #require(try nodes.children(of: nil).first { $0.title.contains("Orbit") })
        #expect(orbit.isBoard)
        #expect(try nodes.children(of: orbit.id).filter(\.isBoard).count >= 2)
    }
}

private extension Brain {
    /// Plans a command and applies it right away, like pressing Next.
    func planAndApply(_ text: String) async -> CommandOutcome {
        switch await plan(text, scope: nil, progress: { _ in }) {
        case .ready(let plan): apply(plan)
        case .unclear(let question): .unclear(question: question)
        case .queued: .failed(message: "queued")
        case .failed(let message): .failed(message: message)
        }
    }
}

/// Commands said on an open screen see everything, plus a line saying where you are.
@MainActor
struct ScopeTests {
    let store: SwiftDataNodeStore
    let media: Node
    let movies: Node
    let orbit: Node

    init() throws {
        store = try .inMemory()
        media = try store.create(kind: .item, title: "Media", parentID: nil, view: .folder)
        movies = try store.create(kind: .item, title: "Movies", parentID: media.id, view: .list)
        try store.create(kind: .item, title: "Dune", parentID: movies.id)
        orbit = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board)
    }

    @Test func outlineHoldsEverythingAndMarksTheOpenScreen() {
        let outline = BrainContext(store: store, scope: movies.id).outline()
        #expect(outline.contains("Orbit"))
        #expect(outline.contains("Dune"))
        #expect(outline.contains("Movies (list, open screen)"))
    }

    @Test func hereLineNamesTheOpenItem() throws {
        let context = BrainContext(store: store, scope: movies.id)
        let line = try #require(context.hereLine())
        let handle = context.handle(for: movies)
        #expect(line.contains("\"Movies\" list, in Media"))
        #expect(line.contains("Put a new thing in \(handle) only when it fits there"))
        #expect(BrainContext(store: store).hereLine() == nil)
    }

    @Test func hereLineForANotePointsAtItsFolder() throws {
        let note = try store.create(kind: .note, title: "Ideas", parentID: orbit.id, body: "secret text")
        let context = BrainContext(store: store, scope: note.id)
        let line = try #require(context.hereLine())
        #expect(line.contains("Put a new thing in \(context.handle(for: orbit))"))
        #expect(!line.contains("secret") && !context.outline().contains("secret"))
    }

    @Test func listsInsideTheOpenItemComeFirst() throws {
        try store.create(kind: .item, title: "Books", parentID: media.id, view: .list)
        let context = BrainContext(store: store, scope: media.id)
        #expect(context.topLists(excluding: []).map(\.title) == ["Movies", "Books", "Orbit"])
    }

    @Test func mainListsStayVisibleFromABigFolder() throws {
        for title in ["A", "B", "C", "D", "E", "F", "G"] {
            try store.create(kind: .item, title: title, parentID: orbit.id, view: .list)
        }
        let watched = try store.create(kind: .item, title: "Movies Watched", parentID: nil, view: .list)
        let context = BrainContext(store: store, scope: orbit.id)
        #expect(context.topLists(excluding: []).contains { $0.id == watched.id })
    }

    @Test func topStillMeansTheTopLevel() throws {
        let context = BrainContext(store: store, scope: movies.id)
        try ActionExecutor(context: context).apply([BrainAction(type: .addItem, parent: "top", title: "Groceries")])
        #expect(try store.children(of: nil).map(\.title) == ["Media", "Orbit", "Groceries"])
    }

    @Test func noDuplicateListInsideAFolder() {
        let context = BrainContext(store: store, scope: media.id)
        let actions = PlanRepair.reuseExistingLists([
            BrainAction(type: .createNode, parent: context.handle(for: media), title: "movies", kind: .item, view: .list),
            BrainAction(type: .addItem, parent: "#1", title: "Arrival"),
        ], context: context)
        #expect(actions.count == 1)
        #expect(actions.first?.parent == context.handle(for: movies))
    }
}

/// "I started X" and "I finished X" set doing and done, even when the model forgets.
struct StatusWordsTests {
    @Test func readsTheStatusFromTheWords() {
        #expect(PlanRepair.spokenStatus(in: "I started doing EN open ended project") == .doing)
        #expect(PlanRepair.spokenStatus(in: "I'm working on the report") == .doing)
        #expect(PlanRepair.spokenStatus(in: "I finished the EN project") == .done)
        #expect(PlanRepair.spokenStatus(in: "Done with the essay") == .done)
        #expect(PlanRepair.spokenStatus(in: "Make a todo list for my project Orbit") == nil)
        #expect(PlanRepair.spokenStatus(in: "I finished watching Dune") == nil)
    }

    @Test func newProjectGetsTheStatusAtTheEnd() {
        let fixed = PlanRepair.statusFromWords([
            BrainAction(type: .createNode, parent: "top", title: "EN Open Ended Project", kind: .item, view: .board),
            BrainAction(type: .createNode, parent: "#1", title: "Research", kind: .item, view: .board),
        ], command: "I started doing EN open ended project")
        #expect(fixed.count == 3)
        #expect(fixed[1].parent == "#1")
        #expect(fixed[2] == BrainAction(type: .setStatus, target: "#1", status: .doing))
    }

    @Test func newItemGetsTheStatusDirectly() {
        let fixed = PlanRepair.statusFromWords([
            BrainAction(type: .addItem, parent: "n1", title: "EN project"),
        ], command: "I finished the EN project")
        #expect(fixed == [BrainAction(type: .addItem, parent: "n1", title: "EN project", status: .done)])
    }

    @Test func leavesPlansThatAlreadySetAStatus() {
        let plan = [BrainAction(type: .setStatus, target: "n2", status: .doing)]
        #expect(PlanRepair.statusFromWords(plan, command: "I started the EN project") == plan)
    }

    @Test func existingProjectBecomesDoingThroughTheExecutor() throws {
        let store = try SwiftDataNodeStore.inMemory()
        let project = try store.create(kind: .item, title: "EN Open Ended Project", parentID: nil, view: .board)
        let context = BrainContext(store: store)
        let actions = PlanRepair.all([
            BrainAction(type: .createNode, parent: "top", title: "EN open ended project", kind: .item, view: .board),
        ], command: "I started doing EN open ended project", context: context)
        try ActionExecutor(context: context).apply(actions)
        #expect(try store.node(id: project.id)?.status == .doing)
        #expect(try store.children(of: nil).count == 1)
    }
}
