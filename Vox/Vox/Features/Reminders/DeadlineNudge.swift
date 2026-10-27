import Foundation

/// A notification before an item's deadline. Bigger estimates start earlier,
/// and the nudges come closer together as the deadline nears.
struct DeadlineNudge: Equatable {
    /// Every nudge's notification id starts with this, so they can be swapped out together.
    static let idPrefix = "nudge-"
    /// Without an estimate, a task counts as 30 minutes.
    static let defaultEstimate = 30
    /// Where in the window the nudges go: the start, halfway, a quarter left, and the deadline itself.
    private static let steps: [Double] = [1, 0.5, 0.25, 0]

    let nodeID: UUID
    let title: String
    let fireAt: Date
    /// How long before the deadline it goes off. Zero is at the deadline.
    let lead: TimeInterval

    var id: String { "\(Self.idPrefix)\(nodeID.uuidString)-\(Int(lead))" }

    /// "Due in 2 hours", or "Due now" at the deadline.
    var body: String {
        guard lead > 0 else { return "Due now" }
        let left = Duration.seconds(lead).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2))
        return "Due in \(left)"
    }

    /// How long before the deadline the nudges start: 4 times the estimate.
    /// 2 hours for a 30 minute task, the day before for a 5 hour one. Never less than 2 hours, never more than 2 days.
    static func window(estimateMinutes: Int?) -> TimeInterval {
        let estimate = TimeInterval(estimateMinutes ?? defaultEstimate) * 60
        return min(max(estimate * 4, 2 * 3600), 2 * 86_400)
    }

    /// The nudges still to come for one item. None once it is done or the deadline passed.
    static func nudges(for node: Node, now: Date = .now) -> [DeadlineNudge] {
        guard let due = node.dueAt, due > now, node.status != .done, !node.deleted else { return [] }
        let window = window(estimateMinutes: node.estimateMinutes)
        return steps
            .map { step in
                let lead = window * step
                return DeadlineNudge(nodeID: node.id, title: node.title, fireAt: due.addingTimeInterval(-lead), lead: lead)
            }
            .filter { $0.fireAt > now }
    }
}
