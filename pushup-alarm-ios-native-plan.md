# Pushup Alarm — Native iOS Implementation Plan (Swift)

A detailed architecture + build plan for the iOS-first, all-Apple version of the app. Everything is first-party: no cross-platform framework, no native bridges, one language.

**Locked decisions**
- **Language/UI:** Swift 6 + SwiftUI
- **Pose detection:** Apple **Vision** (`DetectHumanBodyPoseRequest`, 19 joints, on-device)
- **Alarm:** Apple **AlarmKit** (iOS 26+)
- **Persistence:** **SwiftData** (no backend)
- **Toolchain:** Xcode 26, **iOS 26 deployment target**, real device required for the alarm path

> Written assuming you're newer to the stack: each framework choice explains *why*, and the build order front-loads the two risky pieces so you learn them first on small spikes.

---

## 1. Tech stack (all Apple, by concern)

| Concern | Framework / API | Why it's the right native choice |
|---|---|---|
| UI | **SwiftUI** | Declarative, fast to learn, first-class on iOS 26 |
| View state | **Observation** (`@Observable`) | Modern replacement for `ObservableObject`; less boilerplate |
| Concurrency | **Swift Concurrency** (`async/await`, actors, `AsyncStream`) | Clean way to stream camera frames and pose results off the main thread |
| Camera capture | **AVFoundation** (`AVCaptureSession`) | Raw frame access for Vision; standard live-camera path |
| Pose detection | **Vision** (`DetectHumanBodyPoseRequest`) | First-party, on-device, async; 19 body joints incl. shoulders/elbows/wrists/hips |
| Alarm | **AlarmKit** (`AlarmManager`) | Only API that rings through Silent/Focus with Lock Screen + Dynamic Island |
| Alarm button actions | **App Intents** (`LiveActivityIntent`) | Runs your code / launches the app from an alarm button |
| Lock-screen/Dynamic Island UI | **ActivityKit + WidgetKit** (Live Activity) | AlarmKit presents via Live Activities; custom UI lives in a widget extension |
| Persistence | **SwiftData** (`@Model`) | Native, low-boilerplate local DB; no server needed |
| Keep screen awake | `UIApplication.isIdleTimerDisabled` | Screen stays on during the challenge |
| Crash/issue reporting | (optional) Sentry or MetricKit | First device-specific bugs will be invisible otherwise |

**Third-party dependencies: essentially none.** That's a real advantage for a solo/newer dev — fewer moving parts, no version-churn surprises, every API has Apple docs + WWDC videos.

---

## 2. Xcode project & targets

Four pieces in one Xcode project:

```
PushupAlarm (Xcode project)
├── PushupAlarm            (App target — SwiftUI)
├── PushupAlarmWidget      (Widget Extension — AlarmKit Live Activity UI)
├── ChallengeCore          (local Swift Package — PURE logic, no UIKit/Vision)
│     └── RepCounter, FormEvaluator, ChallengeStateMachine, models
└── App Group: group.com.you.pushupalarm   (shared state: app ↔ widget ↔ intents)
```

Two structural decisions that pay off:

- **`ChallengeCore` as a local Swift Package.** Put the rep-counting/form/state-machine logic in a pure package with zero Apple-UI dependencies. It compiles fast, and you can unit-test it on the Mac without a simulator. This is the single best move for quality (see §6).
- **App Group.** AlarmKit's App Intents and the widget extension run in separate processes from your app. They share state (which alarm, did the user finish) through an App Group container. Set this up early — and note it generally requires the **paid Apple Developer Program**, so budget the $99 before this milestone.

---

## 3. Architecture overview

Pattern: **MVVM with `@Observable`**, Swift Concurrency for data flow, layered so the two risky subsystems sit behind protocols.

```
┌────────────────────────────────────────────────────────────┐
│ VIEWS (SwiftUI)                                             │
│  AlarmListView • AlarmEditorView • OnboardingView          │
│  ChallengeView (camera + rep HUD) • HistoryView • Settings │
└──────────────┬─────────────────────────────────────────────┘
               │ observes @Observable state objects
┌──────────────▼─────────────────────────────────────────────┐
│ STATE / VIEW MODELS  (@Observable, @MainActor)             │
│  AlarmListModel • AlarmEditorModel • ChallengeModel        │
└──────┬───────────────────────────────┬────────────────────┘
       │                               │
┌──────▼──────────────┐    ┌───────────▼───────────────────┐
│ COORDINATORS         │    │ ChallengeCore (Swift Package) │
│  AlarmCoordinator    │    │  RepCounter  FormEvaluator    │
│   wraps AlarmManager │    │  ChallengeStateMachine        │
│   + persistence loop │    │  (PURE — testable)            │
│  PosePipeline        │    └───────────────────────────────┘
│   AVCapture→Vision   │
│   → AsyncStream<Pose>│    ┌───────────────────────────────┐
└──────────────────────┘    │ SwiftData (Alarm, Session)    │
                            └───────────────────────────────┘
```

