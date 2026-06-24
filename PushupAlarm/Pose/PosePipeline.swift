import Foundation
import AVFoundation
import Vision
import ChallengeCore

/// Owns the camera and Vision inference. Frames flow out as an `AsyncStream` of
/// pure `PoseFrame`s for the `ChallengeModel` to consume off the main actor
/// (plan §5).
///
/// Concurrency design: the capture delegate (called serially on `sessionQueue`)
/// only hands pixel buffers to a `bufferingNewest(1)` stream. A single consumer
/// task runs Vision one frame at a time and drops anything that piles up behind
/// it — this gives the ~10–15 fps throttle naturally, with no shared mutable
/// state shared across executors (plan §5.3).
final class PosePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    /// Stream of detected poses. Consume with `for await frame in pipeline.frames`.
    let frames: AsyncStream<PoseFrame>
    private let framesContinuation: AsyncStream<PoseFrame>.Continuation

    /// Inbound camera frames, keeping only the newest so stale frames are
    /// dropped while Vision is busy.
    private let buffers: AsyncStream<TimedBuffer>
    private let buffersContinuation: AsyncStream<TimedBuffer>.Continuation

    private let request = DetectHumanBodyPoseRequest()
    private let sessionQueue = DispatchQueue(label: "com.wakeupcall.pushupalarm.camera")
    private let videoOutput = AVCaptureVideoDataOutput()
    private var processingTask: Task<Void, Never>?
    private let startTime = Date()

    /// Carries a non-Sendable pixel buffer to the consumer task. Safe because
    /// exactly one consumer reads it and we never mutate the buffer.
    private struct TimedBuffer: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let timestamp: TimeInterval
    }

    override init() {
        var framesCont: AsyncStream<PoseFrame>.Continuation!
        frames = AsyncStream { framesCont = $0 }
        framesContinuation = framesCont

        var buffersCont: AsyncStream<TimedBuffer>.Continuation!
        buffers = AsyncStream(TimedBuffer.self, bufferingPolicy: .bufferingNewest(1)) { buffersCont = $0 }
        buffersContinuation = buffersCont

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
        startProcessing()
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
        processingTask?.cancel()
        buffersContinuation.finish()
        framesContinuation.finish()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        buffersContinuation.yield(TimedBuffer(pixelBuffer: pixelBuffer,
                                              timestamp: Date().timeIntervalSince(startTime)))
    }

    // MARK: - Inference loop

    private func startProcessing() {
        processingTask = Task { [request, buffers, framesContinuation] in
            for await item in buffers {
                if Task.isCancelled { break }
                guard let observation = try? await request.perform(on: item.pixelBuffer).first else { continue }
                framesContinuation.yield(PoseMapping.poseFrame(from: observation, timestamp: item.timestamp))
            }
        }
    }
}
