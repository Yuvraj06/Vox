import Foundation
import FoundationModels

/// What the model can see during one command. Gives nodes short ids (n1, n2, ...)
/// so the model never has to copy long UUIDs.
final class BrainContext {
    let store: any NodeStore
    private var handles: [String: UUID] = [:]
    private var handleOf: [UUID: String] = [:]
    /// Tool calls made so far, so a stuck model can be told to stop searching.
    private var toolCalls: [String] = []
    static let maxToolCalls = 5
    static let stopMessage = "Stop calling tools. Return the actions now."
    /// Nodes to leave out, like the ones a just applied fast plan made, so a second look doesn't see them.
    var hidden: Set<UUID> = []
    /// Called with a short line for each tool call, like: Searching "movies watched". Shown in the Thinking tab.
    var onStep: ((String) -> Void)?
    /// The open folder, list or note, so the model knows where you are. It still sees the whole tree. Nil on the home screen.
    let scope: UUID?
    /// Where voice reminders and alarms are saved. Nil means reminders can't be made.
    var reminders: (any ReminderStore)?

    init(store: any NodeStore, scope: UUID? = nil) {
        self.store = store
        self.scope = scope
    }

    /// The open node, if there is one.
    var scopeNode: Node? { scope.flatMap { try? store.node(id: $0) } }

    /// Tells the model where you are, like: Open screen: n4 "Movies" list, in Media. Nil on the home screen.
    /// Only a hint: new things go there when they fit it, otherwise into the list they belong in.
    func hereLine() -> String? {
        guard let node = scopeNode else { return nil }
        let handle = handle(for: node)
        let place = node.kind == .item
            ? handle
            : node.parentID.flatMap { try? store.node(id: $0) }.map { self.handle(for: $0) } ?? "top"
        return "Open screen: \(describe(node)). \"This\" and \"here\" mean \(handle)."
            + " Put a new thing in \(place) only when it fits there, like a task on a project board or a movie in a movies list."
            + " If it belongs in another list that already exists, like a movie in Movies Watched, put it there instead."
    }

    /// Records a tool call. Returns a stop message when the call is a repeat or over the limit.
    func checkToolBudget(_ call: String) -> String? {
        defer { toolCalls.append(call) }
        if toolCalls.contains(call) || toolCalls.count >= Self.maxToolCalls { return Self.stopMessage }
        return nil
    }

    func id(forHandle handle: String) -> UUID? {
        handles[handle.lowercased()]
    }

    func handle(for node: Node) -> String {
        if let existing = handleOf[node.id] { return existing }
        let handle = "n\(handles.count + 1)"
        handles[handle] = node.id
        handleOf[node.id] = handle
        return handle
    }

    // MARK: Reads used by the tools

    /// Every node in the tree, top level first.
    func allNodes() -> [Node] {
        let top = (try? store.children(of: nil)) ?? []
        let below = top.flatMap { (try? store.descendants(of: $0.id)) ?? [] }
        let all = top + below
        return hidden.isEmpty ? all : all.filter { !hidden.contains($0.id) }
    }

    /// Nodes whose titles appear in the command, best first. Board columns (Todo, Doing, Done) are left out,
    /// so "add a todo" doesn't match every board's Todo column. Runs in Swift, in milliseconds.
    func candidates(for text: String, limit: Int = 6) -> [Node] {
        let nodes = allNodes()
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let isColumn: (Node) -> Bool = { node in
            node.kind == .item && !node.isBoard && node.status == nil
                && node.parentID.flatMap { byID[$0] }?.isBoard == true
        }
        return NodeSearch.mentioned(in: text, among: nodes.filter { !isColumn($0) }, ancestors: ancestorTitles(of:))
            .prefix(limit)
            .map { $0 }
    }

    /// Titles from the top level down to the node's parent, like ["Orbit", "Frontend"].
    func ancestorTitles(of node: Node) -> [String] {
        var titles: [String] = []
        var parentID = node.parentID
        while let id = parentID, let parent = try? store.node(id: id) {
            titles.insert(parent.title, at: 0)
            parentID = parent.parentID
        }
        return titles
    }

