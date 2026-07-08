
import SwiftUI
import SwiftData

struct PresetsView: View {
    @Environment(\.modelContext) private var context
    var state: ChallengeState
    @State private var name = ""
    @State private var minutes = 45
    @State private var outdoor = false
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("New Preset") {
                    TextField("Name (e.g., Chest Day)", text: $name)
                    Stepper("Default minutes: \(minutes)", value: $minutes, in: 5...180, step: 5)
                    Toggle("Outdoors", isOn: $outdoor)
                    TextField("Notes", text: $notes)
                    Button("Add Preset") {
                        let p = WorkoutPreset(name: name, defaultMinutes: minutes, outdoor: outdoor, notes: notes.isEmpty ? nil : notes)
                        state.presets.append(p)
                        try? context.save()
                        name = ""; minutes = 45; outdoor = false; notes = ""
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Existing Presets") {
                    if state.presets.isEmpty { Text("No presets yet.").foregroundStyle(.secondary) }
                    ForEach(state.presets) { p in
                        VStack(alignment: .leading) {
                            Text(p.name).font(.headline)
                            HStack { Text("\(p.defaultMinutes) min"); if p.outdoor { Text("outdoor") } }
                            if let n = p.notes, !n.isEmpty { Text(n).foregroundStyle(.secondary) }
                        }
                    }
                    .onDelete { idx in
                        idx.map { state.presets[$0] }.forEach { context.delete($0) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("Workout Presets")
        }
    }
}
