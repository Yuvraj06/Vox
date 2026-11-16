import Foundation

/// A screen the navigation stack can push.
enum Route: Hashable {
    case node(Node)
    case allNotes
    case allReminders
    case history
    case account
    case settings
}
