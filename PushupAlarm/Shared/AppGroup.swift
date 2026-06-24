import Foundation

/// Cross-process shared state (app ↔ widget ↔ App Intent). Backed by an App
/// Group `UserDefaults` suite when available, falling back to `.standard` so the
/// project builds and runs without the paid Developer Program (no App Group
/// provisioning). Swap nothing when you enroll — the suite just starts working.
final class SharedState: @unchecked Sendable {
    static let shared = SharedState()

    static let appGroupID = "group.com.wakeupcall.pushupalarm"

    private let defaults: UserDefaults

    /// True when the real App Group container is in use (paid account + correct
    /// entitlements). Useful for surfacing setup state during development.
    let usingAppGroup: Bool

    private init() {
        if let suite = UserDefaults(suiteName: Self.appGroupID) {
            defaults = suite
            usingAppGroup = true
        } else {
            defaults = .standard
            usingAppGroup = false
        }
    }

    private enum Key {
        static let pendingAlarmID = "pendingChallengeAlarmID"
    }

    /// The alarm whose challenge should open. Set by `OpenChallengeIntent` (in a
    /// separate process) and read by the app on launch/foreground.
    var pendingAlarmID: String? {
        get { defaults.string(forKey: Key.pendingAlarmID) }
        set { defaults.set(newValue, forKey: Key.pendingAlarmID) }
    }
}