Data flow during a wake-up: `AVCaptureSession` frames → `PosePipeline` runs Vision → emits `AsyncStream<PoseFrame>` → `ChallengeModel` feeds frames to `RepCounter`/`FormEvaluator` → updates the HUD → on completion tells `AlarmCoordinator` to stop (and not re-arm).

---

## 4. Alarm subsystem (AlarmKit) — the load-bearing part

### 4.1 Concepts
- `AlarmManager.shared` is the entry point: authorization, `schedule`, `cancel`, `stop`, `pause/resume`, plus an updates stream.
- An alarm is built from an `AlarmConfiguration` containing: a schedule (fixed date, or **relative recurring** like "Mon/Wed/Fri 6:00"), `AlarmAttributes` (presentation + tint + your metadata), an optional `secondaryIntent`, and a custom `sound` (`AlertSound.named(...)`, file in the main bundle or `Library/Sounds`).
- The presentation is an `AlarmPresentation.Alert(title:, stopButton:, secondaryButton:, secondaryButtonBehavior:)` using `AlarmButton(text:, textColor:, systemImageName:)`.

### 4.2 The mechanic: a custom button that launches the challenge
This is the heart of the app. Use the **secondary button** with `.custom` behavior, wired to an App Intent that opens your app into the challenge:

```swift
// Pseudocode — verify exact signatures against current AlarmKit docs.
import AlarmKit
import AppIntents

struct OpenChallengeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Do Pushups"
    @Parameter var alarmID: String
    func perform() async throws -> some IntentResult {
        // App opens; deep-link to the challenge screen for alarmID.
        ChallengeRouter.shared.pending = alarmID   // via App Group
        return .result()
    }
}

let alert = AlarmPresentation.Alert(
    title: "Time to wake up",
    stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
    secondaryButton: AlarmButton(text: "Do Pushups", textColor: .white, systemImageName: "figure.strengthtraining.traditional"),
    secondaryButtonBehavior: .custom
)

let config = AlarmManager.AlarmConfiguration(
    schedule: /* relative recurring schedule */,
    attributes: AlarmAttributes(presentation: AlarmPresentation(alert: alert), tintColor: .orange),
    secondaryIntent: OpenChallengeIntent(alarmID: id.uuidString),
    sound: .named("alarm.caf")
)
try await AlarmManager.shared.schedule(id: id, configuration: config)
```

> **Churn caveat (real):** the "open the app from an alarm button" mechanism is new and shifting — the old `openAppWhenRun` flag was deprecated in iOS 26.0 in favor of `supportedModes`, and iOS 26.1 turned the Stop button into a slider in some states. Treat the snippet as the shape, not the exact final code, and verify on the current OS build.

### 4.3 The "can't turn it off until done" reality
AlarmKit **requires a Stop button** — iOS guarantees the user an off switch, so you can't literally trap them. You enforce the challenge with a **persistence loop** in `AlarmCoordinator`:

1. Alarm fires → user taps **Do Pushups** → app opens to `ChallengeView`.
2. If the alarm is stopped/snoozed and the `ChallengeSession` is **not** completed → immediately schedule a fresh alarm ~45–60s out. Repeat.
3. On verified completion → stop, do **not** re-arm, log the session.
4. On app launch, if an unfinished session exists, re-arm.

### 4.4 Live Activity (widget extension)
AlarmKit presents on the Lock Screen / Dynamic Island via **ActivityKit**. For MVP you can lean on the system's fallback presentation; for branded countdown/alert UI you add the **Widget Extension** target and implement the Live Activity views. Your alarm `metadata` (conforming to `AlarmMetadata`) feeds that UI (e.g. reps required).

