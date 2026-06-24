import Foundation
import Observation
import AVFoundation
import ChallengeCore

/// The challenge view model (plan §3). Drives the camera, feeds frames through
/// the pure engine (`RepCounter` / `FormEvaluator` / `ChallengeStateMachine`),
/// and publishes HUD state for `ChallengeView`. `@MainActor` so SwiftUI sees
/// consistent state; the heavy Vision work happens off-actor in `PosePipeline`.
@MainActor
@Observable
final class ChallengeModel {
    // Published HUD state.
    private(set) var state: ChallengeState = .idle
    private(set) var reps = 0
    let target: Int
    private(set) var latestFrame: PoseFrame?
    private(set) var latestImageSize: CGSize = .zero
    private(set) var formIssue: FormIssue?
    private(set) var poseVisible = false
    private(set) var cameraDenied = false

    /// Called once on terminal states so the coordinator can stop/re-arm + log.
    var onCompleted: (() -> Void)?
    var onAbandoned: (() -> Void)?

    private var machine: ChallengeStateMachine
    private var repCounter: RepCounter
    private let formEvaluator: FormEvaluator
    private let pipeline = PosePipeline()
    private let framesToAcquire = 8
    private var goodFrameStreak = 0
    private var consumeTask: Task<Void, Never>?

    /// The configured preview layer (orientation/mirroring already applied).
    var previewLayer: AVCaptureVideoPreviewLayer { pipeline.previewLayer }

    /// Diagnostic string for the on-screen debug readout while tuning detection.
    var debugReadout: String {
        let n = latestFrame?.joints.count ?? 0
        let conf = meanConfidence
        return "joints \(n) · conf \(String(format: "%.2f", conf)) · \(phaseText)"
    }

    private var meanConfidence: Double {
        guard let joints = latestFrame?.joints.values, !joints.isEmpty else { return 0 }
        return joints.map(\.confidence).reduce(0, +) / Double(joints.count)
    }

    private var phaseText: String {
        switch state {
        case .idle: return "idle"
        case .initializingCamera: return "init"
        case .detectingUser: return "detecting"
        case .counting: return "counting"
        case .escapeOffered: return "escape"
        case .completed: return "done"
        case .abandoned: return "abandoned"
        }
    }

    init(target: Int, strictness: Strictness, minConfidence: Double = 0.5) {
        self.target = target
        self.machine = ChallengeStateMachine(target: target)
        self.repCounter = RepCounter(config: RepCounterConfig(minConfidence: minConfidence))
        self.formEvaluator = FormEvaluator(config: FormConfig(strictness: strictness, minConfidence: minConfidence))
    }

    func begin() async {
        machine.handle(.start)
        sync()

        guard await AVCaptureDevice.requestAccess(for: .video) else {
            cameraDenied = true
            return
        }
        pipeline.attachPreview(position: .front)
        pipeline.configure(position: .front)
        pipeline.start()
        machine.handle(.cameraReady)
        sync()
        consume()
    }

    func end() {
        consumeTask?.cancel()
        pipeline.stop()
    }

    /// Leaving the foreground mid-challenge abandons it (coordinator re-arms).
    func appWillBackground() {
        machine.handle(.backgrounded)
        sync()
    }

    /// The user solved the fallback (escape valve).
    func completeEscape() {
        machine.handle(.escapeCompleted)
        sync()
    }

    // MARK: - Frame processing

    private func consume() {
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await sample in pipeline.frames {
                if Task.isCancelled { break }
                process(sample)
            }
        }
    }

    private func process(_ sample: PoseSample) {
        let frame = sample.frame
        latestFrame = frame
        latestImageSize = sample.imageSize
        formIssue = formEvaluator.evaluate(frame).issue

        let update = repCounter.process(frame)
        poseVisible = update.poseVisible
        reps = update.count

        switch state {
        case .detectingUser:
            goodFrameStreak = update.poseVisible ? goodFrameStreak + 1 : 0
            if goodFrameStreak >= framesToAcquire {
                machine.handle(.poseAcquired)
            }
        case .counting:
            if !update.poseVisible {
                machine.handle(.poseLost)
            } else if update.didCompleteRep {
                machine.handle(.repCounted(total: update.count))
            }
        default:
            break
        }
        sync()
    }

    /// Mirror the machine's state into observable properties and fire terminal
    /// callbacks exactly once.
    private func sync() {
        let new = machine.state
        guard new != state else { return }
        if new == .detectingUser { goodFrameStreak = 0 }
        state = new
        switch new {
        case .completed:
            end()
            onCompleted?()
        case .abandoned:
            end()
            onAbandoned?()
        default:
            break
        }
    }
}
