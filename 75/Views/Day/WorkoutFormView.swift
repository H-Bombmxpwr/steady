
import SwiftUI

/// Log any workout — scheduled or not, as many per day as you like.
/// Picking a preset pre-fills its exercises; edit reps/weight to match what
/// you actually did, and the sets feed each exercise's progress history.
struct WorkoutFormView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog
    var plan: Plan

    @State private var selectedPreset: WorkoutPreset?
    @State private var name: String = ""
    @State private var minutes: Int = 45
    @State private var outdoor: Bool = false
    @State private var category: WorkoutCategory = .strength

    @State private var entries: [ExerciseEntry] = []
    @State private var showExercisePicker = false
    @State private var showPresetPicker = false

    struct SetEntry: Identifiable {
        let id = UUID()
        var reps: Int
        var weight: Double?
    }

    struct ExerciseEntry: Identifiable {
        let id = UUID()
        var name: String
        var sets: [SetEntry]
    }

    var body: some View {
        Form {
            if !plan.presets.isEmpty {
                Section("Presets") {
                    // A button into the searchable alphabetized picker — the
                    // inline Picker menu became a giant unusable list once
                    // the workout collection grew.
                    Button {
                        showPresetPicker = true
                    } label: {
                        HStack {
                            Label(selectedPreset?.name ?? "Choose a Workout",
                                  systemImage: selectedPreset?.category.icon ?? "list.bullet")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if selectedPreset != nil {
                        Button("Clear preset", role: .destructive) {
                            selectedPreset = nil
                        }
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

            ForEach($entries) { $entry in
                Section {
                    ForEach(Array($entry.sets.enumerated()), id: \.element.id) { index, $set in
                        HStack {
                            Text("Set \(index + 1)")
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .leading)
                            TextField("reps", value: $set.reps, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                            Text("reps ×").font(.caption).foregroundStyle(.secondary)
                            TextField("bw", value: $set.weight, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                            Text("lb").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in entry.sets.remove(atOffsets: idx) }
                    HStack {
                        Button {
                            let last = entry.sets.last
                            entry.sets.append(SetEntry(reps: last?.reps ?? 10, weight: last?.weight))
                        } label: {
                            Label("Add Set", systemImage: "plus")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Button(role: .destructive) {
                            entries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text(entry.name)
                }
            }

            Section {
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                }
            } footer: {
                entries.isEmpty
                    ? Text("Optional: add exercises to log sets, reps, and weight.")
                    : Text("Swipe a set to delete it. Leave weight empty for bodyweight.")
            }

            Button("Log Workout") { logWorkout() }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .themedForm()
        .keyboardDoneButton()
        .navigationTitle("Add Workout")
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView { exercise in
                entries.append(ExerciseEntry(
                    name: exercise.name,
                    sets: (0..<3).map { _ in SetEntry(reps: 10, weight: nil) }))
            }
            .themedRoot()
        }
        .sheet(isPresented: $showPresetPicker) {
            PresetPickerSheet(plan: plan) { p in
                selectedPreset = p
                name = p.name
                minutes = p.defaultMinutes
                outdoor = p.outdoor
                category = p.category
                entries = p.orderedExercises.map { ex in
                    ExerciseEntry(name: ex.name,
                                  sets: (0..<max(1, ex.sets)).map { _ in
                                      SetEntry(reps: ex.reps, weight: ex.weightLbs)
                                  })
                }
            }
        }
    }

    private func logWorkout() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = WorkoutLog(name: trimmed, minutes: minutes, outdoor: outdoor, category: category)
        for entry in entries {
            for (index, set) in entry.sets.enumerated() where set.reps > 0 {
                log.sets.append(SetLog(exerciseName: entry.name, setIndex: index,
                                       reps: set.reps, weightLbs: set.weight))
            }
        }
        day.workouts.append(log)
        let date = day.date
        Task { await HealthKitService.shared.saveWorkout(log, on: date) }
        dismiss()
    }
}
