import Foundation
import Observation

/// In-process deep-link router. The alarm button (App Intent) writes the pending
/// alarm ID into the App Group; on launch/foreground the app moves it here so
/// SwiftUI can present the challenge.
@MainActor
@Observable
final class ChallengeRouter {
    /// The alarm whose challenge should be shown, if any.
    var pendingAlarmID: UUID?

    /// Pull any pending challenge handed over by the App Intent across processes.
    func consumePendingFromSharedState() {
        guard let raw = SharedState.shared.pendingAlarmID,
              let uuid = UUID(uuidString: raw) else { return }
        SharedState.shared.pendingAlarmID = nil
        pendingAlarmID = uuid
    }

    func clear() {
        pendingAlarmID = nil
    }
}
