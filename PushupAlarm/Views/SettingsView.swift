import SwiftUI

struct SettingsView: View {
    @Environment(AlarmCoordinator.self) private var coordinator
    @State private var alarmAuthorized: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section("Permissions") {
                    Button("Request alarm permission") {
                        Task { alarmAuthorized = await coordinator.requestAuthorization() }
                    }
                    if let alarmAuthorized {
                        LabeledContent("Alarm authorized", value: alarmAuthorized ? "Yes" : "No")
                    }
                }

                Section("Setup status") {
                    LabeledContent("App Group active",
                                   value: SharedState.shared.usingAppGroup ? "Yes" : "No (UserDefaults fallback)")
                    if !SharedState.shared.usingAppGroup {
                        Text("Enroll in the Apple Developer Program and provision the App Group to enable the AlarmKit alarm path.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Privacy") {
                    Text("Camera frames are processed on-device for rep counting and never leave your phone. No account, no servers.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}