    /// One line the model can read, like: n4 "Backend" board, in Orbit
    func describe(_ node: Node) -> String {
        var parts = ["\(handle(for: node)) \"\(node.title)\""]
        if node.kind == .note {
            parts.append("note")
        } else if let status = node.status {
            parts.append("task \(status.rawValue)")
        } else if let view = node.view {
            parts.append(view.rawValue)
        }
        let ancestors = ancestorTitles(of: node)
        let place = ancestors.isEmpty ? "in top" : "in \(ancestors.joined(separator: "/"))"
        return parts.joined(separator: " ") + ", " + place
    }

    /// Every title as an indented outline, like "n1 Movies Watched (list)". For Gemini, which has room for all of it.
    /// The open screen is marked. Only titles: note text is never included. Stops after `limit` lines.
    func outline(limit: Int = 800) -> String {
        var lines: [String] = []
        func walk(_ parentID: UUID?, depth: Int, insideBoard: Bool) {
            for node in (try? store.children(of: parentID)) ?? [] where !hidden.contains(node.id) {
                guard lines.count < limit else { return }
                let isColumn = insideBoard && node.kind == .item && !node.isBoard && node.status == nil
                let what: String? = if node.kind == .note { "note" }
                    else if let status = node.status { "task \(status.rawValue)" }
                    else if isColumn { "column" }
                    else { node.view?.rawValue }
                let indent = String(repeating: "  ", count: depth)
                let marks = [what, node.id == scope ? "open screen" : nil].compactMap { $0 }
                lines.append(indent + "\(handle(for: node)) \(node.title)" + (marks.isEmpty ? "" : " (\(marks.joined(separator: ", ")))"))
                if node.kind == .item { walk(node.id, depth: depth + 1, insideBoard: node.isBoard) }
            }
        }
        walk(nil, depth: 0, insideBoard: false)
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }

    /// Lists, boards and folders that aren't in `excluding`, so the model knows the main lists even when the command
    /// doesn't name one ("Avengers Endgame, 10/10" belongs in Movies Watched). Lists inside the open item come first.
    func topLists(excluding: [Node], limit: Int = 6) -> [Node] {
        let taken = Set(excluding.map(\.id))
        // A few from inside the open item, so a big folder doesn't push out the main lists like Movies Watched.
        let fits: (Node) -> Bool = { $0.kind == .item && !$0.isTask && !taken.contains($0.id) && !self.hidden.contains($0.id) && $0.id != self.scope }
        let inside = scopeNode?.kind == .item ? ((try? store.children(of: scope)) ?? []).filter(fits).prefix(3).map { $0 } : []
        let top = ((try? store.children(of: nil)) ?? []).filter(fits)
        return (inside + top).prefix(limit).map { $0 }
    }

    func findNodes(_ query: String) -> String {
        if let stop = checkToolBudget("findNodes \(NodeSearch.words(query).sorted())") { return stop }
        onStep?("Searching \"\(query)\"")
        let matches = NodeSearch.rank(query: query, in: allNodes(), ancestors: ancestorTitles(of:))
        onStep?(matches.first.map { "Found \($0.title)" + (matches.count > 1 ? " and \(matches.count - 1) more" : "") } ?? "Nothing called \"\(query)\"")
        guard !matches.isEmpty else { return "No match for \"\(query)\"." }
        return matches.prefix(5).map(describe).joined(separator: "\n")
    }

    func currentDate() -> String {
        if let stop = checkToolBudget("getCurrentDate") { return stop }
        return Date.now.formatted(date: .complete, time: .shortened)
    }

    func listChildren(_ handle: String) -> String {
        if let stop = checkToolBudget("listChildren \(handle.lowercased())") { return stop }
        guard let id = id(forHandle: handle), let node = try? store.node(id: id) else {
            return "Unknown id \(handle). Use an id from findNodes."
        }
        onStep?("Looking inside \(node.title)")
        let kids = ((try? store.children(of: node.id)) ?? []).filter { !hidden.contains($0.id) }
        guard !kids.isEmpty else { return "\"\(node.title)\" is empty." }
        return kids.prefix(12).map(describe).joined(separator: "\n")
    }
}

