import Foundation

/// Said every time something is saved on this phone, so sync can upload it soon.
/// Changes that came from sync itself don't say it, so they don't bounce back.
enum LocalChange {
    static let name = Notification.Name("vox.localChange")

    static func post() {
        NotificationCenter.default.post(name: name, object: nil)
    }
}
