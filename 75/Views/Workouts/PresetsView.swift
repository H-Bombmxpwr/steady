
import SwiftUI
import SwiftData

/// Workouts tab: build workouts (with exercises from the bundled database),
/// then put them on the weekly schedule — in that order.
struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan

    // New workout
    @State private var presetName = ""
    @State private var presetMinutes = 45
    @State private var presetOutdoor = false
    @State private var presetCategory: WorkoutCategory = .strength

    // New schedule entry
    @State private var scheduleSource: String = ""   // preset name, or "" = custom
    @State private var newWeekday = 2 // Monday
    @State private var newName = ""
    @State private var newMinutes = 45
    @State private var newTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!
    @State private var newCategory: WorkoutCategory = .cardio
    @State private var newIntensity: WorkoutIntensity = .moderate

    // Calendar sync feedback
    @State private var syncMessage: String?

    // Searchable picker for the schedule's workout
    @State private var showSchedulePicker = false

    var body: some View {
        NavigationStack {
            Form {
                // --- 1. Build workouts
                Section {
                    if plan.presets.isEmpty {
                        Text("Start here: build a workout, then add it to your week below.")
                            .foregroundStyle(.secondary)
                    } else {
                        // The full list lives one tap in — alphabetized and
                        // searchable, so a growing collection never clogs
                        // this page. Duplicated names show when they were
                        // built.
                        NavigationLink {
                            WorkoutLibraryView(plan: plan)
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet.rectangle.fill")
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("All Workouts").font(.headline)
                                    Text("\(plan.presets.count) built · search, edit, delete")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    NavigationLink {
                        TemplatesView(plan: plan)
                    } label: {
                        Label("Start from a Template", systemImage: "sparkles")
                    }
                } header: {
                    Text("1 · Your Workouts")
                } footer: {
                    Text("Tap a workout to add exercises with sets, reps, and weight from the 870-exercise database.")
                }

                Section("New Workout") {
                    TextField("Name (e.g., Chest Day)", text: $presetName)
                    Picker("Type", selection: $presetCategory) {
                        ForEach(WorkoutCategory.allCases) { c in
                            Label(c.label, systemImage: c.icon).tag(c)
                        }
                    }
                    Stepper("Default minutes: \(presetMinutes)", value: $presetMinutes, in: 5...180, step: 5)
                    Toggle("Outdoors", isOn: $presetOutdoor)
                    Button("Create Workout") {
                        let p = WorkoutPreset(name: presetName.trimmingCharacters(in: .whitespacesAndNewlines),
                                              defaultMinutes: presetMinutes,
                                              outdoor: presetOutdoor, category: presetCategory)
                        plan.presets.append(p)
                        try? context.save()
                        presetName = ""; presetMinutes = 45; presetOutdoor = false; presetCategory = .strength
                    }.disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // --- 2. Weekly schedule
                Section {
                    if plan.schedule.isEmpty {
                        Text("Nothing scheduled yet — pick a workout and a day below.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(plan.schedule.sorted(by: { ($0.weekday, $0.hour) < ($1.weekday, $1.hour) })) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(entry.weekdayName) — \(entry.name)")
                                Text("\(entry.minutes) min · \(entry.intensity.label) at \(entry.timeString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.calendarEventID != nil {
                                Image(systemName: "calendar.badge.checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .onDelete(perform: deleteScheduleEntries)
                } header: {
                    Text("2 · Weekly Schedule")
                } footer: {
                    Text("Workouts only count against your daily goals on scheduled days — everything else is a rest day.")
                }

                Section {
                    Button {
                        showSchedulePicker = true
                    } label: {
                        HStack {
                            Text("Workout").foregroundStyle(.primary)
                            Spacer()
                            Text(scheduleSource.isEmpty ? "Custom…" : scheduleSource)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !scheduleSource.isEmpty {
                        Button("Use a custom name instead") { scheduleSource = "" }
                            .font(.footnote)
                    }
                    if scheduleSource.isEmpty {
                        TextField("Workout (e.g., Upper body, Run)", text: $newName)
                        Stepper("Minutes: \(newMinutes)", value: $newMinutes, in: 5...300, step: 5)
                        Picker("Type", selection: $newCategory) {
                            ForEach(WorkoutCategory.allCases) { c in
                                Label(c.label, systemImage: c.icon).tag(c)
                            }
                        }
                    }
                    Picker("Intensity", selection: $newIntensity) {
                        ForEach(WorkoutIntensity.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Day", selection: $newWeekday) {
                        ForEach(1...7, id: \.self) { d in
                            Text(Calendar.current.weekdaySymbols[d - 1]).tag(d)
                        }
                    }
                    DatePicker("Time", selection: $newTime, displayedComponents: .hourAndMinute)
                    Button("Add to Schedule") { addToSchedule() }
                        .disabled(scheduleSource.isEmpty
                                  && newName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Add to Schedule")
                } footer: {
                    Text("Type and intensity size the fueling plan — carbs per hour during, plus what to eat before and after. Cardio and sports longer than an hour are where mid-workout carbs start to matter.")
                }

                // --- Fueling: the week ahead, and the on-demand calculator
                Section {
                    NavigationLink {
                        WeekFuelView(plan: plan)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Week's Fuel")
                                Text("Day-by-day nutrition for the next 7 days of training")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.foodTint)
                        }
                    }
                    .disabled(plan.schedule.isEmpty)
                    NavigationLink {
                        FuelCalculatorView(plan: plan)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Fuel Calculator")
                                Text("Carbs/hr, fluids, and recovery for any session")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "bolt.fill").foregroundStyle(Theme.foodTint)
                        }
                    }
                } footer: {
                    if plan.schedule.isEmpty {
                        Text("Schedule a workout above and Week's Fuel maps the next seven days of eating around your training.")
                    }
                }

                // --- Calendar sync (local via EventKit — no server involved)
                Section {
                    Button {
                        Task { await syncCalendar() }
                    } label: {
                        Label("Sync Schedule to Calendar", systemImage: "calendar.badge.plus")
                    }
                    .disabled(plan.schedule.isEmpty)
                    if plan.schedule.contains(where: { $0.calendarEventID != nil }) {
                        Button(role: .destructive) {
                            Task { await removeCalendar() }
                        } label: {
                            Label("Remove from Calendar", systemImage: "calendar.badge.minus")
                        }
                    }
                    if let msg = syncMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Adds each scheduled workout to your iPhone calendar as a weekly repeating event. Stored locally in your calendar; re-run after changing the schedule.")
                }
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Workouts")
            .navigationDestination(for: WorkoutPreset.self) { preset in
                WorkoutDetailView(plan: plan, preset: preset)
            }
            .onAppear {
                if scheduleSource.isEmpty, let first = plan.presets.first {
                    scheduleSource = first.name
                }
            }
            .sheet(isPresented: $showSchedulePicker) {
                PresetPickerSheet(plan: plan) { p in
                    scheduleSource = p.name
                }
            }
        }
    }

    private func addToSchedule() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
        let preset = plan.presets.first { $0.name == scheduleSource }
        let name = preset?.name ?? newName.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.schedule.append(WorkoutScheduleEntry(
            weekday: newWeekday,
            name: name,
            minutes: preset?.defaultMinutes ?? newMinutes,
            hour: comps.hour ?? 7,
            minute: comps.minute ?? 0,
            category: preset?.category ?? newCategory,
            intensity: newIntensity))
        try? context.save()
        NotificationManager.rescheduleAll(plan: plan)
        newName = ""
    }

    private func deleteScheduleEntries(_ idx: IndexSet) {
        let sorted = plan.schedule.sorted(by: { ($0.weekday, $0.hour) < ($1.weekday, $1.hour) })
        idx.map { sorted[$0] }.forEach { context.delete($0) }
        try? context.save()
        NotificationManager.rescheduleAll(plan: plan)
    }

    private func syncCalendar() async {
        do {
            let count = try await CalendarSync.sync(plan: plan)
            try? context.save()
            syncMessage = "Added \(count) weekly event\(count == 1 ? "" : "s") to your calendar."
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    private func removeCalendar() async {
        do {
            try await CalendarSync.removeFromCalendar(plan: plan)
            try? context.save()
            syncMessage = "Removed synced events."
        } catch {
            syncMessage = error.localizedDescription
        }
    }
}

// MARK: - Templates

struct TemplatesView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    @State private var added: Set<String> = []

    var body: some View {
        Form {
            ForEach(WorkoutTemplates.programs) { program in
                Section {
                    ForEach(program.workouts) { t in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.headline)
                                Text(t.summary).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if added.contains(t.name) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            } else {
                                Button("Add") {
                                    WorkoutTemplates.apply(t, to: plan)
                                    try? context.save()
                                    added.insert(t.name)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } header: {
                    Text(program.name)
                } footer: {
                    Text(program.summary)
                }
            }
        }
        .themedForm()
        .navigationTitle("Templates")
    }
}

// MARK: - Workout (preset) editor

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    @Bindable var preset: WorkoutPreset

    @State private var showExercisePicker = false
    @State private var scheduleWeekday = 2
    @State private var scheduleTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!
    @State private var scheduledConfirm: String?

    var body: some View {
        Form {
            Section("Workout") {
                TextField("Name", text: $preset.name)
                Picker("Type", selection: Binding(get: { preset.category }, set: { preset.category = $0 })) {
                    ForEach(WorkoutCategory.allCases) { c in
                        Label(c.label, systemImage: c.icon).tag(c)
                    }
                }
                Stepper("Default minutes: \(preset.defaultMinutes)",
                        value: $preset.defaultMinutes, in: 5...180, step: 5)
                Toggle("Outdoors", isOn: $preset.outdoor)
            }

            Section {
                ForEach(preset.orderedExercises) { ex in
                    NavigationLink {
                        PresetExerciseEditor(plan: plan, exercise: ex)
                    } label: {
                        HStack {
                            Text(ex.name).lineLimit(2)
                            Spacer()
                            Text(ex.targetText)
                                .font(.caption.bold())
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                .onDelete { idx in
                    let ordered = preset.orderedExercises
                    idx.map { ordered[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add Exercise", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text(preset.exercises.isEmpty
                     ? "Search 870+ exercises by name or muscle. Sets, reps, and weight become the pre-fill when you log this workout."
                     : "Tap an exercise for targets, instructions, and your progress history.")
            }

            Section {
                Picker("Day", selection: $scheduleWeekday) {
                    ForEach(1...7, id: \.self) { d in
                        Text(Calendar.current.weekdaySymbols[d - 1]).tag(d)
                    }
                }
                DatePicker("Time", selection: $scheduleTime, displayedComponents: .hourAndMinute)
                Button {
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: scheduleTime)
                    plan.schedule.append(WorkoutScheduleEntry(
                        weekday: scheduleWeekday,
                        name: preset.name,
                        minutes: preset.defaultMinutes,
                        hour: comps.hour ?? 7,
                        minute: comps.minute ?? 0))
                    try? context.save()
                    NotificationManager.rescheduleAll(plan: plan)
                    scheduledConfirm = "Added to \(Calendar.current.weekdaySymbols[scheduleWeekday - 1])s."
                } label: {
                    Label("Add to Weekly Schedule", systemImage: "calendar.badge.plus")
                }
                if let msg = scheduledConfirm {
                    Text(msg).font(.footnote).foregroundStyle(Theme.accent)
                }
            } header: {
                Text("Schedule")
            }
        }
        .themedForm()
        .keyboardDoneButton()
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView { exercise in
                let next = (preset.exercises.map(\.orderIndex).max() ?? -1) + 1
                preset.exercises.append(PresetExercise(name: exercise.name, orderIndex: next))
                try? context.save()
            }
            .themedRoot()
        }
        .onDisappear { try? context.save() }
    }
}

// MARK: - Exercise picker (bundled database)

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (Exercise) -> Void

    @State private var query = ""
    @State private var muscle: String?

    private var results: [Exercise] {
        ExerciseDatabase.shared.search(query, muscle: muscle)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { ex in
                    Button {
                        onPick(ex)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).foregroundStyle(.primary).lineLimit(2)
                            Text(ex.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises (e.g. squat)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("All muscles") { muscle = nil }
                        ForEach(ExerciseDatabase.shared.muscleGroups, id: \.self) { m in
                            Button(m.capitalized) { muscle = m }
                        }
                    } label: {
                        Label(muscle?.capitalized ?? "Muscle",
                              systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}

// MARK: - Per-exercise targets, instructions, history

struct PresetExerciseEditor: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    @Bindable var exercise: PresetExercise

    private var dbEntry: Exercise? { ExerciseDatabase.shared.byName(exercise.name) }

    var body: some View {
        Form {
            Section("Targets") {
                Stepper("Sets: \(exercise.sets)", value: $exercise.sets, in: 1...12)
                Stepper("Reps: \(exercise.reps)", value: $exercise.reps, in: 1...50)
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("bodyweight", value: $exercise.weightLbs, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    Text("lb").foregroundStyle(.secondary)
                }
            }

            ExerciseHistorySection(plan: plan, exerciseName: exercise.name)

            if let db = dbEntry {
                Section("How To — \(db.muscles)") {
                    ForEach(Array(db.i.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).").bold().foregroundStyle(Theme.accent)
                            Text(step)
                        }
                        .font(.footnote)
                    }
                }
            }
        }
        .themedForm()
        .keyboardDoneButton()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
    }
}
