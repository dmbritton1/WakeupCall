import SwiftUI
import SwiftData
import UserNotifications

@main
struct PushupAlarmApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var router = ChallengeRouter()
    @State private var coordinator: AlarmCoordinator

    private let container: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Alarm.self, ChallengeSession.self)
        } catch {
            // Last-resort in-memory store so the app still launches.
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: Alarm.self, ChallengeSession.self, configurations: config)
        }
        self.container = container

        // Default to the dev-friendly local-notification backend. Swap in
        // `AlarmKitScheduler()` once running on a device with the paid account.
        let scheduler = LocalNotificationScheduler()
        scheduler.registerCategories()
        _coordinator = State(initialValue: AlarmCoordinator(scheduler: scheduler, context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(coordinator)
                .modelContainer(container)
                .task {
                    router.consumePendingFromSharedState()
                    await coordinator.reArmUnfinishedIfNeeded()
                }
        }
    }
}

/// Bridges UNUserNotificationCenter into the app. When the user taps the
/// "Do Pushups" action (the dev fallback for the AlarmKit button), it stashes
/// the alarm ID in shared state; the app picks it up when it becomes active
/// (see `RootView`'s scenePhase handling).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let id = info[LocalNotificationScheduler.alarmIDKey] as? String else { return }
        SharedState.shared.pendingAlarmID = id
    }

    /// Show the alarm even when the app is foregrounded.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
