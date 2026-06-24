import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \ChallengeSession.startedAt, order: .reverse) private var sessions: [ChallengeSession]

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "chart.bar",
                                           description: Text("Your wake-up history shows up here."))
                } else {
                    Section {
                        LabeledContent("Completed", value: "\(completedCount)")
                        LabeledContent("Total pushups", value: "\(totalReps)")
                    }
                    Section("Recent") {
                        ForEach(sessions) { session in
                            SessionRow(session: session)
                        }
                    }
                }
            }
            .navigationTitle("History")
        }
    }

    private var completedCount: Int { sessions.filter { $0.outcome == .completed }.count }
    private var totalReps: Int { sessions.reduce(0) { $0 + $1.repsCompleted } }
}

private struct SessionRow: View {
    let session: ChallengeSession

    var body: some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading) {
                Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                Text("\(session.repsCompleted)/\(session.targetReps) reps")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if session.reArmCount > 0 {
                Text("\(session.reArmCount)× re-armed").font(.caption2).foregroundStyle(.orange)
            }
        }
    }

    private var icon: String {
        switch session.outcome {
        case .completed: return "checkmark.circle.fill"
        case .abandoned: return "xmark.circle.fill"
        case .escaped: return "figure.walk.circle.fill"
        case .inProgress: return "clock.fill"
        }
    }
    private var color: Color {
        switch session.outcome {
        case .completed: return .green
        case .abandoned: return .red
        case .escaped: return .orange
        case .inProgress: return .secondary
        }
    }
}
