import Foundation
import Testing
@testable import Vox

@MainActor
struct NodeStoreTests {
    let store: SwiftDataNodeStore
    let model: NotesModel

    init() throws {
        store = try .inMemory()
        model = NotesModel(store: store)
    }

    // MARK: Storage

    @Test func positionMath() {
        #expect(NodeOrdering.position(between: nil, and: nil) == 1)
        #expect(NodeOrdering.position(between: 1, and: 2) == 1.5)
        #expect(NodeOrdering.position(between: 3, and: nil) == 4)
        #expect(NodeOrdering.position(between: nil, and: 1) == 0)
    }

    @Test func createAppendsInOrder() throws {
        let movies = try store.create(kind: .item, title: "Movies Watched", parentID: nil)
        try store.create(kind: .item, title: "Dune", parentID: movies.id)
        try store.create(kind: .item, title: "Alien", parentID: movies.id)

        #expect(try store.children(of: movies.id).map(\.title) == ["Dune", "Alien"])
        #expect(try store.children(of: nil).map(\.title) == ["Movies Watched"])
    }

    @Test func kindSpecificFields() throws {
        let item = try store.create(kind: .item, title: "Orbit", parentID: nil, view: .board, columnType: .todo)
        let plain = try store.create(kind: .item, title: "Ideas", parentID: nil)
        let note = try store.create(kind: .note, title: "Note", parentID: nil, status: .done, view: .board, columnType: .done)

        #expect(try store.node(id: item.id)?.view == .board)
        #expect(try store.node(id: item.id)?.columnType == .todo)
        #expect(try store.node(id: plain.id)?.view == .list)
        #expect(try store.node(id: plain.id)?.status == nil)
        #expect(try store.node(id: note.id)?.status == nil)
        #expect(try store.node(id: note.id)?.view == nil)
        #expect(try store.node(id: note.id)?.columnType == nil)
    }

    @Test func detailsAndDueRoundTrip() throws {
        var item = try store.create(
            kind: .item, title: "Village", parentID: nil,
            details: [NodeDetail(key: "x", value: "120"), NodeDetail(key: "z", value: "-300")]
        )
        #expect(try store.node(id: item.id)?.details.map(\.key) == ["x", "z"])

        let due = Date(timeIntervalSince1970: 2_000_000_000)
        item.dueAt = due
        item.estimateMinutes = 90
        item.details = []
        try store.update(item)

        let saved = try #require(try store.node(id: item.id))
        #expect(saved.dueAt == due)
        #expect(saved.estimateMinutes == 90)
        #expect(saved.details.isEmpty)
    }

    @Test func oldKindsStillLoad() {
        for old in ["page", "entry", "folder", "list", "item", "task"] {
            #expect(NodeKind(storedValue: old) == .item)
        }
        #expect(NodeKind(storedValue: "note") == .note)
    }

    @Test func moveReorders() throws {
        let list = try store.create(kind: .item, title: "L", parentID: nil)
        let a = try store.create(kind: .item, title: "A", parentID: list.id)
        try store.create(kind: .item, title: "B", parentID: list.id)
        try store.create(kind: .item, title: "C", parentID: list.id)

        try store.move(id: a.id, toIndex: 2)
        #expect(try store.children(of: list.id).map(\.title) == ["B", "C", "A"])

        try store.move(id: a.id, toIndex: 1)
        #expect(try store.children(of: list.id).map(\.title) == ["B", "A", "C"])
    }

    @Test func updateSavesAndBumpsTimestamp() throws {
        var task = try store.create(kind: .item, title: "Old", parentID: nil, status: .todo)
        let before = task.updatedAt
        task.title = "New"
        task.status = .doing
        try store.update(task)

        let saved = try #require(try store.node(id: task.id))
        #expect(saved.title == "New")
        #expect(saved.status == .doing)
        #expect(saved.updatedAt >= before)
    }

    @Test func deleteIsSoftAndRecursive() throws {
        let orbit = try store.create(kind: .item, title: "Orbit", parentID: nil)
        let frontend = try store.create(kind: .item, title: "Frontend", parentID: orbit.id)
        let task = try store.create(kind: .item, title: "Login", parentID: frontend.id, status: .todo)
        #expect(try store.descendants(of: orbit.id).count == 2)

        try store.delete(id: orbit.id)

        #expect(try store.node(id: orbit.id) == nil)
        #expect(try store.node(id: task.id) == nil)
        #expect(try store.children(of: nil).isEmpty)
    }

    // MARK: Boards

