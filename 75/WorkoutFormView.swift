
import SwiftUI

struct WorkoutFormView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayEntry
    var state: ChallengeState

    @State private var selectedPreset: WorkoutPreset?
    @State private var minutes: Int = 45
    @State private var outdoor: Bool = false
    @State private var assignToWhich: Int = 1 // 1 or 2

    var body: some View {
        Form {
            Section("Presets") {
                Picker("Preset", selection: $selectedPreset) {
                    Text("None").tag(Optional<WorkoutPreset>.none)
                    ForEach(state.presets) { p in Text(p.name).tag(Optional(p)) }
                }
                .onChange(of: selectedPreset) { p in
                    minutes = p?.defaultMinutes ?? minutes
                    outdoor = p?.outdoor ?? outdoor
                }
            }
            Section("Manual") {
                Stepper("Minutes: \(minutes)", value: $minutes, in: 0...300, step: 5)
                Toggle("Outdoors", isOn: $outdoor)
                Picker("Assign to", selection: $assignToWhich) {
                    Text("Workout 1").tag(1)
                    Text("Workout 2").tag(2)
                }.pickerStyle(.segmented)
            }
            Button("Apply to Day") {
                if assignToWhich == 1 { day.workout1Minutes = minutes; day.workout1Outdoor = outdoor }
                else { day.workout2Minutes = minutes; day.workout2Outdoor = outdoor }
                dismiss()
            }.buttonStyle(.borderedProminent)
        }
        .navigationTitle("Add Workout")
    }
}