/// Fuzzy title search. "movies i watched" finds "Movies Watched", "orbit backend" finds Backend inside Orbit.
enum NodeSearch {
    private static let ignored: Set<String> = [
        "the", "a", "an", "my", "i", "to", "of", "for", "in", "on", "list", "page", "project", "called", "named", "me",
    ]

    /// Lowercase word stems, without filler words.
    static func words(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !ignored.contains($0) }
            .map { stem($0) }
    }

    static func stem(_ word: String) -> String {
        for suffix in ["ing", "ed", "es", "s"] where word.count > suffix.count + 2 && word.hasSuffix(suffix) {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    /// Best matches first. A node must match at least one word of its own title.
    static func rank(query: String, in nodes: [Node], ancestors: (Node) -> [String]) -> [Node] {
        let queryWords = Set(words(query))
        guard !queryWords.isEmpty else { return [] }
        let scored: [(node: Node, score: Double)] = nodes.compactMap { node in
            let titleWords = Set(words(node.title))
            let titleHits = queryWords.filter { word in titleWords.contains { similar(word, $0) } }
            guard !titleHits.isEmpty, !titleWords.isEmpty else { return nil }
            let pathWords = Set(ancestors(node).flatMap { words($0) })
            let pathHits = queryWords.subtracting(titleHits).filter { word in pathWords.contains { similar(word, $0) } }
            let coverage = (Double(titleHits.count) + 0.8 * Double(pathHits.count)) / Double(queryWords.count)
            let fit = Double(titleHits.count) / Double(titleWords.count)
            return (node, 0.7 * coverage + 0.3 * fit)
        }
        return scored
            .filter { $0.score >= 0.35 }
            .sorted { $0.score > $1.score }
            .map(\.node)
    }

    /// Nodes whose title words show up in a whole sentence, best first.
    /// Unlike `rank`, a long command doesn't water down the score: what counts is how much of each title was said.
    static func mentioned(in text: String, among nodes: [Node], ancestors: (Node) -> [String]) -> [Node] {
        let said = Set(words(text))
        guard !said.isEmpty else { return [] }
        let scored: [(node: Node, score: Double)] = nodes.compactMap { node in
            let titleWords = Set(words(node.title))
            guard !titleWords.isEmpty else { return nil }
            let hits = titleWords.filter { word in said.contains { similar(word, $0) } }
            let fit = Double(hits.count) / Double(titleWords.count)
            guard fit >= 0.5 else { return nil }
            let pathWords = Set(ancestors(node).flatMap { words($0) })
            let pathHits = pathWords.filter { word in said.contains { similar(word, $0) } }
            return (node, fit + 0.1 * Double(hits.count) + 0.05 * Double(pathHits.count))
        }
        return scored.sorted { $0.score > $1.score }.map(\.node)
    }

    /// Same word, a prefix of 3+ letters, or one typo in a longer word.
    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        if min(a.count, b.count) >= 3, a.hasPrefix(b) || b.hasPrefix(a) { return true }
        return min(a.count, b.count) >= 5 && editDistance(a, b) <= 1
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...a.count {
            var previous = row[0]
            row[0] = i
            for j in 1...b.count {
                let saved = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, previous + (a[i - 1] == b[j - 1] ? 0 : 1))
                previous = saved
            }
        }
        return row[b.count]
    }
}

// MARK: Tools

nonisolated struct FindNodesTool: Tool {
    let context: BrainContext
    let name = "findNodes"
    let description = "Finds notes, lists, boards and items by title. Returns ids like n3."

    @Generable
    struct Arguments {
        @Guide(description: "Words from the title, like movies watched")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        await context.findNodes(arguments.query)
    }
}

nonisolated struct ListChildrenTool: Tool {
    let context: BrainContext
    let name = "listChildren"
    let description = "Lists what is inside a node, like the columns of a board."

    @Generable
    struct Arguments {
        @Guide(description: "An id from findNodes, like n3")
        var nodeId: String
    }

    func call(arguments: Arguments) async throws -> String {
        await context.listChildren(arguments.nodeId)
    }
}

nonisolated struct CurrentDateTool: Tool {
    let context: BrainContext
    let name = "getCurrentDate"
    let description = "Today's date and time."

    @Generable
    struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        await context.currentDate()
    }
}
