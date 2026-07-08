
import SwiftUI

/// Log any workout — scheduled or not, as many per day as you like.
struct WorkoutFormView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog
    var plan: Plan

    @State private var selectedPreset: WorkoutPreset?
    @State private var name: String = ""
    @State private var minutes: Int = 45
    @State private var outdoor: Bool = false
    @State private var category: WorkoutCategory = .strength

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
                        category = p.category
                    }
                }
            }
            Section("Workout") {
                TextField("Name (e.g., Upper body, Run)", text: $name)
                Picker("Type", selection: $category) {
                    ForEach(WorkoutCategory.allCases) { c in
                        Label(c.label, systemImage: c.icon).tag(c)
                    }
                }
                Stepper("Minutes: \(minutes)", value: $minutes, in: 5...300, step: 5)
                Toggle("Outdoors", isOn: $outdoor)
            }
            Button("Log Workout") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let log = WorkoutLog(name: trimmed, minutes: minutes, outdoor: outdoor, category: category)
                day.workouts.append(log)
                let date = day.date
                Task { await HealthKitService.shared.saveWorkout(log, on: date) }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .themedForm()
        .navigationTitle("Add Workout")
    }
}
