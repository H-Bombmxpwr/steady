
import SwiftUI

struct WorkoutFormView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog
    var plan: Plan

    @State private var selectedPreset: WorkoutPreset?
    @State private var name: String = ""
    @State private var minutes: Int = 45
    @State private var outdoor: Bool = false

    var body: some View {
        Form {
            if !plan.presets.isEmpty {
                Section("Presets") {
                    Picker("Preset", selection: $selectedPreset) {
                        Text("None").tag(Optional<WorkoutPreset>.none)
                        ForEach(plan.presets) { p in Text(p.name).tag(Optional(p)) }
                    }
                    .onChange(of: selectedPreset) { p in
                        guard let p else { return }
                        name = p.name
                        minutes = p.defaultMinutes
                        outdoor = p.outdoor
                    }
                }
            }
            Section("Workout") {
                TextField("Name (e.g., Upper body, Run)", text: $name)
                Stepper("Minutes: \(minutes)", value: $minutes, in: 5...300, step: 5)
                Toggle("Outdoors", isOn: $outdoor)
            }
            Button("Log Workout") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                day.workouts.append(WorkoutLog(name: trimmed, minutes: minutes, outdoor: outdoor))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .navigationTitle("Add Workout")
    }
}
