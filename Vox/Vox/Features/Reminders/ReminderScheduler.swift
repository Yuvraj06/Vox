import AlarmKit
import Foundation
import SwiftUI
import UserNotifications

/// Puts reminders and alarms on the system clock, and takes them off again.
protocol ReminderScheduling {
    /// Asks for permission the first time. Throws when the user said no.
    func schedule(_ reminder: Reminder) async throws
    func cancel(id: UUID) async
}

/// Reminders are local notifications. Alarms go through AlarmKit, so they ring even on silent.
final class SystemReminderScheduler: NSObject, ReminderScheduling, UNUserNotificationCenterDelegate {
    enum Failure: Error, LocalizedError {
        case notificationsOff
        case alarmsOff

        var errorDescription: String? {
            switch self {
            case .notificationsOff: "Notifications are off for Vox. Turn them on in Settings > Notifications > Vox."
            case .alarmsOff: "Alarms are off for Vox. Turn them on in Settings > Apps > Vox."
            }
        }
    }

    /// Nothing extra to carry on the alarm.
    struct AlarmInfo: AlarmMetadata {}

    private let notifications = UNUserNotificationCenter.current()

    override init() {
        super.init()
        // Without this, reminders don't show while the app is open.
        notifications.delegate = self
    }

    func schedule(_ reminder: Reminder) async throws {
        await cancel(id: reminder.id)
        switch reminder.kind {
        case .reminder: try await scheduleNotification(reminder)
        case .alarm: try await scheduleAlarm(reminder)
        }
    }

    func cancel(id: UUID) async {
        notifications.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        try? AlarmManager.shared.cancel(id: id)
    }

    // MARK: Notifications

    private func scheduleNotification(_ reminder: Reminder) async throws {
        guard try await notifications.requestAuthorization(options: [.alert, .sound, .badge]) else {
            throw Failure.notificationsOff
        }
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.sound = .default
        content.userInfo = ["reminderID": reminder.id.uuidString]

        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = switch reminder.repeatRule {
        case nil: [.year, .month, .day, .hour, .minute]
        case .daily: [.hour, .minute]
        case .weekly: [.weekday, .hour, .minute]
        }
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(parts, from: reminder.fireAt),
            repeats: reminder.repeatRule != nil
        )
        try await notifications.add(UNNotificationRequest(identifier: reminder.id.uuidString, content: content, trigger: trigger))
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // MARK: Alarms

    private func scheduleAlarm(_ reminder: Reminder) async throws {
        let manager = AlarmManager.shared
        let state = manager.authorizationState == .notDetermined
            ? try await manager.requestAuthorization()
            : manager.authorizationState
        guard state == .authorized else { throw Failure.alarmsOff }

        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: reminder.title),
            stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        )
        let attributes = AlarmAttributes<AlarmInfo>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: TaskStatus.doing.tint
        )
        _ = try await manager.schedule(
            id: reminder.id,
            configuration: .alarm(schedule: Self.alarmSchedule(for: reminder), attributes: attributes)
        )
    }

    private static func alarmSchedule(for reminder: Reminder) -> Alarm.Schedule {
        let time = Calendar.current.dateComponents([.hour, .minute], from: reminder.fireAt)
        let clock = Alarm.Schedule.Relative.Time(hour: time.hour ?? 0, minute: time.minute ?? 0)
        switch reminder.repeatRule {
        case nil:
            return .fixed(reminder.fireAt)
        case .daily:
            return .relative(.init(time: clock, repeats: .weekly(Locale.Weekday.allCases)))
        case .weekly(let weekday):
            let day = Locale.Weekday.allCases.first { $0.calendarWeekday == weekday } ?? .monday
            return .relative(.init(time: clock, repeats: .weekly([day])))
        }
    }
}

private extension Locale.Weekday {
    static let allCases: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]

    /// 1 for Sunday ... 7 for Saturday, like `Calendar`.
    var calendarWeekday: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/// For previews and tests: remembers what it was asked, touches nothing.
final class FakeReminderScheduler: ReminderScheduling {
    private(set) var scheduled: Set<UUID> = []

    func schedule(_ reminder: Reminder) async throws { scheduled.insert(reminder.id) }
    func cancel(id: UUID) async { scheduled.remove(id) }
}
