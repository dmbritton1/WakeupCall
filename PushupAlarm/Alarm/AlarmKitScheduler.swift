import Foundation
import AlarmKit
import AppIntents
import SwiftUI

/// Custom metadata attached to every alarm, surfaced to the Live Activity UI.
struct PushupAlarmMetadata: AlarmMetadata {
    var alarmID: String
    var repTarget: Int

    init(alarmID: String, repTarget: Int) {
        self.alarmID = alarmID
        self.repTarget = repTarget
    }
}

/// Production alarm backend built on **AlarmKit** — the only API that rings
/// through Silent/Focus with a Lock Screen + Dynamic Island presentation
/// (plan §4). Requires a physical iOS 26 device and the paid Developer Program
/// (for the App Group used by `OpenChallengeIntent`).
///
/// ⚠️ Churn caveat (plan §4.2): AlarmKit's button-launch mechanism and Stop
/// behavior shifted across iOS 26.0 → 26.1. Treat this as the shape; verify
/// exact signatures on the current OS build and re-test on each iOS update.
final class AlarmKitScheduler: AlarmScheduling {
    func requestAuthorization() async -> Bool {
        do {
            return try await AlarmManager.shared.requestAuthorization() == .authorized
        } catch {
            return false
        }
    }

    func schedule(_ request: ScheduledAlarmRequest) async throws {
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: request.label),
            stopButton: AlarmButton(
                text: "Stop",
                textColor: .white,
                systemImageName: "stop.fill"),
            secondaryButton: AlarmButton(
                text: "Do Pushups",
                textColor: .white,
                systemImageName: "figure.strengthtraining.traditional"),
            secondaryButtonBehavior: .custom)

        let metadata = PushupAlarmMetadata(alarmID: request.id.uuidString, repTarget: request.repTarget)
        let attributes = AlarmAttributes<PushupAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: metadata,
            tintColor: .orange)

        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule(for: request),
            attributes: attributes,
            secondaryIntent: OpenChallengeIntent(alarmID: request.id.uuidString),
            sound: .named(request.soundName))

        _ = try await AlarmManager.shared.schedule(id: request.id, configuration: configuration)
    }

    func cancel(id: UUID) async {
        try? AlarmManager.shared.cancel(id: id)
    }

    func stop(id: UUID) async {
        try? AlarmManager.shared.stop(id: id)
    }

    // MARK: - Schedule construction

    private func schedule(for request: ScheduledAlarmRequest) -> AlarmKit.Alarm.Schedule {
        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: request.hour, minute: request.minute)
        let recurrence: AlarmKit.Alarm.Schedule.Relative.Recurrence
        if request.weekdays.isEmpty {
            recurrence = .never
        } else {
            recurrence = .weekly(request.weekdays.compactMap(Locale.Weekday.init(calendarWeekday:)))
        }
        return .relative(AlarmKit.Alarm.Schedule.Relative(time: time, repeats: recurrence))
    }
}

private extension Locale.Weekday {
    /// Map Calendar's 1=Sunday...7=Saturday onto `Locale.Weekday`.
    init?(calendarWeekday: Int) {
        switch calendarWeekday {
        case 1: self = .sunday
        case 2: self = .monday
        case 3: self = .tuesday
        case 4: self = .wednesday
        case 5: self = .thursday
        case 6: self = .friday
        case 7: self = .saturday
        default: return nil
        }
    }
}
