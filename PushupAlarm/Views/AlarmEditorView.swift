import SwiftUI
import SwiftData
import ChallengeCore

/// Create or edit an alarm. Pass `nil` to create.
struct AlarmEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let alarm: Alarm?
    let onSave: () -> Void

    @State private var time = Date()
    @State private var label = "Wake up"
    @State private var repTarget = 10
    @State private var strictness: Strictness = .lenient
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var snooze: SnoozePolicy = .none

    private let weekdaySymbols = Calendar.current.shortWeekdaySymbols

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)

                Section("Repeat") {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            DayToggle(symbol: weekdaySymbols[day - 1],
                                      isOn: weekdays.contains(day)) {
                                if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                            }
                        }
                    }
                }

                Section("Challenge") {
                    Stepper("Pushups: \(repTarget)", value: $repTarget, in: 1...100)
                    Picker("Strictness", selection: $strictness) {
                        ForEach(Strictness.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Picker("Snooze", selection: $snooze) {
                        Text("None").tag(SnoozePolicy.none)
                        Text("One short snooze").tag(SnoozePolicy.onceShort)
                    }
                }

                Section {
                    TextField("Label", text: $label)
                }
            }
            .navigationTitle(alarm == nil ? "New Alarm" : "Edit Alarm")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let alarm else { return }
        var comps = DateComponents()
        comps.hour = alarm.hour; comps.minute = alarm.minute
        time = Calendar.current.date(from: comps) ?? Date()
        label = alarm.label
        repTarget = alarm.repTarget
        strictness = alarm.strictness
        weekdays = Set(alarm.weekdays)
        snooze = alarm.snoozePolicy
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let target = alarm ?? Alarm()
        target.hour = comps.hour ?? 6
        target.minute = comps.minute ?? 30
        target.label = label
        target.repTarget = repTarget
        target.strictness = strictness
        target.weekdays = weekdays.sorted()
        target.snoozePolicy = snooze
        target.isEnabled = true
        if alarm == nil { context.insert(target) }
        try? context.save()
        onSave()
        dismiss()
    }
}

private struct DayToggle: View {
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(symbol.prefix(2))
                .font(.caption.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(isOn ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
