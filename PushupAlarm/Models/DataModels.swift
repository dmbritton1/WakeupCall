import Foundation
import SwiftData
import ChallengeCore

/// The exercise a challenge requires. Only pushups for v1; the enum leaves room
/// for squats/situps later without a migration.
public enum ExerciseType: String, Codable, CaseIterable, Sendable {
    case pushup
}

/// What happens when the user taps snooze (if allowed at all).
public enum SnoozePolicy: String, Codable, CaseIterable, Sendable {
    case none          // no snooze; finish the challenge or it re-arms
    case onceShort     // a single short snooze permitted
}

/// How a challenge session ended.
public enum Outcome: String, Codable, Sendable {
    case inProgress
    case completed
    case abandoned
    case escaped
}

/// A configured alarm. `Strictness` is reused from `ChallengeCore` so the UI and
/// the rep engine share one definition.
@Model
final class Alarm {
    @Attribute(.unique) var id: UUID
    var hour: Int
    var minute: Int
    /// Recurring days, 1 = Sunday ... 7 = Saturday (Calendar convention).
    /// Empty means a one-shot alarm.
    var weekdays: [Int]
    var label: String
    var isEnabled: Bool
    var soundName: String
    var repTarget: Int
    var exerciseTypeRaw: String
    var strictnessRaw: String
    var snoozePolicyRaw: String
    var createdAt: Date

    init(id: UUID = UUID(),
         hour: Int = 6,
         minute: Int = 30,
         weekdays: [Int] = [2, 3, 4, 5, 6],
         label: String = "Wake up",
         isEnabled: Bool = true,
         soundName: String = "alarm.caf",
         repTarget: Int = 10,
         exerciseType: ExerciseType = .pushup,
         strictness: Strictness = .lenient,
         snoozePolicy: SnoozePolicy = .none,
         createdAt: Date = .now) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.label = label
        self.isEnabled = isEnabled
        self.soundName = soundName
        self.repTarget = repTarget
        self.exerciseTypeRaw = exerciseType.rawValue
        self.strictnessRaw = strictness.rawValue
        self.snoozePolicyRaw = snoozePolicy.rawValue
        self.createdAt = createdAt
    }

    var exerciseType: ExerciseType {
        get { ExerciseType(rawValue: exerciseTypeRaw) ?? .pushup }
        set { exerciseTypeRaw = newValue.rawValue }
    }
    var strictness: Strictness {
        get { Strictness(rawValue: strictnessRaw) ?? .lenient }
        set { strictnessRaw = newValue.rawValue }
    }
    var snoozePolicy: SnoozePolicy {
        get { SnoozePolicy(rawValue: snoozePolicyRaw) ?? .none }
        set { snoozePolicyRaw = newValue.rawValue }
    }
}

/// A single attempt at a wake-up challenge — the data behind history/streaks and
/// the persistence loop's "is there an unfinished session?" check.
@Model
final class ChallengeSession {
    @Attribute(.unique) var id: UUID
    var alarmID: UUID
    var startedAt: Date
    var completedAt: Date?
    var repsCompleted: Int
    var targetReps: Int
    var reArmCount: Int
    var escapeUsed: Bool
    var outcomeRaw: String

    init(id: UUID = UUID(),
         alarmID: UUID,
         startedAt: Date = .now,
         completedAt: Date? = nil,
         repsCompleted: Int = 0,
         targetReps: Int,
         reArmCount: Int = 0,
         escapeUsed: Bool = false,
         outcome: Outcome = .inProgress) {
        self.id = id
        self.alarmID = alarmID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.repsCompleted = repsCompleted
        self.targetReps = targetReps
        self.reArmCount = reArmCount
        self.escapeUsed = escapeUsed
        self.outcomeRaw = outcome.rawValue
    }

    var outcome: Outcome {
        get { Outcome(rawValue: outcomeRaw) ?? .inProgress }
        set { outcomeRaw = newValue.rawValue }
    }

    var isFinished: Bool { outcome != .inProgress }
}
