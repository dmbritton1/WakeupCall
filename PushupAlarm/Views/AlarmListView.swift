import SwiftUI
import SwiftData

struct AlarmListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AlarmCoordinator.self) private var coordinator
    @Query(sort: \Alarm.hour) private var alarms: [Alarm]

    @State private var editing: Alarm?
    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                if alarms.isEmpty {
                    ContentUnavailableView(
                        "No alarms",
                        systemImage: "alarm",
                        description: Text("Add a wake-up that makes you do pushups."))
                }
                ForEach(alarms) { alarm in
                    AlarmRow(alarm: alarm, isEnabled: Binding(
                        get: { alarm.isEnabled },
                        set: { isOn in
                            alarm.isEnabled = isOn
                            try? context.save()
                            Task { await refresh() }
                        }))
                    .contentShape(Rectangle())
                    .onTapGesture { editing = alarm; showingEditor = true }
                }
                .onDelete(perform: delete)
            }
            .navigationTitle("Alarms")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editing = nil; showingEditor = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingEditor) {
                AlarmEditorView(alarm: editing) { Task { await refresh() } }
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let alarm = alarms[index]
            Task { await coordinator.disable(alarm) }
            context.delete(alarm)
        }
        try? context.save()
    }

    private func refresh() async {
        await coordinator.refreshSchedules(alarms)
    }
}

private struct AlarmRow: View {
    let alarm: Alarm
    @Binding var isEnabled: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "%02d:%02d", alarm.hour, alarm.minute))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                Text("\(alarm.label) · \(alarm.repTarget) pushups · \(weekdaySummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var weekdaySummary: String {
        guard !alarm.weekdays.isEmpty else { return "Once" }
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return alarm.weekdays.sorted().compactMap { symbols[safe: $0 - 1] }.joined(separator: " ")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
