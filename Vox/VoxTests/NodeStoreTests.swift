import Foundation
import Testing
@testable import Vox

@MainActor
struct NodeStoreTests {
    let store: SwiftDataNodeStore

    init() throws {
        store = try .inMemory()
    }

    @Test func positionMath() {
        #expect(NodeOrdering.position(between: nil, and: nil) == 1)
        #expect(NodeOrdering.position(between: 1, and: 2) == 1.5)
        #expect(NodeOrdering.position(between: 3, and: nil) == 4)
        #expect(NodeOrdering.position(between: nil, and: 1) == 0)
    }

    @Test func createAppendsInOrder() throws {
        let movies = try store.create(kind: .page, title: "Movies Watched", parentID: nil)
        try store.create(kind: .entry, title: "Dune", parentID: movies.id)
        try store.create(kind: .entry, title: "Alien", parentID: movies.id)

        let titles = try store.children(of: movies.id).map(\.title)
        #expect(titles == ["Dune", "Alien"])
        #expect(try store.children(of: nil).map(\.title) == ["Movies Watched"])
    }

    @Test func kindSpecificFields() throws {
        let page = try store.create(kind: .page, title: "Orbit", parentID: nil, view: .board)
        let plainPage = try store.create(kind: .page, title: "Ideas", parentID: nil)
        let task = try store.create(kind: .entry, title: "Build UI", parentID: page.id, status: .todo)
        let line = try store.create(kind: .entry, title: "Dune", parentID: page.id)
        let note = try store.create(kind: .note, title: "Note", parentID: nil, status: .done, view: .board)

        #expect(try store.node(id: page.id)?.view == .board)
        #expect(try store.node(id: plainPage.id)?.view == .list)
        #expect(try store.node(id: task.id)?.status == .todo)
        #expect(try store.node(id: line.id)?.status == nil)
        #expect(try store.node(id: note.id)?.status == nil)
        #expect(try store.node(id: note.id)?.view == nil)
    }

    @Test func detailsAndDueRoundTrip() throws {
        var entry = try store.create(
            kind: .entry, title: "Village", parentID: nil,
            details: [NodeDetail(key: "x", value: "120"), NodeDetail(key: "z", value: "-300")]
        )
        #expect(try store.node(id: entry.id)?.details.map(\.key) == ["x", "z"])

        let due = Date(timeIntervalSince1970: 2_000_000_000)
        entry.dueAt = due
        entry.estimateMinutes = 90
        entry.details = []
        try store.update(entry)

        let saved = try #require(try store.node(id: entry.id))
        #expect(saved.dueAt == due)
        #expect(saved.estimateMinutes == 90)
        #expect(saved.details.isEmpty)
    }

    @Test func oldKindsStillLoad() {
        #expect(NodeKind(storedValue: "folder") == .page)
        #expect(NodeKind(storedValue: "list") == .page)
        #expect(NodeKind(storedValue: "item") == .entry)
        #expect(NodeKind(storedValue: "task") == .entry)
        #expect(NodeKind(storedValue: "note") == .note)
    }

    @Test func moveReorders() throws {
        let page = try store.create(kind: .page, title: "L", parentID: nil)
        let a = try store.create(kind: .entry, title: "A", parentID: page.id)
        try store.create(kind: .entry, title: "B", parentID: page.id)
        try store.create(kind: .entry, title: "C", parentID: page.id)

        try store.move(id: a.id, toIndex: 2)
        #expect(try store.children(of: page.id).map(\.title) == ["B", "C", "A"])

        try store.move(id: a.id, toIndex: 1)
        #expect(try store.children(of: page.id).map(\.title) == ["B", "A", "C"])
    }

    @Test func updateSavesAndBumpsTimestamp() throws {
        var task = try store.create(kind: .entry, title: "Old", parentID: nil, status: .todo)
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
        let orbit = try store.create(kind: .page, title: "Orbit", parentID: nil)
        let frontend = try store.create(kind: .page, title: "Frontend", parentID: orbit.id)
        let task = try store.create(kind: .entry, title: "Login", parentID: frontend.id, status: .todo)
        #expect(try store.descendants(of: orbit.id).count == 2)

        try store.delete(id: orbit.id)

        #expect(try store.node(id: orbit.id) == nil)
        #expect(try store.node(id: task.id) == nil)
        #expect(try store.children(of: nil).isEmpty)
    }

    @Test func boardShowsTasksFromSubPagesButNotSubEntries() throws {
        let model = NotesModel(store: store)
        let orbit = try store.create(kind: .page, title: "Orbit", parentID: nil, view: .board)
        let frontend = try store.create(kind: .page, title: "Frontend", parentID: orbit.id)
        let login = try store.create(kind: .entry, title: "Login", parentID: frontend.id, status: .doing)
        try store.create(kind: .entry, title: "Email field", parentID: login.id, status: .done)
        try store.create(kind: .entry, title: "Password field", parentID: login.id, status: .todo)
        try store.create(kind: .entry, title: "Plain line", parentID: orbit.id)
        try store.create(kind: .entry, title: "Deploy", parentID: orbit.id, status: .todo)

        let cards = model.boardEntries(under: orbit.id).map(\.title).sorted()
        #expect(cards == ["Deploy", "Login"])
        #expect(model.progress(of: login.id)?.done == 1)
        #expect(model.progress(of: login.id)?.total == 2)
    }

    @Test func toggleDoneTurnsPlainEntryIntoTask() throws {
        let model = NotesModel(store: store)
        let line = try store.create(kind: .entry, title: "Dune", parentID: nil)
        model.toggleDone(line)
        #expect(try store.node(id: line.id)?.status == .done)
    }
}
