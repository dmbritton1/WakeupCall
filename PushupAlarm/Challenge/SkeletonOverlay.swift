import SwiftUI
import ChallengeCore

/// Draws the detected joints + bones over the camera feed. Input joints are
/// normalized with a lower-left origin (Vision), so we flip y into SwiftUI's
/// top-left space.
struct SkeletonOverlay: View {
    let frame: PoseFrame?
    var minConfidence: Double = 0.3

    /// Bones to connect, as joint pairs.
    private static let bones: [(ChallengeCore.Joint, ChallengeCore.Joint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, _ in
                guard let frame else { return }

                for (a, b) in Self.bones {
                    guard let pa = point(a, in: frame, size: size),
                          let pb = point(b, in: frame, size: size) else { continue }
                    var path = Path()
                    path.move(to: pa)
                    path.addLine(to: pb)
                    context.stroke(path, with: .color(.green.opacity(0.8)), lineWidth: 3)
                }

                for joint in ChallengeCore.Joint.allCases {
                    guard let p = point(joint, in: frame, size: size) else { continue }
                    let dot = Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
                    context.fill(dot, with: .color(.yellow))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func point(_ joint: ChallengeCore.Joint, in frame: PoseFrame, size: CGSize) -> CGPoint? {
        guard let p = frame.point(joint, minConfidence: minConfidence) else { return nil }
        return CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
    }
}
