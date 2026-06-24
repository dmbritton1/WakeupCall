import Foundation
import SwiftData
import Observation

/// Wraps the alarm backend and the SwiftData session bookkeeping, and enforces
/// the "can't turn it off until done" persistence loop (plan §4.3). iOS always
/// guarantees a Stop button, so completion is enforced by re-arming a fresh
/// alarm whenever an unfinished session is abandoned — not by trapping the user.
@MainActor
@Observable
final class AlarmCoordinator {
    /// Seconds until a re-armed alarm fires after an unverified stop/abandon.
    static let reArmDelay: TimeInterval = 60

    private let scheduler: AlarmScheduling
    private let context: ModelContext

    init(scheduler: AlarmScheduling, context: ModelContext) {
        self.scheduler = scheduler
        self.context = context
    }

    func requestAuthorization() async -> Bool {
        await scheduler.requestAuthorization()
    }

    /// (Re)schedule every enabled alarm.
    func refreshSchedules(_ alarms: [Alarm]) async {
        for alarm in alarms where alarm.isEnabled {
            try? await scheduler.schedule(request(for: alarm))
        }
    }

    func disable(_ alarm: Alarm) async {
        await scheduler.cancel(id: alarm.id)
    }

    // MARK: - Sessions

    /// Start (or resume) the session for an alarm when its challenge opens.
    func beginSession(for alarm: Alarm) -> ChallengeSession {
        if let existing = unfinishedSession(for: alarm.id) { return existing }
        let session = ChallengeSession(alarmID: alarm.id, targetReps: alarm.repTarget)
        context.insert(session)
        try? context.save()
        return session
    }

    /// Verified completion: stop the alarm, log it, do NOT re-arm.
    func complete(_ session: ChallengeSession, reps: Int) async {
        session.repsCompleted = reps
        session.completedAt = .now
        session.outcome = .completed
        try? context.save()
        await scheduler.stop(id: session.alarmID)
        await scheduler.cancel(id: reArmID(for: session.alarmID))
    }

    /// Unverified stop / abandonment: log it and re-arm shortly so the user has
    /// to face the challenge again.
    func abandon(_ session: ChallengeSession, reps: Int) async {
        session.repsCompleted = max(session.repsCompleted, reps)
        session.outcome = .abandoned
        session.reArmCount += 1
        try? context.save()
        await reArm(alarmID: session.alarmID, label: "Finish your pushups", repTarget: session.targetReps)
    }

    /// On launch/foreground, if a session was left unfinished, re-arm so the
    /// alarm comes back (plan §4.3 step 4).
    func reArmUnfinishedIfNeeded() async {
        let unfinished = (try? context.fetch(FetchDescriptor<ChallengeSession>())) ?? []
        for session in unfinished where !session.isFinished {
            await reArm(alarmID: session.alarmID, label: "Finish your pushups", repTarget: session.targetReps)
        }
    }

    // MARK: - Helpers

    private func reArm(alarmID: UUID, label: String, repTarget: Int) async {
        let fireDate = Date().addingTimeInterval(Self.reArmDelay)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: fireDate)
        let request = ScheduledAlarmRequest(
            id: reArmID(for: alarmID),
            hour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            weekdays: [],            // one-shot
            label: label,
            soundName: "alarm.caf",
            repTarget: repTarget)
        try? await scheduler.schedule(request)
    }

    /// A stable, distinct id for the re-arm alarm derived from the base alarm.
    private func reArmID(for alarmID: UUID) -> UUID {
        UUID(uuidString: alarmID.uuidString) ?? alarmID
    }

    private func unfinishedSession(for alarmID: UUID) -> ChallengeSession? {
        let all = (try? context.fetch(FetchDescriptor<ChallengeSession>())) ?? []
        return all.first { $0.alarmID == alarmID && !$0.isFinished }
    }

    private func request(for alarm: Alarm) -> ScheduledAlarmRequest {
        ScheduledAlarmRequest(
            id: alarm.id,
            hour: alarm.hour,
            minute: alarm.minute,
            weekdays: alarm.weekdays,
            label: alarm.label,
            soundName: alarm.soundName,
            repTarget: alarm.repTarget)
    }
}
