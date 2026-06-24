import Foundation

/// Everything a backend needs to ring one alarm. Decoupled from SwiftData so
/// schedulers never touch the database.
struct ScheduledAlarmRequest: Sendable, Equatable {
    var id: UUID
    var hour: Int
    var minute: Int
    /// 1 = Sunday ... 7 = Saturday. Empty = fire once at the next occurrence.
    var weekdays: [Int]
    var label: String
    var soundName: String
    var repTarget: Int
}

/// The seam that isolates the load-bearing, churn-prone alarm layer (plan §4).
/// The app talks only to this; concrete backends are AlarmKit (production,
/// device + paid account) or local notifications (dev fallback, simulator).
protocol AlarmScheduling: Sendable {
    /// Returns true if alarms may be scheduled.
    func requestAuthorization() async -> Bool
    func schedule(_ request: ScheduledAlarmRequest) async throws
    func cancel(id: UUID) async
    /// Stop a currently-ringing alarm (e.g. on verified completion).
    func stop(id: UUID) async
}
