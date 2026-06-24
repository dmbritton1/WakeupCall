import SwiftUI
import SwiftData

/// Tab shell. Owns the deep-link presentation: when the router has a pending
/// alarm (set by the alarm button / notification action), the challenge takes
/// over full-screen.
struct RootView: View {
    @Environment(ChallengeRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query private var alarms: [Alarm]

    var body: some View {
        TabView {
            Tab("Alarms", systemImage: "alarm") {
                AlarmListView()
            }
            Tab("History", systemImage: "chart.bar") {
                HistoryView()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsView()
            }
        }
        .fullScreenCover(isPresented: isPresenting) {
            if let alarm = alarms.first(where: { $0.id == router.pendingAlarmID }) {
                ChallengeView(alarm: alarm)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A notification action (or AlarmKit button) may have stashed a
            // pending challenge while we were backgrounded — pick it up.
            if phase == .active { router.consumePendingFromSharedState() }
        }
    }

    private var isPresenting: Binding<Bool> {
        Binding(
            get: { router.pendingAlarmID != nil },
            set: { presenting in if !presenting { router.clear() } }
        )
    }
}
