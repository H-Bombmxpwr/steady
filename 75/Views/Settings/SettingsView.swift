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

    // Appearance — bound to the observable store so the change applies live
    @Bindable private var theme = ThemeStore.shared
    @AppStorage("ui.glassBar") private var glassBar = true

    // Apple Health
    @AppStorage(HealthKitService.enabledKey) private var healthEnabled = false
    @State private var healthMessage: String?

    // Live Activity (Lock Screen / Dynamic Island)
    @AppStorage(LiveActivityManager.enabledKey) private var liveActivity = false

    // Alternate app icon — stores the alternate icon's asset name, or "" for
    // the primary icon (which follows the system light/dark appearance).
    @AppStorage("ui.appIcon") private var appIconChoice = ""
    @State private var iconMessage: String?

    // Lab-aware coaching
    @AppStorage("labs.enabled") private var labsEnabled = false
    @State private var showLabEntry = false

    // Fasting window
    @AppStorage(Fasting.enabledKey) private var fastingEnabled = false
    @AppStorage(Fasting.targetHoursKey) private var fastingTarget = 16

    // Backup PIN for the photo lock
    @State private var pinIsSet = PinStore.isSet
    @State private var pinCurrent = ""
    @State private var pinNew = ""
    @State private var pinNewConfirm = ""
    @State private var pinMessage: String?

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
                    Picker("Streak counts when", selection: $plan.strictStreak) {
                        Text("I log anything").tag(false)
                        Text("I hit my goals").tag(true)
                    }
                }

                // --- Daily targets
                Section {
                    let targets = CalorieEngine.targets(profile: profile, plan: plan)
                    HStack {
                        Text("Calorie budget")
                        Spacer()
                        Text("\(targets.calories) cal").foregroundStyle(.secondary)
                    }
                    Toggle("Adaptive budget", isOn: $plan.adaptiveBudget)
                    if plan.adaptiveBudget {
                        if let adaptive = CalorieEngine.adaptiveTDEE(profile: profile, plan: plan) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Learned burn rate: \(Int(adaptive.blended.rounded())) cal/day")
                                Text("From \(adaptive.loggedDays) logged days and \(adaptive.spanDays) days of weigh-ins (formula says \(Int(adaptive.formula.rounded())))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        } else {
                            Text("Learning… needs about two weeks of food logs and weigh-ins, then the budget tunes itself to your real burn rate.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
                } header: {
                    Text("Daily Targets")
                } footer: {
                    Text("Adaptive budget compares what you logged eating against how your weight trend actually moved, and quietly corrects the textbook formula — the longer you log, the more it trusts your own data.")
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
                        Button {
                            Task {
                                let n = await HealthKitService.shared.importExternalWorkouts(into: plan)
                                try? context.save()
                                healthMessage = "Imported \(n) workout\(n == 1 ? "" : "s") from Health."
                            }
                        } label: {
                            Label("Import Workouts Now", systemImage: "figure.run.circle")
                        }
                    }
                    if let msg = healthMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Garmin, Apple Watch, and smart scales that write to Apple Health flow in automatically — this is the Garmin link. Workouts recorded on a watch or in Garmin Connect import into the day log (each one only once) and count toward minutes and the streak.")
                }

                // --- Fasting (opt-in eating-window tracking)
                Section {
                    Toggle("Fasting timer", isOn: $fastingEnabled)
                    if fastingEnabled {
                        Stepper("Target fast: \(fastingTarget) h",
                                value: $fastingTarget, in: 12...23)
                    }
                } header: {
                    Text("Fasting")
                } footer: {
                    Text("No extra logging — your last logged food starts the clock, the first food of the day ends it. A fasting card appears on the dashboard and eating windows chart under Stats → Food. 16 h ≈ the classic 16:8.")
                }

                // --- Blood work (opt-in lab-aware coaching)
                Section {
                    Toggle("Lab-aware coaching", isOn: $labsEnabled)
                    if labsEnabled {
                        if let labs = plan.latestLabs {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Latest panel — \(labs.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(labSummaryText(labs))
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                        Button { showLabEntry = true } label: {
                            Label(plan.latestLabs == nil ? "Log Lab Results" : "Log a New Panel",
                                  systemImage: "testtube.2")
                        }
                        .sheet(isPresented: $showLabEntry) {
                            LabEntrySheet(plan: plan)
                                .themedRoot()
                        }
                    }
                } header: {
                    Text("Blood Work")
                } footer: {
                    Text("Not medical advice — think of it as prep for your next doctor visit. Log a few numbers from a recent panel and day summaries and nutrition targets lean toward improving them. Values stay on this device; while this is on, only the bare numbers (never your name, age, or anything identifying) are included when a day summary is generated.")
                }

                // --- AI & estimates (details live on their own screen)
                Section {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI & Estimates")
                                Text("How it's used, your key, accuracy, and the exact prompts")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    }
                } header: {
                    Text("About Estimates")
                } footer: {
                    Text("Nutrition estimates are powered by Google's Gemini. Only food descriptions and photos are sent — everything else stays on this device.")
                }

                // --- Appearance
                Section {
                    Picker("Accent", selection: $theme.palette) {
                        ForEach(ThemePalette.allCases) { p in
                            HStack {
                                Circle().fill(p.accents.0).frame(width: 14, height: 14)
                                Text(p.label)
                            }.tag(p)
                        }
                    }
                    Picker("Mode", selection: $theme.mode) {
                        ForEach(ThemeMode.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    appIconPicker
                    if let iconMessage {
                        Text(iconMessage).font(.footnote).foregroundStyle(.secondary)
                    }
                    Toggle("Glass tab bar", isOn: $glassBar)
                    Toggle("Live Activity", isOn: $liveActivity)
                        .onChange(of: liveActivity) { on in
                            if on {
                                LiveActivityManager.sync(plan: plan, profile: profile)
                            } else {
                                LiveActivityManager.endAll()
                            }
                        }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("App icon: pick any palette in light (color background, white line) or dark (black background, color line), or “Match appearance” to follow the system. Glass tab bar floats over the content and lets you swipe left/right between tabs. Live Activity keeps today's remaining calories, protein, and water on the Lock Screen and Dynamic Island — it refreshes whenever the app runs.")
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
                Section {
                    Label("Face ID protects your progress photos", systemImage: "faceid")
                        .foregroundStyle(.secondary)
                    if pinIsSet {
                        SecureField("Current PIN", text: $pinCurrent)
                            .keyboardType(.numberPad)
                            .focused($fieldFocused)
                        SecureField("New PIN — leave blank to remove", text: $pinNew)
                            .keyboardType(.numberPad)
                            .focused($fieldFocused)
                        if !pinNew.isEmpty {
                            SecureField("Confirm new PIN", text: $pinNewConfirm)
                                .keyboardType(.numberPad)
                                .focused($fieldFocused)
                        }
                        Button(pinNew.isEmpty ? "Remove Backup PIN" : "Change Backup PIN") {
                            updatePin()
                        }
                        .disabled(pinCurrent.count < 4)
                    } else {
                        SecureField("New PIN (4+ digits)", text: $pinNew)
                            .keyboardType(.numberPad)
                            .focused($fieldFocused)
                        SecureField("Confirm PIN", text: $pinNewConfirm)
                            .keyboardType(.numberPad)
                            .focused($fieldFocused)
                        Button("Set Backup PIN") { setPin() }
                            .disabled(pinNew.count < 4 || pinNew != pinNewConfirm)
                    }
                    if let msg = pinMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("The backup PIN unlocks photos when Face ID fails, or if you'd rather not use Face ID.")
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
        .themedRoot()
    }

    // MARK: App icon picker

    /// "Match appearance" (the primary icon, follows the system) plus every
    /// palette in both light and dark styles — all selectable at any time.
    private var appIconPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { selectIcon(nil) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.surface2))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Match appearance").foregroundStyle(.primary)
                        Text("Emerald — follows Light / Dark")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if appIconChoice.isEmpty {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)

            ForEach(ThemePalette.allCases) { p in
                HStack(spacing: 12) {
                    Text(p.label)
                        .font(.subheadline)
                        .frame(width: 62, alignment: .leading)
                    ForEach([false, true], id: \.self) { dark in
                        let option = AppIconOption(palette: p, dark: dark)
                        Button { selectIcon(option.assetName) } label: {
                            IconSwatch(palette: p, dark: dark,
                                       selected: appIconChoice == option.assetName)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func selectIcon(_ name: String?) {
        UIApplication.shared.setAlternateIconName(name) { error in
            iconMessage = error == nil
                ? nil : "Couldn't switch the icon — \(error!.localizedDescription)"
        }
        appIconChoice = name ?? ""
    }

    private func reschedule() {
        NotificationManager.rescheduleAll(plan: plan)
    }

    private func setPin() {
        guard pinNew.count >= 4, pinNew == pinNewConfirm, pinNew.allSatisfy(\.isNumber) else {
            pinMessage = "PIN needs 4+ digits and both fields must match."
            return
        }
        PinStore.set(pinNew)
        pinIsSet = true
        pinNew = ""; pinNewConfirm = ""
        pinMessage = "Backup PIN set."
    }

    private func updatePin() {
        guard PinStore.verify(pinCurrent) else {
            pinMessage = "Current PIN is incorrect."
            pinCurrent = ""
            return
        }
        if pinNew.isEmpty {
            PinStore.clear()
            pinIsSet = false
            pinMessage = "Backup PIN removed."
        } else if pinNew.count >= 4, pinNew == pinNewConfirm, pinNew.allSatisfy(\.isNumber) {
            PinStore.set(pinNew)
            pinMessage = "Backup PIN updated."
        } else {
            pinMessage = "New PIN needs 4+ digits and both fields must match."
            return
        }
        pinCurrent = ""; pinNew = ""; pinNewConfirm = ""
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

/// A rounded-square preview of an app-icon option — a diagonal descending
/// "line" over the background, matching the two real styles: light is a
/// color gradient background with a white line, dark is a near-black
/// background with the color-gradient line. Approximate, but enough to tell
/// the ten options apart at a glance.
private struct IconSwatch: View {
    let palette: ThemePalette
    let dark: Bool
    let selected: Bool

    private var gradient: LinearGradient {
        LinearGradient(colors: [palette.accents.0, palette.accents.1],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            // Background
            if dark {
                Color(hex: 0x12161F)
            } else {
                gradient
            }
            // The descending line
            Capsule()
                .fill(dark ? AnyShapeStyle(gradient) : AnyShapeStyle(Color.white))
                .frame(width: 30, height: 8)
                .rotationEffect(.degrees(26))
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Color.primary : Theme.hairline,
                              lineWidth: selected ? 2.5 : 1))
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white, Theme.accent)
                    .padding(2)
            }
        }
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

// MARK: - Blood work entry

/// One-line recap of the latest panel for the settings row.
private func labSummaryText(_ labs: LabResult) -> String {
    var parts: [String] = []
    if let v = labs.ldl { parts.append("LDL \(Int(v))") }
    if let v = labs.hdl { parts.append("HDL \(Int(v))") }
    if let v = labs.triglycerides { parts.append("Trig \(Int(v))") }
    if let v = labs.fastingGlucose { parts.append("Glucose \(Int(v))") }
    if let v = labs.a1c { parts.append("A1C \(v.formatted(.number.precision(.fractionLength(1))))%") }
    return parts.joined(separator: " · ")
}

/// Log a lab panel — a few numbers off the report, all optional.
struct LabEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var plan: Plan

    @State private var date = Date()
    @State private var ldl = ""
    @State private var hdl = ""
    @State private var triglycerides = ""
    @State private var glucose = ""
    @State private var a1c = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Test date", selection: $date, in: ...Date(), displayedComponents: .date)
                Section {
                    field("LDL cholesterol", $ldl, unit: "mg/dL")
                    field("HDL cholesterol", $hdl, unit: "mg/dL")
                    field("Triglycerides", $triglycerides, unit: "mg/dL")
                    field("Fasting glucose", $glucose, unit: "mg/dL")
                    field("A1C", $a1c, unit: "%")
                } header: {
                    Text("From your lab report (leave blank to skip)")
                } footer: {
                    Text("Copy the numbers straight off the report. They stay on this device and only the bare values steer summaries — nothing identifying.")
                }
                Button("Save") {
                    let labs = LabResult(date: date)
                    labs.ldl = Double(ldl)
                    labs.hdl = Double(hdl)
                    labs.triglycerides = Double(triglycerides)
                    labs.fastingGlucose = Double(glucose)
                    labs.a1c = Double(a1c)
                    if !labs.isEmpty {
                        plan.labs.append(labs)
                        try? context.save()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Lab Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func field(_ label: String, _ text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }
}
