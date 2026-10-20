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
        let list = try store.create(kind: .list, title: "Movies Watched", parentID: nil)
        try store.create(kind: .item, title: "Dune", parentID: list.id)
        try store.create(kind: .item, title: "Alien", parentID: list.id)

        let titles = try store.children(of: list.id).map(\.title)
        #expect(titles == ["Dune", "Alien"])
        #expect(try store.children(of: nil).map(\.title) == ["Movies Watched"])
    }

    @Test func kindSpecificFields() throws {
        let folder = try store.create(kind: .folder, title: "Orbit", parentID: nil, view: .board)
        let task = try store.create(kind: .task, title: "Build UI", parentID: folder.id)
        let item = try store.create(kind: .item, title: "Dune", parentID: folder.id, status: .done)

        #expect(try store.node(id: folder.id)?.view == .board)
        #expect(try store.node(id: task.id)?.status == .todo)
        #expect(try store.node(id: item.id)?.status == nil)
    }

    @Test func moveReorders() throws {
        let list = try store.create(kind: .list, title: "L", parentID: nil)
        let a = try store.create(kind: .item, title: "A", parentID: list.id)
        try store.create(kind: .item, title: "B", parentID: list.id)
        try store.create(kind: .item, title: "C", parentID: list.id)

        try store.move(id: a.id, toIndex: 2)
        #expect(try store.children(of: list.id).map(\.title) == ["B", "C", "A"])

        try store.move(id: a.id, toIndex: 1)
        #expect(try store.children(of: list.id).map(\.title) == ["B", "A", "C"])
    }

    @Test func updateSavesAndBumpsTimestamp() throws {
        var task = try store.create(kind: .task, title: "Old", parentID: nil)
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
        let orbit = try store.create(kind: .folder, title: "Orbit", parentID: nil)
        let frontend = try store.create(kind: .folder, title: "Frontend", parentID: orbit.id)
        let task = try store.create(kind: .task, title: "Login", parentID: frontend.id)
        #expect(try store.descendants(of: orbit.id).count == 2)

        try store.delete(id: orbit.id)

        #expect(try store.node(id: orbit.id) == nil)
        #expect(try store.node(id: task.id) == nil)
        #expect(try store.children(of: nil).isEmpty)
    }
}
