import SwiftUI
import SwiftData

/// Add or edit a dated session by hand — the path for anyone not on
/// TrainingPeaks, and for the session the plan didn't know about.
struct PlannedWorkoutFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let plan: Plan
    var date: Date = Calendar.current.startOfDay(for: Date())
    var existing: PlannedWorkout?

    @State private var name = ""
    @State private var day = Date()
    @State private var minutes = 60
    @State private var time = Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!
    @State private var category: WorkoutCategory = .cardio
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var details = ""

    @FocusState private var focused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fuelingPreview: FuelingPlan {
        FuelingEngine.plan(category: category, intensity: intensity, minutes: minutes,
                           bodyweightLbs: plan.currentWeight,
                           sweat: plan.sweatProfile(matching: category, intensity: intensity),
                           weather: plan.weatherAwareFueling
                               ? WeatherService.shared.effective : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Long Ride, Track Session)", text: $name)
                        .focused($focused)
                    DatePicker("Date", selection: $day, displayedComponents: .date)
                    DatePicker("Start", selection: $time, displayedComponents: .hourAndMinute)
                    Stepper("Duration: \(minutes) min", value: $minutes, in: 5...480, step: 5)
                }

                Section {
                    Picker("Type", selection: $category) {
                        ForEach(WorkoutCategory.allCases) { c in
                            Label(c.label, systemImage: c.icon).tag(c)
                        }
                    }
                    Picker("Intensity", selection: $intensity) {
                        ForEach(WorkoutIntensity.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(intensity.cue).font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("How hard")
                } footer: {
                    Text("Type and intensity are what the fueling math runs on — they decide whether you need carbs during the session or only around it.")
                }

                Section {
                    Text(fuelingPreview.headline).font(.callout)
                    Text(fuelingPreview.carbRationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("Fluid")
                        Spacer()
                        Text("\(fuelingPreview.fluidOzPerHour) oz/hr")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Estimated burn")
                        Spacer()
                        Text("\(fuelingPreview.burnCalories) cal")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(icon: "bolt.fill", title: "Fuel for this", tint: Theme.foodTint)
                }

                Section("Notes") {
                    TextField("The session, in your own words", text: $details, axis: .vertical)
                        .lineLimit(2...6)
                        .focused($focused)
                }

                if let existing {
                    Section {
                        Button(role: .destructive) { delete(existing) } label: {
                            Label("Delete session", systemImage: "trash")
                        }
                    } footer: {
                        if existing.isImported {
                            Text("This came from TrainingPeaks. Deleting it here removes it until the next sync puts it back — remove it in TrainingPeaks to make it stick.")
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle(existing == nil ? "Add Session" : "Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(trimmedName.isEmpty)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .themedRoot()
        .onAppear(perform: load)
    }

    private func load() {
        if let existing {
            name = existing.name
            day = existing.date
            minutes = existing.minutes
            time = Calendar.current.date(from: DateComponents(hour: existing.hour,
                                                              minute: existing.minute)) ?? time
            category = existing.category
            intensity = existing.intensity
            details = existing.details ?? ""
        } else {
            day = date
        }
    }

    private func save() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        let target = existing ?? {
            let new = PlannedWorkout(date: day, name: trimmedName)
            plan.plannedWorkouts.append(new)
            return new
        }()
        target.date = Calendar.current.startOfDay(for: day)
        target.name = trimmedName
        target.minutes = minutes
        target.hour = comps.hour ?? 7
        target.minute = comps.minute ?? 0
        target.category = category
        target.intensity = intensity
        target.details = details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : details
        try? context.save()
        Haptics.success()
        dismiss()
    }

    private func delete(_ workout: PlannedWorkout) {
        plan.plannedWorkouts.removeAll { $0.persistentModelID == workout.persistentModelID }
        context.delete(workout)
        try? context.save()
        dismiss()
    }
}
