import Foundation

/// Fixes small mistakes the fast model tends to make, before the plan is shown.
enum PlanRepair {
    /// Every repair, in order. Used for plans from Gemini, the fast path and Thinking.
    static func all(_ actions: [BrainAction], command: String, context: BrainContext) -> [BrainAction] {
        reuseExistingLists(itemsIntoNewList(statusFromWords(actions, command: command)), context: context)
    }

    /// "I started the EN project" or "I finished the EN project", but the plan sets no status:
    /// gives the thing it makes or changes that status. Plans that already set a status are left alone.
    static func statusFromWords(_ actions: [BrainAction], command: String) -> [BrainAction] {
        guard let status = spokenStatus(in: command),
              !actions.contains(where: { $0.status != nil || $0.type == .setStatus }) else { return actions }
        var actions = actions
        // The first thing made is what the user is talking about. Lists made just to hold it come before it.
        if let index = actions.firstIndex(where: { $0.type == .addItem }) {
            actions[index].status = StatusChoice(rawValue: status.rawValue)
        } else if let index = actions.firstIndex(where: { $0.type == .createNode && $0.kind != .note }) {
            // A list or board can't take a status in createNode, so it gets one at the end. Appending keeps #refs right.
            actions.append(BrainAction(type: .setStatus, target: "#\(index + 1)", status: StatusChoice(rawValue: status.rawValue)))
        } else if let index = actions.firstIndex(where: { [.renameNode, .setDetail, .setDue, .moveNode].contains($0.type) }),
                  let target = actions[index].target {
            actions.append(BrainAction(type: .setStatus, target: target, status: StatusChoice(rawValue: status.rawValue)))
        }
        return actions
    }

    /// doing for "started" or "working on", done for "finished" or "done with". Nil when neither, or both.
    /// Nil for "finished watching Dune": that is a movie to log, not a task.
    static func spokenStatus(in command: String) -> TaskStatus? {
        let text = " " + command.lowercased().split { !$0.isLetter && $0 != "'" }.joined(separator: " ") + " "
        let media = [" watching ", " reading ", " listening ", " playing "]
        if media.contains(where: { text.contains($0) }) { return nil }
        let doing = [" started ", " starting ", " began ", " begun ", " working on ", " in progress ", " i'm doing ", " i am doing "]
        let done = [" finished ", " completed ", " done with ", " i'm done ", " i am done ", " wrapped up ", " is done ", " are done "]
        let saysDoing = doing.contains { text.contains($0) }
        let saysDone = done.contains { text.contains($0) }
        if saysDoing == saysDone { return nil }
        return saysDoing ? .doing : .done
    }

    /// When a plan makes a new list and then adds an item to the top level, the item was meant for the new list.
    /// Example: "I watched Dune today" -> create Movies Watched, add Dune to top. Dune goes into #1 instead.
    static func itemsIntoNewList(_ actions: [BrainAction]) -> [BrainAction] {
        var newList: Int?
        return actions.enumerated().map { index, action in
            var action = action
            switch action.type {
            case .createNode where action.kind != .note:
                newList = index + 1
            case .addItem where isTop(action.parent):
                if let newList { action.parent = "#\(newList)" }
            default:
                break
            }
            return action
        }
    }

    /// When a plan makes a list that already exists by name in the same place, uses the existing one instead.
    /// Works at the top level and inside any existing item, like the open folder.
    /// "Movies Watched" also matches "Watched Movies" or "movie watched". Later #refs are renumbered.
    static func reuseExistingLists(_ actions: [BrainAction], context: BrainContext) -> [BrainAction] {
        let visible = Set(context.allNodes().map(\.id))
        /// Lists already in the place a ref points to. Empty for a list made in this same plan (#1).
        func existing(in ref: String?) -> [Node] {
            let parentID: UUID?
            if isTop(ref) {
                parentID = nil
            } else if let ref, !ref.hasPrefix("#"), let id = context.id(forHandle: ref) ?? UUID(uuidString: ref) {
                parentID = id
            } else {
                return []
            }
            return ((try? context.store.children(of: parentID)) ?? []).filter { $0.kind == .item && visible.contains($0.id) }
        }
        var kept: [BrainAction] = []
        // Old action number (1 based) -> the ref to use for it now.
        var refs: [Int: String] = [:]
        for (index, original) in actions.enumerated() {
            var action = original
            action.target = renumber(action.target, refs)
            action.parent = renumber(action.parent, refs)
            if action.type == .createNode, action.kind != .note,
               let title = action.title,
               let match = existing(in: action.parent).first(where: { sameName($0.title, title) }) {
                refs[index + 1] = context.handle(for: match)
                continue
            }
            kept.append(action)
            refs[index + 1] = "#\(kept.count)"
        }
        return kept
    }

    private static func renumber(_ ref: String?, _ refs: [Int: String]) -> String? {
        guard let ref, ref.hasPrefix("#"), let number = Int(ref.dropFirst()) else { return ref }
        return refs[number] ?? ref
    }

    /// Same words once filler words and endings are dropped, in any order.
    private static func sameName(_ a: String, _ b: String) -> Bool {
        let words = Set(NodeSearch.words(a))
        return !words.isEmpty && words == Set(NodeSearch.words(b))
    }

    private static func isTop(_ ref: String?) -> Bool {
        let ref = ref?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return ref.isEmpty || ["top", "root", "none", "null"].contains(ref)
    }
}
