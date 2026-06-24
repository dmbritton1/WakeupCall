import Foundation
import AVFoundation
import Vision
import ChallengeCore

/// Owns the camera and Vision inference. Frames flow out as an `AsyncStream` of
/// pure `PoseFrame`s for the `ChallengeModel` to consume off the main actor
/// (plan §5). Inference is throttled with an `isProcessing` guard so we run
/// ~10–15 fps regardless of camera frame rate — plenty for slow pushups, easy
/// on battery/heat.
final class PosePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    /// Stream of detected poses. Consume with `for await frame in pipeline.frames`.
    let frames: AsyncStream<PoseFrame>
    private let continuation: AsyncStream<PoseFrame>.Continuation

    private let request = DetectHumanBodyPoseRequest()
    private let sessionQueue = DispatchQueue(label: "com.wakeupcall.pushupalarm.camera")
    private let videoOutput = AVCaptureVideoDataOutput()

    /// Skip frames while one is in flight — the throttle.
    private var isProcessing = false
    private let startTime = Date()

    override init() {
        var cont: AsyncStream<PoseFrame>.Continuation!
        frames = AsyncStream { cont = $0 }
        continuation = cont
        super.init()
    }

    /// Configure for the given camera position (front recommended in the dark —
    /// the screen acts as fill light, plan §5.3).
    func configure(position: AVCaptureDevice.Position = .front) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            session.sessionPreset = .high

            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            session.commitConfiguration()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, session.isRunning else { return }
            session.stopRunning()
        }
        continuation.finish()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard !isProcessing,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        isProcessing = true

        let timestamp = Date().timeIntervalSince(startTime)
        Task { [weak self] in
            guard let self else { return }
            defer { isProcessing = false }
            guard let observation = try? await request.perform(on: pixelBuffer).first else { return }
            continuation.yield(PoseMapping.poseFrame(from: observation, timestamp: timestamp))
        }
    }
}
