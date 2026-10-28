import Foundation
import Observation
import Supabase

/// Keeps the phone and Supabase in step while signed in.
/// Uploads what changed here, then downloads what changed elsewhere. The newer change wins.
/// Runs when the app opens or comes back, a few seconds after a change, and on pull to refresh.
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSynced: Date?

    /// The signed in user. Nil stops syncing; everything stays on the phone.
    var userID: UUID? {
        didSet {
            lastSynced = userID.flatMap { UserDefaults.standard.object(forKey: Self.key("lastSynced", $0)) as? Date }
            if userID != oldValue { status = .idle }
        }
    }

    /// How long to wait after a change, so a burst of edits goes up together.
    static let delay: Duration = .seconds(3)
    /// Rows per request.
    static let pageSize = 500

    private let client: SupabaseClient?
    private let store: any SyncStore
    /// Called after a download changed something, so screens and notifications catch up.
    private let onPulled: () -> Void
    private var running = false
    private var again = false
    private var soonTask: Task<Void, Never>?
    private var observer: (any NSObjectProtocol)?

    init(client: SupabaseClient? = SupabaseConfig.client, store: any SyncStore, onPulled: @escaping () -> Void) {
        self.client = client
        self.store = store
        self.onPulled = onPulled
        observer = NotificationCenter.default.addObserver(forName: LocalChange.name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncSoon() }
        }
    }

    /// Waits a moment, then syncs. More changes in the meantime restart the wait.
    func syncSoon() {
        guard userID != nil else { return }
        soonTask?.cancel()
        soonTask = Task {
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    func syncNow() async {
        guard let client, let user = userID else { return }
        // One at a time. A request while running runs once more at the end.
        guard !running else {
            again = true
            return
        }
        running = true
        status = .syncing
        do {
            try await push(client, owner: user)
            if try await pull(client, user: user) { onPulled() }
            lastSynced = .now
            UserDefaults.standard.set(lastSynced, forKey: Self.key("lastSynced", user))
            status = .idle
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost].contains(error.code) {
            status = .offline
        } catch {
            status = .failed(error.localizedDescription)
        }
        running = false
        if again, userID == user {
            again = false
            await syncNow()
        }
    }

    // MARK: Upload

    private func push(_ client: SupabaseClient, owner: UUID) async throws {
        let all = try store.unpushed()
        // Rows of another account that used this phone before stay here. Supabase would refuse them.
        let batch = SyncBatch(
            nodes: all.nodes.filter { $0.userID == nil || $0.userID == owner },
            reminders: all.reminders.filter { $0.userID == nil || $0.userID == owner },
            log: all.log.filter { $0.userID == nil || $0.userID == owner }
        )
        guard !batch.isEmpty else { return }
        for chunk in batch.nodes.chunked(Self.pageSize) {
            try await client.from("nodes").upsert(chunk.map { NodeRecord($0, owner: owner) }, onConflict: "id", returning: .minimal).execute()
        }
        for chunk in batch.reminders.chunked(Self.pageSize) {
            try await client.from("reminders").upsert(chunk.map { ReminderRecord($0, owner: owner) }, onConflict: "id", returning: .minimal).execute()
        }
        for chunk in batch.log.chunked(Self.pageSize) {
            try await client.from("action_log").upsert(chunk.map { ActionLogRecord($0, owner: owner) }, onConflict: "id", returning: .minimal).execute()
        }
        try store.markPushed(batch)
    }

    // MARK: Download

    /// Everything changed since the last download, page by page. True if anything here changed.
    private func pull(_ client: SupabaseClient, user: UUID) async throws -> Bool {
        let nodes: [NodeRecord] = try await rows(client, table: "nodes", column: "updated_at", user: user)
        let reminders: [ReminderRecord] = try await rows(client, table: "reminders", column: "updated_at", user: user)
        let log: [ActionLogRecord] = try await rows(client, table: "action_log", column: "created_at", user: user)
        let batch = SyncBatch(nodes: nodes.map(\.node), reminders: reminders.map(\.reminder), log: log.map(\.entry))
        let changed = try store.merge(batch)
        // Move the bookmarks only once the rows are safely saved here.
        saveCursor(nodes.map(\.updatedAt).max(), table: "nodes", user: user)
        saveCursor(reminders.map(\.updatedAt).max(), table: "reminders", user: user)
        saveCursor(log.map(\.createdAt).max(), table: "action_log", user: user)
        return changed
    }

    private func rows<Row: Decodable>(_ client: SupabaseClient, table: String, column: String, user: UUID) async throws -> [Row] {
        let since = Self.timestamp(cursor(table: table, user: user))
        var all: [Row] = []
        while true {
            let page: [Row] = try await client.from(table)
                .select()
                .gte(column, value: since)
                .order(column)
                .order("id")
                .range(from: all.count, to: all.count + Self.pageSize - 1)
                .execute()
                .value
            all += page
            if page.count < Self.pageSize { return all }
        }
    }

    // MARK: Bookmarks

    /// The newest change already downloaded, per table and user. Nil downloads everything.
    private func cursor(table: String, user: UUID) -> Date? {
        UserDefaults.standard.object(forKey: Self.key("cursor.\(table)", user)) as? Date
    }

    private func saveCursor(_ date: Date?, table: String, user: UUID) {
        guard let date, date > (cursor(table: table, user: user) ?? .distantPast) else { return }
        UserDefaults.standard.set(date, forKey: Self.key("cursor.\(table)", user))
    }

    private static func key(_ name: String, _ user: UUID) -> String {
        "sync.\(name).\(user.uuidString)"
    }

    /// "2026-10-28T09:41:00.123Z". The same moment is downloaded again next time; merging it changes nothing.
    private static func timestamp(_ date: Date?) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date ?? Date(timeIntervalSince1970: 0))
    }
}

private extension Array {
    func chunked(_ size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
