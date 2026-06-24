import SwiftUI
import ChallengeCore

/// The wake-up challenge: live camera, skeleton overlay, rep HUD, and the
/// state-driven prompts (detecting / counting / completed / escape).
struct ChallengeView: View {
    @Environment(AlarmCoordinator.self) private var coordinator
    @Environment(ChallengeRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase

    let alarm: Alarm

    @State private var model: ChallengeModel
    @State private var session: ChallengeSession?

    init(alarm: Alarm) {
        self.alarm = alarm
        _model = State(initialValue: ChallengeModel(target: alarm.repTarget, strictness: alarm.strictness))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if model.cameraDenied {
                cameraDeniedView
            } else {
                CameraPreview(session: model.captureSession)
                    .ignoresSafeArea()
                SkeletonOverlay(frame: model.latestFrame)
                    .ignoresSafeArea()
            }

            VStack {
                repHUD
                Spacer()
                statusBanner
            }
            .padding()

            overlayForState
        }
        .statusBarHidden()
        .task { await start() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.appWillBackground() }
        }
    }

    // MARK: - HUD

    private var repHUD: some View {
        VStack(spacing: 2) {
            Text("\(model.reps) / \(model.target)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text("pushups")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    @ViewBuilder private var statusBanner: some View {
        if let issue = model.formIssue, isCounting {
            Label(issue == .sagging ? "Lift your hips" : "Lower your hips",
                  systemImage: "exclamationmark.triangle.fill")
                .padding()
                .background(.orange, in: Capsule())
                .foregroundStyle(.white)
        } else if isCounting && !model.poseVisible {
            Label("Reposition so your whole body is in view", systemImage: "viewfinder")
                .padding()
                .background(.ultraThinMaterial, in: Capsule())
        }
    }

    @ViewBuilder private var overlayForState: some View {
        switch model.state {
        case .initializingCamera, .idle:
            ProgressView("Starting camera…").tint(.white).foregroundStyle(.white)
        case .detectingUser:
            VStack(spacing: 8) {
                Image(systemName: "figure.strengthtraining.traditional").font(.largeTitle)
                Text("Get into pushup position").font(.title2.weight(.semibold))
                Text("Place the phone on its side, a few feet away.").font(.callout).foregroundStyle(.secondary)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
            .foregroundStyle(.white)
        case .escapeOffered:
            EscapeValveView { model.completeEscape() }
        case .completed:
            completedView
        case .counting, .abandoned:
            EmptyView()
        }
    }

    private var completedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(.green)
            Text("Done — you're up!").font(.title.bold()).foregroundStyle(.white)
            Button("Dismiss") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private var cameraDeniedView: some View {
        ContentUnavailableView {
            Label("Camera access needed", systemImage: "camera.fill")
        } description: {
            Text("Pushup Alarm counts your pushups on-device. Enable the camera in Settings.")
        }
        .foregroundStyle(.white)
    }

    private var isCounting: Bool {
        if case .counting = model.state { return true }
        return false
    }

    // MARK: - Lifecycle

    private func start() async {
        session = coordinator.beginSession(for: alarm)
        UIApplication.shared.isIdleTimerDisabled = true
        model.onCompleted = {
            Task {
                if let session { await coordinator.complete(session, reps: model.reps) }
                dismiss()
            }
        }
        model.onAbandoned = {
            Task {
                if let session { await coordinator.abandon(session, reps: model.reps) }
                dismiss()
            }
        }
        await model.begin()
    }

    private func dismiss() {
        model.end()
        UIApplication.shared.isIdleTimerDisabled = false
        router.clear()
    }
}

/// Accessibility / anti-trap valve (plan §7). Placeholder: a simple confirm.
/// Replace with a math problem / type-a-phrase / QR scan and tune leniency.
private struct EscapeValveView: View {
    let onSolved: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Having trouble?").font(.title2.bold())
            Text("Solve this to dismiss the alarm.").foregroundStyle(.secondary)
            Button("I'm awake — dismiss", action: onSolved)
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .foregroundStyle(.white)
    }
}
