import Foundation
import UserNotifications

/// Development fallback backend that works on the simulator and without the paid
/// Developer Program. It uses local notifications — which do NOT ring through
/// Silent/Focus and can't trap the user — so it's only for iterating on the
/// challenge flow before the AlarmKit path is wired on a real device (plan §4).
final class LocalNotificationScheduler: AlarmScheduling {
    static let challengeCategoryID = "PUSHUP_CHALLENGE"
    static let doPushupsActionID = "DO_PUSHUPS"
    static let alarmIDKey = "alarmID"

    private var center: UNUserNotificationCenter { .current() }

    /// Registers the notification action that deep-links into the challenge.
    func registerCategories() {
        let action = UNNotificationAction(
            identifier: Self.doPushupsActionID,
            title: "Do Pushups",
            options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.challengeCategoryID,
            actions: [action],
            intentIdentifiers: [],
            options: [.customDismissAction])
        center.setNotificationCategories([category])
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(_ request: ScheduledAlarmRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.label
        content.body = "Time to wake up — \(request.repTarget) pushups."
        content.sound = .defaultCritical
        content.categoryIdentifier = Self.challengeCategoryID
        content.userInfo = [Self.alarmIDKey: request.id.uuidString]

        for trigger in triggers(for: request) {
            let id = identifier(for: request.id, weekday: trigger.weekday)
            let notification = UNNotificationRequest(
                identifier: id, content: content, trigger: trigger.trigger)
            try await center.add(notification)
        }
    }

    func cancel(id: UUID) async {
        let prefix = id.uuidString
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func stop(id: UUID) async {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
    }

    // MARK: - Helpers

    private struct WeekdayTrigger { var weekday: Int?; var trigger: UNCalendarNotificationTrigger }

    private func triggers(for request: ScheduledAlarmRequest) -> [WeekdayTrigger] {
        if request.weekdays.isEmpty {
            var comps = DateComponents()
            comps.hour = request.hour
            comps.minute = request.minute
            return [WeekdayTrigger(weekday: nil,
                                   trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))]
        }
        return request.weekdays.map { weekday in
            var comps = DateComponents()
            comps.weekday = weekday
            comps.hour = request.hour
            comps.minute = request.minute
            return WeekdayTrigger(weekday: weekday,
                                  trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: true))
        }
    }

    private func identifier(for id: UUID, weekday: Int?) -> String {
        weekday.map { "\(id.uuidString)-\($0)" } ?? id.uuidString
    }
}
