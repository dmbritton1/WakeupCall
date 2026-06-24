# Pushup Alarm

An iOS-first alarm app that won't fully turn off until you do your pushups. The
camera counts reps on-device with Apple Vision; the alarm rings through
Silent/Focus via AlarmKit.

Native, all-Apple stack: **Swift 6 + SwiftUI + Vision + AlarmKit + SwiftData**.
See [`pushup-alarm-ios-native-plan.md`](pushup-alarm-ios-native-plan.md) for the
full architecture plan this is built from.

## Project layout

```
WakeupCall/
├── ChallengeCore/            Pure-Swift SwiftPM package — the rep/form engine.
│   ├── Sources/ChallengeCore/  Geometry, RepCounter, FormEvaluator,
│   │                           ChallengeStateMachine, PoseFixture replay.
│   └── Tests/                 34 tests, run on the Mac with no simulator/device.
├── PushupAlarm/              The app target (SwiftUI).
│   ├── App/                  App entry + notification delegate.
│   ├── Models/               SwiftData @Model types (Alarm, ChallengeSession).
│   ├── Alarm/                AlarmScheduling protocol + AlarmKit & local-notif
│   │                         backends + AlarmCoordinator (persistence loop).
│   ├── Pose/                 AVFoundation capture + Vision → PoseFrame mapping.
│   ├── Challenge/            ChallengeModel (wires camera→engine→state machine).
│   ├── Shared/              App Group abstraction + deep-link router.
│   └── Views/                SwiftUI screens.
├── PushupAlarmWidget/        Widget extension (Live Activity placeholder).
├── project.yml               XcodeGen project definition (source of truth).
└── PushupAlarm.xcodeproj     Generated from project.yml.
```

## Build status

- ✅ **`ChallengeCore`** — fully implemented & tested (`cd ChallengeCore && swift test`).
- ✅ **App + widget** — type-check clean against the iOS 26.4 SDK. The default
  build uses a **local-notification** alarm backend so it runs without the paid
  Developer Program.
- ⏳ **On-device verification pending** — the AlarmKit alarm path and camera
  rep-counting can only be truly tested on a physical iOS 26 device (see below).

## Running it

### Prerequisites
- Xcode 26 with the **iOS 26 platform component** installed
  (Xcode → Settings → Components). The build SDK alone is not enough to target a
  device or simulator.
- A physical iOS 26 device for the alarm + camera paths (simulator can't fully
  present alarms and has no camera).

### Generate & open
```bash
brew install xcodegen      # once
xcodegen generate          # regenerate the .xcodeproj after editing project.yml
open PushupAlarm.xcodeproj
```
Set your Signing Team on the `PushupAlarm` target, then build to your device.

### Free Apple account vs. paid
The App Group entitlement is **omitted by default** so the app signs with a free
Apple ID. `SharedState` falls back to standard `UserDefaults`, and the app uses
the local-notification backend — enough to exercise the challenge flow.

To enable the real AlarmKit alarm (rings through Silent/Focus, custom Lock
Screen button):
1. Enroll in the Apple Developer Program ($99).
2. Re-add the App Group entitlement (see `PushupAlarm/PushupAlarm.entitlements`
   and the note in `project.yml`), and add the same group to the widget target.
3. Swap `LocalNotificationScheduler()` for `AlarmKitScheduler()` in
   `PushupAlarm/App/PushupAlarmApp.swift`.

## Testing the engine
```bash
cd ChallengeCore
swift test
```
The engine is tested by replaying recorded pose streams from JSON fixtures
(`Tests/ChallengeCoreTests/Fixtures/`). Add adversarial recordings
(arm-waving, half-reps, occlusion) as new fixtures to harden rep counting.
