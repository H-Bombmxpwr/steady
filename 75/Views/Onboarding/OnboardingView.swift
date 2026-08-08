import SwiftUI
import SwiftData

/// Multi-step plan setup.
///
/// The first question is which app this is going to be — losing weight or
/// training for something — because almost every later question depends on the
/// answer. An athlete gets asked about their training plan and their sweat
/// rate; someone in a deficit gets asked about a goal weight and a pace.
/// Neither has to wade through the other's questions.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context

    /// The steps that apply to the chosen mode, in order. Rebuilt whenever the
    /// mode changes, so the flow has no dead branches in it.
    private enum Step: Hashable {
        case mode, profile, goal, budget, training, trainingPeaks, schedule
        case sweat, hydration, cycle, labs, ai, privacy

        var title: String {
            switch self {
            case .mode: return "How You'll Use It"
            case .profile: return "About You"
            case .goal: return "Your Goal"
            case .budget: return "Your Budget"
            case .training: return "Your Training"
            case .trainingPeaks: return "TrainingPeaks"
            case .schedule: return "Workout Days"
            case .sweat: return "Sweat & Weather"
            case .hydration: return "Hydration"
            case .cycle: return "Cycle Tracking"
            case .labs: return "Blood Work"
            case .ai: return "AI Assist"
            case .privacy: return "Privacy"
            }
        }
    }

    @State private var stepIndex = 0

    // Mode
    @State private var mode: AppMode = .weightLoss
    @State private var generalHealth = false

    // Streak style — relaxed (any logging) is the default
    @State private var strictStreak = false

    // AI assist (optional own Gemini key; a shared one is bundled)
    @AppStorage(AIFoodEstimator.apiKeyKey) private var geminiKey = ""

    // Blood work (optional, opt-in)
    @AppStorage("labs.enabled") private var labsEnabled = false
    @State private var ldlText = ""
    @State private var hdlText = ""
    @State private var trigText = ""
    @State private var glucoseText = ""
    @State private var a1cText = ""

    // Profile
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date())!
    @State private var sex: BiologicalSex = .male
    @State private var heightFeet = 5
    @State private var heightInches = 10
    @State private var activity: ActivityLevel = .moderate

    // Goals
    @State private var currentWeightText = ""
    @State private var goalWeightText = ""
    @State private var pace = 1.0
    /// Athlete mode: eat at maintenance rather than in a deficit.
    @State private var eatAtMaintenance = true

    // TrainingPeaks
    @State private var feedURL = ""
    @State private var feedError: String?

    // Sweat & weather
    @AppStorage(SaltLoss.storageKey) private var saltRaw = SaltLoss.typical.rawValue
    @AppStorage(WeatherService.useAutomaticKey) private var automaticWeather = true

    // Cycle tracking
    @State private var cycleTracking = false
    @State private var cycleDecided = false

    // Workout schedule — starts empty; the user picks their own days
    @State private var selectedWeekdays: Set<Int> = []
    @State private var workoutName = "Workout"
    @State private var workoutMinutes = 45
    @State private var workoutTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!

    // Hydration
    @State private var waterGoal = 96
    @State private var waterStep = 8

    // Photo privacy — optional backup PIN for the Face ID lock
    @State private var pin = ""
    @State private var pinConfirm = ""

    @FocusState private var weightFocused: Bool

    private let paces: [Double] = [0.5, 1.0, 1.5, 2.0]

    private var currentWeight: Double? { Double(currentWeightText.trimmingCharacters(in: .whitespaces)) }
    private var goalWeight: Double? { Double(goalWeightText.trimmingCharacters(in: .whitespaces)) }
    private var totalHeightInches: Double { Double(heightFeet * 12 + heightInches) }

    /// Cycle tracking is offered when the profile makes it relevant. A female
    /// profile gets it suggested on; "prefer not to say" gets asked without a
    /// default, because we genuinely don't know.
    private var cycleRelevant: Bool { sex == .female || sex == .unspecified }

    private var steps: [Step] {
        var steps: [Step] = [.mode, .profile]
        switch mode {
        case .weightLoss:
            steps += [.goal, .budget, .schedule, .hydration]
        case .athlete:
            steps += [.training, .trainingPeaks, .schedule, .sweat, .hydration]
        }
        if cycleRelevant { steps.append(.cycle) }
        steps += [.labs, .ai, .privacy]
        return steps
    }

    private var step: Step { steps[min(stepIndex, steps.count - 1)] }

    private var goalsValid: Bool {
        guard let c = currentWeight else { return false }
        guard c > 50 && c < 800 else { return false }
        // An athlete at maintenance never needs a goal weight.
        if mode == .athlete && eatAtMaintenance { return true }
        guard let g = goalWeight else { return false }
        return g > 50 && g <= c
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .mode: modeStep
                case .profile: profileStep
                case .goal: goalsStep
                case .budget: budgetStep
                case .training: trainingStep
                case .trainingPeaks: trainingPeaksStep
                case .schedule: scheduleStep
                case .sweat: sweatStep
                case .hydration: hydrationStep
                case .cycle: cycleStep
                case .labs: labsStep
                case .ai: aiStep
                case .privacy: privacyStep
                }
            }
            .themedForm()
            .navigationTitle(step.title)
            .toolbar {
                if stepIndex > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { stepIndex -= 1 }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { weightFocused = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .themedRoot()
    }

    private func advance() {
        stepIndex = min(stepIndex + 1, steps.count - 1)
    }

    // MARK: Mode

    private var modeStep: some View {
        Form {
            Section {
                ForEach(AppMode.allCases) { option in
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { mode = option }
                        // An athlete at maintenance has no pace; someone in a
                        // deficit does. Keep the two consistent.
                        eatAtMaintenance = option == .athlete
                        Haptics.selection()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: mode == option ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(mode == option ? Theme.accent : .secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Label(option.label, systemImage: option.icon)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(option.pitch)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("What are you here for?")
            } footer: {
                Text(mode.detail + "\n\nYou can switch modes later in Settings without losing anything you've logged.")
            }

            Section {
                Toggle("Also track general health", isOn: $generalHealth)
            } footer: {
                Text("Adds fiber, sodium, and added sugar to your day, and turns on blood-work tracking. Useful if you care about more than the number on the scale or the stopwatch.")
            }

            Section {
                Button("Continue") { advance() }
                    .buttonStyle(.primaryAction)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: Profile

    private var profileStep: some View {
        Form {
            Section(footer: Text("Used only to estimate your daily calorie burn. Everything stays on this device.")) {
                DatePicker("Birth date", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                Picker("Sex", selection: $sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("Height")
                    Spacer()
                    Picker("Feet", selection: $heightFeet) {
                        ForEach(3...7, id: \.self) { Text("\($0) ft") }
                    }
                    .pickerStyle(.menu)
                    Picker("Inches", selection: $heightInches) {
                        ForEach(0...11, id: \.self) { Text("\($0) in") }
                    }
                    .pickerStyle(.menu)
                }
            }
            Section {
                Picker("Activity", selection: $activity) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text(activity.detail).font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Activity Level")
            } footer: {
                if mode == .athlete {
                    Text("Describe life outside training — your job and your daily moving around. Your sessions are counted separately, one at a time, so don't count them twice here.")
                }
            }
            Section {
                Button("Continue") { advance() }
            }
        }
    }

    // MARK: Goal (weight loss)

    private var goalsStep: some View {
        Form {
            Section("Weight") {
                TextField("Current weight (lb)", text: $currentWeightText)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
                TextField("Goal weight (lb)", text: $goalWeightText)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
            }
            Section(footer: Text("1–2 lb per week is the widely recommended sustainable range.")) {
                Picker("Pace", selection: $pace) {
                    ForEach(paces, id: \.self) { p in
                        Text(String(format: "%.1f lb / week", p)).tag(p)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Picker("Streak counts when", selection: $strictStreak) {
                    Text("I log anything").tag(false)
                    Text("I hit my goals").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Streak Style")
            } footer: {
                Text("Relaxed keeps the flame alive any day you log something — food, water, weight, a workout, a photo. Strict requires meeting the day's goals. Changeable anytime in Settings.")
            }
            Section {
                Button("Continue") { advance() }
                    .disabled(!goalsValid)
            }
        }
    }

    // MARK: Budget preview (weight loss)

    private var budgetStep: some View {
        Form {
            if let c = currentWeight, let g = goalWeight {
                let age = Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 30
                let tdee = CalorieEngine.tdee(sex: sex, weightLbs: c, heightInches: totalHeightInches,
                                              ageYears: age, activity: activity)
                let budget = CalorieEngine.dailyBudget(tdee: tdee, paceLbsPerWeek: pace, sex: sex)
                let protein = CalorieEngine.proteinTargetGrams(goalWeightLbs: g)
                let weeks = pace > 0 ? (c - g) / pace : 0
                let projected = Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: Date())

                Section("Daily Targets") {
                    row("Maintenance (TDEE)", "\(Int(tdee.rounded())) cal")
                    row("Calorie budget", "\(budget) cal")
                    row("Protein target", "\(protein) g")
                }
                Section(footer: Text("Your budget adjusts automatically as your weight changes. You can override it later in Settings.")) {
                    if let projected, g < c {
                        row("Est. goal date", projected.formatted(date: .abbreviated, time: .omitted))
                    }
                    row("Total to lose", String(format: "%.1f lb", c - g))
                }
                Section {
                    Button("Looks Good") { advance() }
                }
            }
        }
    }

    // MARK: Training (athlete)

    private var trainingStep: some View {
        Form {
            Section("Weight") {
                TextField("Current weight (lb)", text: $currentWeightText)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
            }

            Section {
                Toggle("Eat at maintenance", isOn: $eatAtMaintenance.animation())
                if !eatAtMaintenance {
                    TextField("Goal weight (lb)", text: $goalWeightText)
                        .keyboardType(.decimalPad)
                        .focused($weightFocused)
                    Picker("Pace", selection: $pace) {
                        ForEach([0.5, 1.0], id: \.self) { p in
                            Text(String(format: "%.1f lb / week", p)).tag(p)
                        }
                    }
                }
            } header: {
                Text("Body composition")
            } footer: {
                Text(eatAtMaintenance
                     ? "Your budget will be maintenance plus whatever the day's training costs. Under-fuelling is the most common way athletes lose a season, so this is the default."
                     : "A body-composition block. Steady caps the deficit at 1 lb/week no matter what — beyond that, performance and lean mass go before fat does.")
            }

            Section {
                Picker("Streak counts when", selection: $strictStreak) {
                    Text("I log anything").tag(false)
                    Text("I hit my goals").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Streak Style")
            }

            Section {
                Button("Continue") { advance() }
                    .disabled(!goalsValid)
            }
        }
    }

    // MARK: TrainingPeaks (athlete)

    private var trainingPeaksStep: some View {
        Form {
            Section {
                Text("If you train from a plan in TrainingPeaks, Steady can read it. Today's session lands on your dashboard, and the fueling is built from its type, length, and intensity.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Import your plan")
            }

            Section {
                TextField("Paste your calendar URL", text: $feedURL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.caption, design: .monospaced))
                    .focused($weightFocused)
                NavigationLink {
                    TrainingPeaksGuideView()
                } label: {
                    Label("Where to find it", systemImage: "questionmark.circle")
                }
                if let feedError {
                    Text(feedError).font(.caption).foregroundStyle(Theme.danger)
                }
            } footer: {
                Text("In TrainingPeaks: Account Settings → Calendar Sync. It's a private link only you have — Steady reads it and stores nothing on any server. You can add or change it later in Settings.")
            }

            Section {
                Button(feedURL.isEmpty ? "Skip for Now" : "Continue") {
                    if !feedURL.isEmpty, TrainingPeaksSync.normalize(feedURL) == nil {
                        feedError = "That doesn't look like a calendar link. It should start with https:// or webcal://."
                        return
                    }
                    feedError = nil
                    advance()
                }
            }
        }
    }

    // MARK: Schedule

    private var scheduleStep: some View {
        Form {
            Section {
                ForEach(1...7, id: \.self) { d in
                    Button {
                        if selectedWeekdays.contains(d) { selectedWeekdays.remove(d) }
                        else { selectedWeekdays.insert(d) }
                    } label: {
                        HStack {
                            Image(systemName: selectedWeekdays.contains(d) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedWeekdays.contains(d) ? Theme.accent : .secondary)
                            Text(Calendar.current.weekdaySymbols[d - 1]).foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                }
            } header: {
                Text("Which days will you train?")
            } footer: {
                if mode == .athlete && !feedURL.isEmpty {
                    Text("Optional — your TrainingPeaks plan already covers the days it knows about, and it always wins over this. This is a fallback for weeks the plan doesn't reach.")
                } else {
                    Text(selectedWeekdays.isEmpty
                         ? "Example: many people start with Monday, Wednesday, and Friday. Workouts only count against your goals on days you pick — you can also skip this and set it up later in the Workouts tab."
                         : "Workouts only count against your daily goals on days you pick. Fine-tune per-day workouts later in the Workouts tab.")
                }
            }
            Section("Default Workout") {
                TextField("Name (e.g., Gym, Run)", text: $workoutName)
                Stepper("Minutes: \(workoutMinutes)", value: $workoutMinutes, in: 5...300, step: 5)
                DatePicker("Time", selection: $workoutTime, displayedComponents: .hourAndMinute)
            }
            Section {
                Button(selectedWeekdays.isEmpty ? "Skip for Now" : "Continue") { advance() }
            }
        }
    }

    // MARK: Sweat & weather (athlete)

    private var sweatStep: some View {
        Form {
            Section {
                Picker("Sweat saltiness", selection: $saltRaw) {
                    ForEach(SaltLoss.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text((SaltLoss(rawValue: saltRaw) ?? .typical).cue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("How salty is your sweat?")
            } footer: {
                Text("The white-crust-on-your-kit question. Sweat sodium varies ten-fold between people, and it's the difference between cramping and not on a long hot day.")
            }

            Section {
                Toggle("Use local weather", isOn: $automaticWeather)
                    // Ask for location here, where the question has context,
                    // rather than ambushing them on the first dashboard.
                    .onChange(of: automaticWeather) { on in
                        if on { Task { await WeatherService.shared.refresh() } }
                    }
            } footer: {
                Text("Heat and humidity change how much you sweat more than anything except how hard you're going. With this on, Steady checks conditions through Apple's WeatherKit and scales your fluid and sodium targets to the day. Your location is used for the lookup and never stored or sent anywhere else. Off means you can enter conditions by hand instead.")
            }

            Section {
                Label("You'll be prompted to run a sweat test later", systemImage: "drop.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Twenty minutes, a scale, and a bottle gives Steady your actual sweat rate — which beats every population average, usually by a lot. It lives under Hydration on your dashboard whenever you're ready.")
            }

            Section {
                Button("Continue") { advance() }
            }
        }
    }

    // MARK: Hydration

    private var hydrationStep: some View {
        Form {
            Section(footer: Text(mode == .athlete
                                 ? "This is your baseline for a rest day. Training fluid gets added on top, from your sweat rate and the weather."
                                 : "Set the step to your bottle size so logging is one tap.")) {
                Stepper("Daily goal: \(waterGoal) oz", value: $waterGoal, in: 32...256, step: 8)
                Stepper("Log step: \(waterStep) oz", value: $waterStep, in: 1...128)
            }
            Section {
                Button("Continue") { advance() }
            }
        }
    }

    // MARK: Cycle tracking

    private var cycleStep: some View {
        Form {
            Section {
                Toggle("Track my cycle", isOn: $cycleTracking.animation())
            } header: {
                Text(sex == .female ? "Cycle tracking" : "One more thing")
            } footer: {
                Text(sex == .female
                     ? "Log your period and Steady shows which phase you're in, explains the scale jumps that come with it, and nudges your hydration in the luteal phase when your core temperature runs warmer."
                     : "If you menstruate, Steady can track it — phases, predictions, and the context behind a scale that jumps for no obvious reason. We're asking because your profile says prefer-not-to-say, and we'd rather ask than assume either way.")
            }

            Section {
                Label("Locked behind Face ID", systemImage: "faceid")
                Label("Stored only on this device", systemImage: "iphone")
                Label("Never sent anywhere, ever", systemImage: "wifi.slash")
            } footer: {
                Text("Cycle data sits behind the same lock as your progress photos, never goes to Apple Health, and is never included in anything sent for a nutrition estimate. You can switch this off and erase all of it any time in Settings.")
            }

            Section {
                Button("Continue") {
                    cycleDecided = true
                    advance()
                }
            }
        }
    }

    // MARK: Blood work

    private var labsStep: some View {
        Form {
            Section {
                Toggle("Lab-aware coaching", isOn: $labsEnabled)
            } footer: {
                Text("Optional. Log a few numbers from a recent blood panel and day summaries and nutrition targets lean toward improving them — framed as things to raise with your doctor, never medical advice. Values stay on this device; when this is on, only the bare numbers are used to steer summaries. You can change this anytime in Settings → Blood Work.")
            }
            if labsEnabled {
                Section("From your lab report (leave blank to skip)") {
                    labField("LDL cholesterol", $ldlText, unit: "mg/dL")
                    labField("HDL cholesterol", $hdlText, unit: "mg/dL")
                    labField("Triglycerides", $trigText, unit: "mg/dL")
                    labField("Fasting glucose", $glucoseText, unit: "mg/dL")
                    labField("A1C", $a1cText, unit: "%")
                }
            }
            Section {
                Button("Continue") { advance() }
            }
        }
    }

    // MARK: AI assist

    private var geminiKeyEntered: Bool {
        !geminiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var aiStep: some View {
        Form {
            Section {
                Text("Steady uses Google's Gemini to turn your meals into calories and macros — describe them, snap a photo, or paste a recipe link, and get every item broken out.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Smart food logging")
            }

            Section {
                TextField("Paste a Gemini key (optional)", text: $geminiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .font(.system(.body, design: .monospaced))
                    .focused($weightFocused)
                NavigationLink {
                    GeminiKeyGuideView()
                } label: {
                    Label("How to get a free key", systemImage: "key.horizontal.fill")
                }
            } footer: {
                Text("A shared key is already built in, so this works right away — just continue. Prefer your own private quota? Paste a free key, or tap above to get one in a minute. You can add or change it anytime in Settings → AI & Estimates.")
            }

            Section {
                Button(geminiKeyEntered ? "Save Key & Continue" : "Use Built-in Key & Continue") {
                    advance()
                }
            }
        }
    }

    private func labField(_ label: String, _ text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .focused($weightFocused)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    // MARK: Privacy PIN + create

    private var pinValid: Bool {
        (pin.isEmpty && pinConfirm.isEmpty)
            || (pin.count >= 4 && pin == pinConfirm && pin.allSatisfy(\.isNumber))
    }

    private var privacyStep: some View {
        Form {
            Section {
                SecureField("PIN (4+ digits)", text: $pin)
                    .keyboardType(.numberPad)
                    .focused($weightFocused)
                SecureField("Confirm PIN", text: $pinConfirm)
                    .keyboardType(.numberPad)
                    .focused($weightFocused)
            } header: {
                Text("Backup PIN (optional)")
            } footer: {
                Text(cycleTracking
                     ? "Your progress photos and your cycle log stay on this device, locked behind Face ID. Set a backup PIN for when Face ID fails — or if you'd rather unlock with a PIN. Leave blank to skip; you can add one later in Settings → Security."
                     : "Your progress photos stay on this device and are locked behind Face ID. Set a backup PIN for when Face ID fails — or if you'd rather unlock with a PIN. Leave blank to skip; you can add one later in Settings → Security.")
            }
            if !pinValid {
                Section {
                    Text(pin.count < 4 ? "PIN needs at least 4 digits."
                                       : "PINs don't match.")
                        .font(.footnote)
                        .foregroundStyle(Theme.danger)
                }
            }
            Section {
                Button("Start Tracking") { createPlan() }
                    .buttonStyle(.primaryAction)
                    .disabled(!goalsValid || !pinValid)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
            }
        }
    }

    private func createPlan() {
        Haptics.success()
        if pin.count >= 4, pin == pinConfirm {
            PinStore.set(pin)
        }
        guard let c = currentWeight else { return }
        // An athlete at maintenance has no goal weight; the plan still needs a
        // number, and their current weight is the honest one.
        let g = goalWeight ?? c

        let profile = UserProfile(birthDate: birthDate,
                                  heightInches: totalHeightInches,
                                  sex: sex,
                                  activityLevel: activity,
                                  mode: mode,
                                  generalHealth: generalHealth)
        profile.cycleTracking = cycleTracking
        profile.cycleTrackingOffered = cycleDecided || cycleRelevant

        let plan = Plan(startDate: Date(),
                        startingWeight: c,
                        goalWeight: g,
                        paceLbsPerWeek: mode == .athlete && eatAtMaintenance ? 0 : pace,
                        waterGoalOunces: waterGoal,
                        waterStepOunces: waterStep,
                        proteinTargetGrams: CalorieEngine.proteinTargetGrams(goalWeightLbs: g))
        plan.strictStreak = strictStreak
        plan.eatAtMaintenance = eatAtMaintenance
        plan.weatherAwareFueling = automaticWeather
        let trimmedFeed = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .athlete, !trimmedFeed.isEmpty {
            plan.trainingPeaksFeedURL = trimmedFeed
        }
        if generalHealth { labsEnabled = true }

        let comps = Calendar.current.dateComponents([.hour, .minute], from: workoutTime)
        let name = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        for weekday in selectedWeekdays.sorted() {
            plan.schedule.append(WorkoutScheduleEntry(
                weekday: weekday,
                name: name.isEmpty ? "Workout" : name,
                minutes: workoutMinutes,
                hour: comps.hour ?? 7,
                minute: comps.minute ?? 0))
        }

        if labsEnabled {
            let labs = LabResult(date: Date())
            labs.ldl = Double(ldlText)
            labs.hdl = Double(hdlText)
            labs.triglycerides = Double(trigText)
            labs.fastingGlucose = Double(glucoseText)
            labs.a1c = Double(a1cText)
            if !labs.isEmpty { plan.labs.append(labs) }
        }

        context.insert(profile)
        context.insert(plan)
        try? context.save()

        // Pull the training plan in right away, so the first dashboard the
        // athlete sees already has today's session on it.
        if plan.trainingPeaksConnected {
            Task { @MainActor in
                _ = try? await TrainingPeaksSync.sync(plan: plan)
                try? context.save()
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).bold() }
    }
}

// MARK: - TrainingPeaks guide

struct TrainingPeaksGuideView: View {
    var body: some View {
        Form {
            Section {
                step(1, "Open TrainingPeaks on the web", "The calendar link lives in the web app, not the phone app. app.trainingpeaks.com.")
                step(2, "Go to Account Settings", "Click your name, top right, then Settings.")
                step(3, "Find Calendar Sync", "It may be called “Calendar Sync” or “iCal Sync” depending on your account type.")
                step(4, "Copy the whole URL", "It starts with webcal:// or https:// and ends in .ics. Paste it into Steady.")
            } header: {
                SectionHeader(icon: "list.number", title: "Finding your link", tint: Theme.accent)
            } footer: {
                Text("This is a private link tied to your account. Anyone with it can read your training calendar, so treat it like a password — and if you ever want to cut Steady off, regenerate it in TrainingPeaks and the old one stops working.")
            }

            Section {
                Text("Steady reads your planned sessions: the name, the day, the duration, and the TSS when your plan includes it. From those it works out the type and intensity, and builds the fueling around them.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Nothing goes the other way. Steady never writes to TrainingPeaks and never uploads anything you log.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                SectionHeader(icon: "arrow.down.circle", title: "What comes across", tint: Theme.accent)
            }
        }
        .themedForm()
        .navigationTitle("TrainingPeaks")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
