import Foundation
import Supabase
import Testing
@testable import Vox

@MainActor
struct SyncTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeStores() throws -> (SwiftDataNodeStore, SwiftDataSyncStore, SwiftDataActionLogStore) {
        let container = try LocalDatabase.inMemory()
        return (SwiftDataNodeStore(container: container), SwiftDataSyncStore(container: container), SwiftDataActionLogStore(container: container))
    }

    @Test func everythingChangedHereGoesUpOnce() throws {
        let (nodes, sync, _) = try makeStores()
        let dune = try nodes.create(kind: .item, title: "Dune", parentID: nil)
        try nodes.delete(id: dune.id)
        let batch = try sync.unpushed()
        #expect(batch.nodes.map(\.id) == [dune.id])
        #expect(batch.nodes.first?.deleted == true)

        try sync.markPushed(batch)
        #expect(try sync.unpushed().isEmpty)
    }

    @Test func aChangeDuringUploadStaysMarked() throws {
        let (nodes, sync, _) = try makeStores()
        let dune = try nodes.create(kind: .item, title: "Dune", parentID: nil)
        let batch = try sync.unpushed()
        var renamed = dune
        renamed.title = "Dune Part Two"
        try nodes.update(renamed)

        try sync.markPushed(batch)
        #expect(try sync.unpushed().nodes.map(\.title) == ["Dune Part Two"])
    }

    @Test func newerRemoteWinsAndOlderRemoteLoses() throws {
        let (nodes, sync, _) = try makeStores()
        let local = try nodes.create(kind: .item, title: "Local", parentID: nil)
        var older = local
        older.title = "Older"
        older.updatedAt = local.updatedAt.addingTimeInterval(-60)
        #expect(try sync.merge(SyncBatch(nodes: [older])) == false)
        #expect(try nodes.node(id: local.id)?.title == "Local")

        var newer = local
        newer.title = "Newer"
        newer.updatedAt = local.updatedAt.addingTimeInterval(60)
        #expect(try sync.merge(SyncBatch(nodes: [newer])) == true)
        #expect(try nodes.node(id: local.id)?.title == "Newer")
        // Came from Supabase, so it doesn't go back up.
        #expect(try sync.unpushed().nodes.isEmpty)
    }

    @Test func newRemoteRowsArriveWithoutBouncingBack() throws {
        let (nodes, sync, _) = try makeStores()
        let remote = Node(kind: .item, title: "From the web", updatedAt: start)
        try sync.merge(SyncBatch(nodes: [remote]))
        #expect(try nodes.node(id: remote.id)?.title == "From the web")
        #expect(try sync.unpushed().isEmpty)
        #expect(try sync.merge(SyncBatch(nodes: [remote])) == false)
    }

    @Test func undoneOnEitherSideStaysUndone() throws {
        let (_, sync, log) = try makeStores()
        let entry = ActionLogEntry(transcript: "add Dune", actionsJSON: "[]", inverse: [], summary: "+ Dune")
        try log.append(entry)
        var remote = entry
        remote.undone = true
        try sync.merge(SyncBatch(log: [remote]))
        #expect(try log.entry(id: entry.id)?.undone == true)
        remote.undone = false
        #expect(try sync.merge(SyncBatch(log: [remote])) == false)
        #expect(try log.entry(id: entry.id)?.undone == true)
    }

    @Test func recordsRoundTripThroughJSON() throws {
        let owner = UUID()
        let node = Node(kind: .item, title: "Dune", status: .doing, details: [NodeDetail(key: "rating", value: "4")], dueAt: start, estimateMinutes: 30, createdAt: start, updatedAt: start)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(NodeRecord(node, owner: owner))
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"user_id\""))
        #expect(json.contains("\"estimate_minutes\":30"))
        let back = try decoder.decode(NodeRecord.self, from: data).node
        #expect(back.title == "Dune" && back.status == .doing && back.userID == owner)
        #expect(back.details == node.details)

        let reminder = Reminder(title: "Gym", fireAt: start, kind: .alarm, repeatRule: .weekly(2), updatedAt: start)
        let reminderBack = try decoder.decode(ReminderRecord.self, from: encoder.encode(ReminderRecord(reminder, owner: owner))).reminder
        #expect(reminderBack.repeatRule == .weekly(2) && reminderBack.kind == .alarm)

        let entry = ActionLogEntry(createdAt: start, transcript: "add Dune", actionsJSON: #"[{"type":"addItem","title":"Dune"}]"#, inverse: [.remove(node.id)], summary: "+ Dune")
        let record = ActionLogRecord(entry, owner: owner)
        #expect(record.actions != .array([]))
        let entryBack = try decoder.decode(ActionLogRecord.self, from: encoder.encode(record)).entry
        #expect(entryBack.inverse == entry.inverse)
        #expect(entryBack.actionsJSON.contains("addItem"))
    }
}