### 4.5 Setup checklist
- `NSAlarmKitUsageDescription` in Info.plist; request authorization before scheduling.
- App Group entitlement on app + widget + intents.
- Custom alarm sound bundled (`.caf`/supported format).
- Test on a **physical iOS 26 device** (simulator can't fully present prominent alarms).

---

## 5. Vision pose pipeline (camera → joints)

### 5.1 Camera capture (AVFoundation)
Configure an `AVCaptureSession` on a dedicated queue, output `kCVPixelFormatType_32BGRA`, discard late frames, and implement `AVCaptureVideoDataOutputSampleBufferDelegate`. Show the preview via an `AVCaptureVideoPreviewLayer` wrapped in a `UIViewRepresentable`, with a SwiftUI skeleton overlay on top.

```swift
final class PosePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let request = DetectHumanBodyPoseRequest()
    private var isProcessing = false
    // emits frames to the ChallengeModel
    let frames: AsyncStream<PoseFrame> /* + continuation */

    func captureOutput(_ out: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from: AVCaptureConnection) {
        guard !isProcessing else { return }      // throttle: skip while busy
        isProcessing = true
        Task {
            defer { isProcessing = false }
            if let observation = try? await request.perform(on: buffer).first {
                continuation.yield(PoseFrame(observation, timestamp: .now))
            }
        }
    }
}
```

### 5.2 The Vision request (modern Swift API)
- Use **`DetectHumanBodyPoseRequest`** (the new async Swift API; the legacy equivalent is `VNDetectHumanBodyPoseRequest`). It returns observations with **19 joints** grouped into head/torso/left+right arm/left+right leg.
- Each recognized point gives a **normalized** location (lower-left origin) and a **confidence**. Gate on confidence > ~0.5; project normalized → view coordinates for the overlay.
- For pushups, the joints you care about: `leftShoulder/rightShoulder`, `leftElbow/rightElbow`, `leftWrist/rightWrist`, `leftHip/rightHip`, `leftAnkle/rightAnkle`.
- **2D is enough** for rep counting and is lighter. Optionally, `DetectHumanBodyPose3DRequest` (iOS 17+, 3D joints in meters) could improve depth-based form checks later — but it returns only the most prominent person and is heavier; start with 2D.

A clean reference for exactly this SwiftUI + AVCapture + `DetectHumanBodyPoseRequest` live-feed setup exists in public tutorials (createwithswift's "Detecting body poses in a live video feed") — adapt that structure rather than building capture from scratch.

### 5.3 Performance & environment
- **Throttle** with the `isProcessing` guard (above); ~10–15 fps of inference is plenty for slow pushups and saves battery/heat.
- Keep the Vision work off the main actor; deliver results via `AsyncStream`.
- **Dark bedroom:** default to the **front camera** so the screen acts as fill light, bump brightness to max during the challenge, and detect low luminance to prompt repositioning. Make camera placement (side view, phone low) an onboarding step.
- Gate counting on joint confidence; if it drops, **pause and prompt re-framing** rather than miscount.

---

## 6. Rep & form engine (`ChallengeCore` — pure Swift)

Lives in the local Swift Package. Input: a sequence of `PoseFrame`s (timestamp + joint positions/confidences). Output: rep count + form events + status. No AVFoundation, no Vision types leak in — convert at the boundary so this stays pure and testable.

### Rep counting (pushups)
- **Elbow angle** = angle(shoulder → elbow → wrist), averaged over both arms.
- **State machine with hysteresis:** `UP` when elbow angle > ~160°, `DOWN` when < ~90°. Count a rep on a full **UP → DOWN → UP** cycle. The hysteresis gap prevents jitter from double-counting.
- **Reject junk:** minimum rep duration (anti-bounce) and minimum range-of-motion (no half-reps).
- **Smooth** the angle signal (moving average or a One-Euro filter) before thresholding — raw joints jitter frame to frame.

### Form evaluation (lenient by default)
- **Body line** = angle(shoulder → hip → ankle); flag sag/pike outside ~±15–20°.
- **Depth** = require the down phase to cross the DOWN threshold.
- Strictness is a per-alarm setting; default lenient (it's 6am).

### Anti-cheat (in-engine)
A valid rep requires the full body-line pose plus plausible dynamics — defeats arm-waving and static posters (no real UP→DOWN→UP trajectory). Force-quit/reboot users still win; that's handled by the persistence loop, not here.

### Why pure + packaged: testability
Record real sessions (you doing pushups; people gaming it) and serialize the `PoseFrame` stream to **JSON fixtures**. Unit-test `RepCounter`/`FormEvaluator` by replaying fixtures — fully deterministic, runs on the Mac, no device. Build this replay harness in week one; it's what makes counting feel reliable.

---

## 7. Challenge state machine

```
idle
 └─(alarm fires → user taps "Do Pushups")→ initializingCamera
     └─→ detectingUser ─(valid pose, N frames, good confidence)→ counting
         ├─(target met)──────────────→ completed → release (stop, no re-arm, log)
         ├─(confidence lost)─────────→ detectingUser  (pause, prompt reframe)
         ├─(repeated genuine failure)→ escapeOffered   (fallback challenge)
         └─(app backgrounded/timeout)→ abandoned → reArm → idle
 (system Stop tapped, unverified) ───────────────────→ reArm → idle
```

Model the state as a Swift `enum` with associated values inside an `@Observable ChallengeModel`; `ChallengeView` switches on it. `escapeOffered` (math problem / type-a-phrase / scan-a-QR) is the accessibility + don't-trap-legit-users valve — tune leniency carefully **[DECIDE]**.

---

## 8. Data model (SwiftData)

```swift
@Model final class Alarm {
    var id: UUID
    var hour: Int; var minute: Int
    var weekdays: [Int]          // recurring days
    var label: String
    var isEnabled: Bool
    var soundName: String
    var repTarget: Int
    var exerciseType: ExerciseType   // pushup for v1
    var strictness: Strictness
    var snoozePolicy: SnoozePolicy
}

@Model final class ChallengeSession {
    var id: UUID
    var alarmID: UUID
    var startedAt: Date
    var completedAt: Date?
    var repsCompleted: Int
    var targetReps: Int
    var reArmCount: Int
    var escapeUsed: Bool
    var outcome: Outcome          // completed / abandoned / escaped
}
```

Settings as a small `@Model` or `@AppStorage`. No remote storage in MVP — which is also the privacy story (camera data never leaves the device; state that plainly in the App Store privacy label).

---

## 9. Build phases (front-load the risk)

**Phase 0 — Spikes (do these before real UI).**
1. **AlarmKit fires.** Schedule a recurring alarm; confirm it rings through Silent/Focus on a physical iOS 26 device.
2. **Custom button launches the app.** Add the `OpenChallengeIntent` secondary button; confirm tapping it cold-launches into a placeholder `ChallengeView` with the right alarm ID. *(This is the make-or-break integration.)*
3. **Camera → Vision skeleton.** AVCaptureSession → `DetectHumanBodyPoseRequest` → draw 19 joints over the live feed.

**Phase 1 — Vertical MVP.**
4. `RepCounter` over live joints + the JSON-fixture replay test harness.
5. Wire alarm → challenge → rep counting → release, with the persistence loop. End-to-end, ugly but real.
6. SwiftData schema; create/edit/delete alarms; onboarding (camera + alarm permission + 3-rep calibration).

**Phase 2 — Make it good.**
7. Camera-placement helper + low-light handling (front camera, brightness, confidence gating).
8. Form feedback; strictness; snooze rules; escape valve; Live Activity widget extension for a nice Lock Screen/Dynamic Island.
9. History/streaks; polish; haptics; sounds.

**Phase 3 — Ship.**
10. App Store prep: privacy nutrition label (camera, on-device, nothing collected), permission justifications, review notes explaining the alarm-challenge pattern. Paid Developer Program → TestFlight → submit.

*(Android, if ever: only the alarm + camera-capture layers are rewritten; `ChallengeCore` logic is portable in spirit. But that's a separate, later decision.)*

---

## 10. Testing strategy

- **Unit (priority):** `RepCounter` / `FormEvaluator` / `ChallengeStateMachine` via recorded JSON fixtures, including adversarial ones (arm-waving, half-reps, occlusion, two people). Runs on the Mac, no device.
- **Manual device:** the alarm path can only be truly tested on a physical iOS 26 device — schedule, lock the phone, enable a Focus, confirm it rings and the button launches the challenge.
- **Across point releases:** AlarmKit is churning (26.0 → 26.1 changed button behavior), so re-test the alarm flow on each iOS update.

---

## 11. Open decisions

| Decision | Notes |
|---|---|
| **2D vs 3D Vision pose** | Start 2D (lighter, multi-person tolerant). 3D only if depth-based form checks prove necessary. |
| **System vs custom Live Activity** | System fallback for MVP; widget extension for branded Lock Screen/Dynamic Island. |
| **Front vs rear camera default** | Front recommended (screen-as-light in the dark, easier self-framing). |
| **Escape-valve leniency** | Too easy → everyone skips; too hard → trapped users / bad reviews. |
| **iOS floor** | iOS 26 only (AlarmKit). No realistic reliable fallback below it. |
| **Inference fps** | ~10–15 fps; tune per device tier for battery/heat. |

---

*Start at Phase 0, step 2 — the custom AlarmKit button that cold-launches `ChallengeView`. Get that working on your own iPhone and the concept is proven; everything after it is ordinary SwiftUI app-building, all on first-party Apple frameworks you can learn from one set of docs and WWDC videos.*
