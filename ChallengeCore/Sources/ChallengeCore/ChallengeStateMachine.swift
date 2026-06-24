/// States of one wake-up challenge (plan §7).
public enum ChallengeState: Sendable, Equatable {
    case idle
    case initializingCamera
    case detectingUser
    case counting(reps: Int, target: Int)
    case escapeOffered
    case completed
    case abandoned
}

/// Things that happen during a challenge. The view model translates camera /
/// rep-engine / lifecycle signals into these and feeds them to the machine.
public enum ChallengeEvent: Sendable, Equatable {
    case start               // user tapped "Do Pushups"
    case cameraReady
    case poseAcquired        // a valid pose held for enough frames
    case repCounted(total: Int)
    case poseLost            // confidence dropped — pause & reframe
    case failureRecorded     // a genuine, repeated failure to make progress
    case escapeCompleted     // user solved the fallback challenge
    case backgrounded        // app left the foreground
    case timeout             // gave up waiting
    case systemStopTapped    // the OS-guaranteed Stop button, unverified
}

/// Pure, deterministic state machine driving a single challenge. Reaching
/// `.completed` or `.abandoned` is terminal here; the `AlarmCoordinator` decides
/// what to do next (stop & log, or re-arm) based on the terminal state.
public struct ChallengeStateMachine: Sendable {
    public private(set) var state: ChallengeState = .idle

    private let target: Int
    private let failuresBeforeEscape: Int
    private var reps = 0
    private var failures = 0

    public init(target: Int, failuresBeforeEscape: Int = 3) {
        self.target = target
        self.failuresBeforeEscape = failuresBeforeEscape
    }

    public mutating func handle(_ event: ChallengeEvent) {
        // Terminal states ignore everything.
        guard state != .completed, state != .abandoned else { return }

        // An OS Stop without verified completion always abandons.
        if event == .systemStopTapped {
            state = .abandoned
            return
        }

        switch (state, event) {
        case (.idle, .start):
            state = .initializingCamera

        case (.initializingCamera, .cameraReady):
            state = .detectingUser

        case (.detectingUser, .poseAcquired):
            state = reps >= target ? .completed : .counting(reps: reps, target: target)

        case (.counting, .repCounted(let total)):
            reps = total
            state = reps >= target ? .completed : .counting(reps: reps, target: target)

        case (.counting, .poseLost):
            state = .detectingUser

        case (.counting, .failureRecorded):
            failures += 1
            if failures >= failuresBeforeEscape {
                state = .escapeOffered
            }

        case (.escapeOffered, .escapeCompleted):
            state = .completed

        case (_, .backgrounded), (_, .timeout):
            state = .abandoned

        default:
            break // ignore events that don't apply to the current state
        }
    }
}
