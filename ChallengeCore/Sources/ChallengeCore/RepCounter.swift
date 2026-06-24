import Foundation

/// Tunables for rep detection. Defaults match the plan (§6): UP > 160°,
/// DOWN < 90°, with a hysteresis gap between them so jitter can't double-count.
public struct RepCounterConfig: Sendable, Equatable {
    /// Elbow angle above which the arms are considered extended (top of pushup).
    public var upThreshold: Double
    /// Elbow angle below which the arms are considered bent (bottom of pushup).
    public var downThreshold: Double
    /// Minimum seconds for a down→up cycle; rejects teleport/bounce cheats.
    public var minRepDuration: TimeInterval
    /// Minimum peak-to-trough angle span within a rep; rejects shallow reps.
    public var minRangeOfMotion: Double
    /// Joints below this confidence are ignored.
    public var minConfidence: Double
    /// Frames of moving-average smoothing applied to the elbow angle.
    public var smoothingWindow: Int

    public init(upThreshold: Double = 160,
                downThreshold: Double = 90,
                minRepDuration: TimeInterval = 0.4,
                minRangeOfMotion: Double = 40,
                minConfidence: Double = 0.5,
                smoothingWindow: Int = 5) {
        self.upThreshold = upThreshold
        self.downThreshold = downThreshold
        self.minRepDuration = minRepDuration
        self.minRangeOfMotion = minRangeOfMotion
        self.minConfidence = minConfidence
        self.smoothingWindow = smoothingWindow
    }
}

/// Coarse phase of the movement.
public enum RepPhase: Sendable, Equatable {
    case unknown
    case up
    case down
}

/// Result of feeding one frame to the counter.
public struct RepUpdate: Sendable, Equatable {
    public var count: Int
    public var phase: RepPhase
    /// True only on the frame that completes a valid rep.
    public var didCompleteRep: Bool
    /// False when no arm cleared the confidence gate this frame.
    public var poseVisible: Bool
}

/// Counts pushup reps from a stream of `PoseFrame`s. Pure value type: no I/O,
/// no Vision/AVFoundation — feed it frames (live or replayed from a fixture)
/// and it returns deterministic updates.
public struct RepCounter: Sendable {
    public private(set) var count = 0
    public private(set) var phase: RepPhase = .unknown

    private let config: RepCounterConfig
    private var smoother: MovingAverage

    // Per-rep tracking, valid while `phase == .down`.
    private var downStartTime: TimeInterval?
    private var minAngleInRep = Double.greatestFiniteMagnitude
    private var maxAngleInRep = -Double.greatestFiniteMagnitude

    public init(config: RepCounterConfig = RepCounterConfig()) {
        self.config = config
        self.smoother = MovingAverage(windowSize: config.smoothingWindow)
    }

    public mutating func process(_ frame: PoseFrame) -> RepUpdate {
        guard let raw = elbowAngle(in: frame) else {
            // Pose lost: hold state, count nothing. Recovery resumes cleanly.
            return RepUpdate(count: count, phase: phase, didCompleteRep: false, poseVisible: false)
        }

        let angle = smoother.add(raw)
        var didComplete = false

        switch phase {
        case .unknown:
            if angle > config.upThreshold {
                phase = .up
            } else if angle < config.downThreshold {
                // Started watching mid-bottom; wait for an UP before counting.
                phase = .down
                beginRep(at: frame.timestamp, angle: angle)
            }

        case .up:
            if angle < config.downThreshold {
                phase = .down
                beginRep(at: frame.timestamp, angle: angle)
            }

        case .down:
            track(angle)
            if angle > config.upThreshold {
                if isValidRep(endingAt: frame.timestamp) {
                    count += 1
                    didComplete = true
                }
                phase = .up
            }
        }

        return RepUpdate(count: count, phase: phase, didCompleteRep: didComplete, poseVisible: true)
    }

    // MARK: - Rep bookkeeping

    private mutating func beginRep(at time: TimeInterval, angle: Double) {
        downStartTime = time
        minAngleInRep = angle
        maxAngleInRep = angle
    }

    private mutating func track(_ angle: Double) {
        minAngleInRep = min(minAngleInRep, angle)
        maxAngleInRep = max(maxAngleInRep, angle)
    }

    private func isValidRep(endingAt time: TimeInterval) -> Bool {
        guard let start = downStartTime else { return false }
        let duration = time - start
        let rom = maxAngleInRep - minAngleInRep
        return duration >= config.minRepDuration && rom >= config.minRangeOfMotion
    }

    // MARK: - Angle extraction

    /// Averaged elbow angle over whichever arms cleared the confidence gate.
    /// `nil` if neither arm is usable this frame.
    private func elbowAngle(in frame: PoseFrame) -> Double? {
        let left = armAngle(frame, .leftShoulder, .leftElbow, .leftWrist)
        let right = armAngle(frame, .rightShoulder, .rightElbow, .rightWrist)
        let available = [left, right].compactMap { $0 }
        guard !available.isEmpty else { return nil }
        return available.reduce(0, +) / Double(available.count)
    }

    private func armAngle(_ frame: PoseFrame, _ s: Joint, _ e: Joint, _ w: Joint) -> Double? {
        guard let shoulder = frame.point(s, minConfidence: config.minConfidence),
              let elbow = frame.point(e, minConfidence: config.minConfidence),
              let wrist = frame.point(w, minConfidence: config.minConfidence) else {
            return nil
        }
        return Geometry.angle(shoulder, elbow, wrist)
    }
}
