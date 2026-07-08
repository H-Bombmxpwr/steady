import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var plan: Plan
    @Bindable var profile: UserProfile

    // Share sheet for the JSON backup
    @State private var exportURL: URL?
    @State private var presentShare = false
    @State private var showEraseConfirm = false

    // Notification settings
    @AppStorage(NotificationManager.Keys.weighInEnabled) private var weighInEnabled = true
    @AppStorage(NotificationManager.Keys.weighInHour) private var weighInHour = 8
    @AppStorage(NotificationManager.Keys.hydrationEnabled) private var hydrationEnabled = true
    @AppStorage(NotificationManager.Keys.hydrationTimes) private var hydrationTimes = "11:00,15:00,19:00"
    @AppStorage(NotificationManager.Keys.workoutEnabled) private var workoutEnabled = true
    @AppStorage(NotificationManager.Keys.workoutLeadMinutes) private var workoutLead = 30
    @AppStorage(NotificationManager.Keys.streakEnabled) private var streakEnabled = true
    @AppStorage(NotificationManager.Keys.streakHour) private var streakHour = 20
    @AppStorage(NotificationManager.Keys.streakMinute) private var streakMinute = 30

    // Appearance
    @AppStorage(Theme.paletteKey) private var themePalette = ThemePalette.emerald.rawValue
    @AppStorage(Theme.modeKey) private var themeMode = ThemeMode.dark.rawValue

    // Apple Health
    @AppStorage(HealthKitService.enabledKey) private var healthEnabled = false
    @State private var healthMessage: String?

    // New supplement
    @State private var supplementName = ""
    @State private var supplementTime = Calendar.current.date(from: DateComponents(hour: 8, minute: 0))!
    @State private var supplementFrequency: Supplement.Frequency = .daily
    @State private var supplementWeekday = 2

    @FocusState private var fieldFocused: Bool

    private let paces: [Double] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            Form {
                // --- Goal
                Section("Goal") {
                    HStack { Text("Started"); Spacer(); Text(plan.startDate, style: .date).foregroundStyle(.secondary) }
                    HStack {
                        Text("Goal weight")
                        Spacer()
                        TextField("lb", value: $plan.goalWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($fieldFocused)
                        Text("lb").foregroundStyle(.secondary)
                    }
                    Picker("Pace", selection: $plan.paceLbsPerWeek) {
                        ForEach(paces, id: \.self) { p in
                            Text(String(format: "%.1f lb / week", p)).tag(p)
                        }
                    }
                }

                // --- Daily targets
                Section("Daily Targets") {
                    let targets = CalorieEngine.targets(profile: profile, plan: plan)
                    HStack {
                        Text("Calorie budget")
                        Spacer()
                        Text("\(targets.calories) cal").foregroundStyle(.secondary)
                    }
                    Toggle("Override budget", isOn: Binding(
                        get: { plan.calorieBudgetOverride != nil },
                        set: { on in
                            plan.calorieBudgetOverride = on ? targets.calories : nil
                        }
                    ))
                    if plan.calorieBudgetOverride != nil {
                        HStack {
                            Text("Custom budget")
                            Spacer()
                            TextField("cal", value: Binding(
                                get: { plan.calorieBudgetOverride ?? 0 },
                                set: { plan.calorieBudgetOverride = max(800, $0) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($fieldFocused)
                        }
                    }
                    Stepper("Protein target: \(plan.proteinTargetGrams) g",
                            value: $plan.proteinTargetGrams, in: 40...400, step: 5)
                    Stepper("Water goal: \(plan.waterGoalOunces) oz",
                            value: $plan.waterGoalOunces, in: 32...256, step: 8)
                    Stepper(value: Binding(
                        get: { max(1, plan.waterStepOunces) },
                        set: { plan.waterStepOunces = max(1, min($0, 256)) }
                    ), in: 1...256) {
                        HStack {
                            Text("Water log step")
                            Spacer()
                            Text("\(plan.waterStepOunces) oz").foregroundStyle(.secondary)
                        }
                    }
                }

                // --- Supplements
                Section {
                    ForEach(plan.supplements) { s in
                        HStack {
                            Text(s.name)
                            Spacer()
                            Text(s.timeString).foregroundStyle(.secondary)
                            Toggle("", isOn: Binding(get: { s.remind }, set: { s.remind = $0; reschedule() }))
                                .labelsHidden()
                        }
                    }
                    .onDelete { idx in
                        idx.map { plan.supplements[$0] }.forEach { context.delete($0) }
                        try? context.save()
                        reschedule()
                    }
                    TextField("Add (e.g., Creatine)", text: $supplementName)
                    Picker("Frequency", selection: $supplementFrequency) {
                        ForEach(Supplement.Frequency.allCases) { Text($0.label).tag($0) }
                    }
                    if supplementFrequency == .weekly {
                        Picker("Day", selection: $supplementWeekday) {
                            ForEach(1...7, id: \.self) { d in
                                Text(Calendar.current.weekdaySymbols[d - 1]).tag(d)
                            }
                        }
                    }
                    DatePicker("Reminder time", selection: $supplementTime, displayedComponents: .hourAndMinute)
                    Button {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: supplementTime)
                        plan.supplements.append(Supplement(
                            name: supplementName.trimmingCharacters(in: .whitespacesAndNewlines),
                            hour: comps.hour ?? 8,
                            minute: comps.minute ?? 0,
                            frequency: supplementFrequency,
                            weekday: supplementWeekday))
                        try? context.save()
                        supplementName = ""
                        reschedule()
                    } label: {
                        Label("Add Supplement", systemImage: "plus.circle.fill")
                    }
                    .disabled(supplementName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Supplements")
                } footer: {
                    Text("Daily or weekly — each gets a reminder and a check-off in the day view on its due days.")
                }

                // --- Apple Health
                Section {
                    Toggle("Sync with Apple Health", isOn: $healthEnabled)
                        .onChange(of: healthEnabled) { on in
                            if on {
                                Task {
                                    let ok = await HealthKitService.shared.requestAuthorization()
                                    healthMessage = ok
                                        ? "Connected. Logged days sync to Health; steps, sleep, and weigh-ins flow into Stats."
                                        : "Health access unavailable — check iOS Settings → Health → Data Access."
                                    if !ok { healthEnabled = false }
                                }
                            }
                        }
                    if healthEnabled {
                        Button {
                            Task {
                                let n = await HealthKitService.shared.importExternalWeights(into: plan)
                                try? context.save()
                                healthMessage = "Imported \(n) weigh-in\(n == 1 ? "" : "s") from Health."
                            }
                        } label: {
                            Label("Import Weigh-ins Now", systemImage: "arrow.down.heart")
                        }
                    }
                    if let msg = healthMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Garmin, Apple Watch, and smart scales that write to Apple Health flow in automatically — this is the Garmin link.")
                }

                // --- Appearance
                Section("Appearance") {
                    Picker("Accent", selection: $themePalette) {
                        ForEach(ThemePalette.allCases) { p in
                            HStack {
                                Circle().fill(p.accents.0).frame(width: 14, height: 14)
                                Text(p.label)
                            }.tag(p.rawValue)
                        }
                    }
                    Picker("Mode", selection: $themeMode) {
                        ForEach(ThemeMode.allCases) { m in Text(m.label).tag(m.rawValue) }
                    }
                    .pickerStyle(.segmented)
                }

                // --- Notifications
                Section("Notifications") {
                    Toggle("Morning weigh-in", isOn: $weighInEnabled)
                    if weighInEnabled {
                        Picker("Weigh-in time", selection: $weighInHour) {
                            ForEach(5...12, id: \.self) { h in
                                Text("\(h):00").tag(h)
                            }
                        }
                    }
                    Toggle("Hydration nudges", isOn: $hydrationEnabled)
                    if hydrationEnabled {
                        ForEach(0..<3, id: \.self) { i in
                            DatePicker("Nudge \(i + 1)",
                                       selection: hydrationTimeBinding(i),
                                       displayedComponents: .hourAndMinute)
                        }
                    }
                    Toggle("Workout reminders", isOn: $workoutEnabled)
                    if workoutEnabled {
                        Picker("Remind me", selection: $workoutLead) {
                            Text("15 min before").tag(15)
                            Text("30 min before").tag(30)
                            Text("1 hour before").tag(60)
                        }
                    }
                    Toggle("Streak guard", isOn: $streakEnabled)
                    if streakEnabled {
                        DatePicker("Check-in time",
                                   selection: streakTimeBinding,
                                   displayedComponents: .hourAndMinute)
                    }
                }
                .onChange(of: weighInEnabled) { _ in reschedule() }
                .onChange(of: weighInHour) { _ in reschedule() }
                .onChange(of: hydrationEnabled) { _ in reschedule() }
                .onChange(of: hydrationTimes) { _ in reschedule() }
                .onChange(of: workoutEnabled) { _ in reschedule() }
                .onChange(of: workoutLead) { _ in reschedule() }
                .onChange(of: streakEnabled) { _ in reschedule() }

                // --- Profile
                Section("Profile") {
                    DatePicker("Birth date", selection: $profile.birthDate, in: ...Date(), displayedComponents: .date)
                    Picker("Sex", selection: Binding(get: { profile.sex }, set: { profile.sex = $0 })) {
                        ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        Picker("Feet", selection: Binding(
                            get: { Int(profile.heightInches) / 12 },
                            set: { profile.heightInches = Double($0 * 12 + Int(profile.heightInches) % 12) }
                        )) {
                            ForEach(3...7, id: \.self) { Text("\($0) ft") }
                        }
                        .pickerStyle(.menu)
                        Picker("Inches", selection: Binding(
                            get: { Int(profile.heightInches) % 12 },
                            set: { profile.heightInches = Double((Int(profile.heightInches) / 12) * 12 + $0) }
                        )) {
                            ForEach(0...11, id: \.self) { Text("\($0) in") }
                        }
                        .pickerStyle(.menu)
                    }
                    Picker("Activity", selection: Binding(get: { profile.activityLevel }, set: { profile.activityLevel = $0 })) {
                        ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                    }
                }

                // --- Security
                Section("Security") {
                    Label("Face ID protects your progress photos", systemImage: "faceid")
                        .foregroundStyle(.secondary)
                }

                // --- Backup / Export (JSON)
                Section("Backup / Export") {
                    Button("Export Backup (JSON)…") {
                        do {
                            exportURL = try BackupService.exportJSON(profile: profile, plan: plan)
                            presentShare = (exportURL != nil)
                        } catch {
                            exportURL = nil
                        }
                    }
                    .sheet(isPresented: $presentShare) {
                        if let url = exportURL {
                            ActivityView(activityItems: [url])
                        }
                    }
                }

                // --- Reset
                Section("Reset") {
                    Button(role: .destructive) { showEraseConfirm = true } label: {
                        Text("Erase All Data")
                    }
                    .confirmationDialog("Erase all local data? This cannot be undone.",
                                        isPresented: $showEraseConfirm,
                                        titleVisibility: .visible) {
                        Button("Erase All", role: .destructive) { eraseAll() }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .themedForm()
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
    }

    private func reschedule() {
        NotificationManager.rescheduleAll(plan: plan)
    }

    /// Binding for one of the three comma-separated hydration times.
    private func hydrationTimeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                let times = NotificationManager.hydrationTimes()
                let t = index < times.count ? times[index] : (11 + index * 4, 0)
                return Calendar.current.date(from: DateComponents(hour: t.0, minute: t.1)) ?? Date()
            },
            set: { date in
                var times = NotificationManager.hydrationTimes()
                while times.count < 3 { times.append((11 + times.count * 4, 0)) }
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                times[index] = (comps.hour ?? 11, comps.minute ?? 0)
                hydrationTimes = times.map { String(format: "%d:%02d", $0.hour, $0.minute) }
                    .joined(separator: ",")
            }
        )
    }

    private var streakTimeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(from: DateComponents(hour: streakHour, minute: streakMinute)) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                streakHour = comps.hour ?? 20
                streakMinute = comps.minute ?? 30
            }
        )
    }

    private func eraseAll() {
        if let days = try? context.fetch(FetchDescriptor<DayLog>()) {
            days.forEach { context.delete($0) }
        }
        if let ps = try? context.fetch(FetchDescriptor<WorkoutPreset>()) {
            ps.forEach { context.delete($0) }
        }
        if let plans = try? context.fetch(FetchDescriptor<Plan>()) {
            plans.forEach { context.delete($0) }
        }
        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            profiles.forEach { context.delete($0) }
        }
        try? context.save()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()

        // Delete photos directory
        try? FileManager.default.removeItem(at: photosDir())
    }
}

// Simple share wrapper (unchanged)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
