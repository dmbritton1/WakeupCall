import Testing
@testable import ChallengeCore

@Suite("ChallengeStateMachine — wake-up flow transitions (plan §7)")
struct ChallengeStateMachineTests {

    private func started(target: Int = 2, failuresBeforeEscape: Int = 3) -> ChallengeStateMachine {
        var m = ChallengeStateMachine(target: target, failuresBeforeEscape: failuresBeforeEscape)
        m.handle(.start)
        m.handle(.cameraReady)
        m.handle(.poseAcquired)
        return m
    }

    @Test("happy path: reaching the target completes the challenge")
    func happyPath() {
        var m = ChallengeStateMachine(target: 2)
        #expect(m.state == .idle)
        m.handle(.start);        #expect(m.state == .initializingCamera)
        m.handle(.cameraReady);  #expect(m.state == .detectingUser)
        m.handle(.poseAcquired); #expect(m.state == .counting(reps: 0, target: 2))
        m.handle(.repCounted(total: 1)); #expect(m.state == .counting(reps: 1, target: 2))
        m.handle(.repCounted(total: 2)); #expect(m.state == .completed)
    }

    @Test("losing the pose pauses to detectingUser and resumes without losing reps")
    func poseLostResumes() {
        var m = started(target: 5)
        m.handle(.repCounted(total: 2))
        m.handle(.poseLost)
        #expect(m.state == .detectingUser)
        m.handle(.poseAcquired)
        #expect(m.state == .counting(reps: 2, target: 5)) // resumed, not reset
    }

    @Test("repeated genuine failures offer the escape valve")
    func escapeOffered() {
        var m = started(failuresBeforeEscape: 3)
        m.handle(.failureRecorded)
        m.handle(.failureRecorded)
        #expect(m.state != .escapeOffered)
        m.handle(.failureRecorded)
        #expect(m.state == .escapeOffered)
    }

    @Test("completing the escape valve completes the challenge")
    func escapeCompletes() {
        var m = started(failuresBeforeEscape: 1)
        m.handle(.failureRecorded)
        #expect(m.state == .escapeOffered)
        m.handle(.escapeCompleted)
        #expect(m.state == .completed)
    }

    @Test("backgrounding mid-challenge abandons (coordinator will re-arm)")
    func backgroundedAbandons() {
        var m = started()
        m.handle(.backgrounded)
        #expect(m.state == .abandoned)
    }

    @Test("an unverified system Stop abandons rather than completing")
    func systemStopAbandons() {
        var m = started()
        m.handle(.repCounted(total: 1))
        m.handle(.systemStopTapped)
        #expect(m.state == .abandoned)
    }

    @Test("completed is terminal — later events are ignored")
    func completedTerminal() {
        var m = ChallengeStateMachine(target: 1)
        m.handle(.start); m.handle(.cameraReady); m.handle(.poseAcquired)
        m.handle(.repCounted(total: 1))
        #expect(m.state == .completed)
        m.handle(.poseLost)
        m.handle(.backgrounded)
        #expect(m.state == .completed)
    }
}