    /// Makes a board with Todo / Doing / Done columns and returns the columns by title.
    private func makeBoard(_ title: String, in parentID: UUID? = nil) throws -> (Node, [String: Node]) {
        let board = try store.create(kind: .item, title: title, parentID: parentID)
        model.setView(board, .board)
        let columns = Dictionary(uniqueKeysWithValues: model.columnItems(in: board).map { ($0.title, $0) })
        return (try #require(model.node(id: board.id)), columns)
    }

    @Test func emptyItemBecomesBoardWithDefaultColumns() throws {
        let (board, columns) = try makeBoard("Orbit")
        #expect(model.columns(for: board).map(\.title) == ["Todo", "Doing", "Done"])
        #expect(columns["Done"]?.columnType == .done)
    }

    @Test func boardCardsAreTheSameItemsAsTheList() throws {
        let (board, columns) = try makeBoard("Orbit")
        let todo = try #require(model.columns(for: board).first)
        model.addCard("hi", to: todo)

        // List view of the board: an item "Todo" with "hi" inside.
        #expect(model.children(of: board.id).map(\.title) == ["Todo", "Doing", "Done"])
        let hi = try #require(model.children(of: columns["Todo"]!.id).first)
        #expect(hi.title == "hi")
        #expect(hi.status == .todo)
    }

    @Test func sectionsMergeColumnsByTitle() throws {
        let (orbit, _) = try makeBoard("Orbit")
        // Remove Orbit's own columns so only sections remain.
        model.delete(model.columnItems(in: orbit).map(\.id))
        let (frontend, fe) = try makeBoard("Frontend", in: orbit.id)
        let (backend, be) = try makeBoard("Backend", in: orbit.id)
        try store.create(kind: .item, title: "Login", parentID: fe["Doing"]!.id, status: .doing)
        try store.create(kind: .item, title: "API", parentID: be["Doing"]!.id, status: .doing)

        let merged = model.columns(for: orbit)
        #expect(merged.map(\.title) == ["Todo", "Doing", "Done"])
        #expect(merged[1].cards.map(\.title).sorted() == ["API", "Login"])
        #expect(model.sections(of: orbit).map(\.id) == [frontend.id, backend.id])

        // Filter to one section.
        let onlyFrontend = model.columns(for: orbit, section: frontend)
        #expect(onlyFrontend[1].cards.map(\.title) == ["Login"])
    }

    @Test func dropStaysInSectionAndCreatesMissingColumn() throws {
        let (orbit, _) = try makeBoard("Orbit")
        model.delete(model.columnItems(in: orbit).map(\.id))
        let (frontend, fe) = try makeBoard("Frontend", in: orbit.id)
        let (_, _) = try makeBoard("Backend", in: orbit.id)
        // Backend gets an extra "Testing" column that Frontend lacks.
        let backend = try #require(model.sections(of: orbit).last)
        model.saveColumns(model.columnDrafts(in: backend) + [.init(id: nil, title: "Testing", type: .doing)], in: backend)

        let card = try store.create(kind: .item, title: "Login", parentID: fe["Todo"]!.id, status: .todo)
        let testing = try #require(model.columns(for: orbit).first { $0.title == "Testing" })
        model.drop(card, into: testing)

        let moved = try #require(model.node(id: card.id))
        let newColumn = try #require(moved.parentID.flatMap { model.node(id: $0) })
        #expect(newColumn.title == "Testing")
        #expect(newColumn.parentID == frontend.id) // stayed in Frontend
        #expect(moved.status == .doing)
    }

    @Test func tickingDoneMovesCardToDoneColumn() throws {
        let (_, columns) = try makeBoard("Orbit")
        let card = try store.create(kind: .item, title: "Ship", parentID: columns["Doing"]!.id, status: .doing)
        model.toggleDone(card)
        let saved = try #require(model.node(id: card.id))
        #expect(saved.status == .done)
        #expect(saved.parentID == columns["Done"]!.id)
    }

    @Test func neutralColumnRules() throws {
        #expect(ColumnRules.accepts(nil, .todo))
        #expect(ColumnRules.accepts(nil, .doing))
        #expect(!ColumnRules.accepts(nil, .done))
        #expect(ColumnRules.statusOnDrop(into: nil, from: .doing) == .doing)
        #expect(ColumnRules.statusOnDrop(into: nil, from: .done) == .todo)
        #expect(ColumnRules.statusOnDrop(into: .done, from: .todo) == .done)
    }

    @Test func removingColumnMovesItsCards() throws {
        let (board, columns) = try makeBoard("Orbit")
        let card = try store.create(kind: .item, title: "Ship", parentID: columns["Doing"]!.id, status: .doing)
        let drafts = model.columnDrafts(in: board).filter { $0.title != "Doing" }
        model.saveColumns(drafts, in: board)

        #expect(model.columnItems(in: board).map(\.title) == ["Todo", "Done"])
        let saved = try #require(model.node(id: card.id))
        #expect(saved.parentID == columns["Todo"]!.id)
        #expect(saved.status == .todo)
    }

    @Test func toggleDoneTurnsPlainItemIntoTask() throws {
        let line = try store.create(kind: .item, title: "Dune", parentID: nil)
        model.toggleDone(line)
        #expect(try store.node(id: line.id)?.status == .done)
    }
}
