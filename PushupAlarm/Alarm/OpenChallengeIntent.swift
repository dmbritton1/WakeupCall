import AppIntents

/// Runs when the user taps the alarm's custom "Do Pushups" button. It executes
/// in a separate process from the app, so it hands the alarm ID off through the
/// App Group; the app picks it up on launch/foreground and presents the
/// challenge (plan §4.2).
///
/// Churn caveat (plan §4.2): the exact mechanism for launching the app from an
/// alarm button is new and shifting across iOS 26 point releases. Verify the
/// `LiveActivityIntent` requirements against the current SDK on device.
struct OpenChallengeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Do Pushups" }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Alarm ID")
    var alarmID: String

    init() {}

    init(alarmID: String) {
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        SharedState.shared.pendingAlarmID = alarmID
        return .result()
    }
}
