import SwiftUI
import SwiftData

/// Multi-step plan setup: profile → goals → budget preview → workout schedule → hydration.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var step = 0

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

    // Workout schedule — starts empty; the user picks their own days
    @State private var selectedWeekdays: Set<Int> = []
    @State private var workoutName = "Workout"
    @State private var workoutMinutes = 45
    @State private var workoutTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!

    // Hydration
    @State private var waterGoal = 96
    @State private var waterStep = 8

    // Photo privacy — optional backup PIN for the Face ID photo lock
    @State private var pin = ""
    @State private var pinConfirm = ""

    @FocusState private var weightFocused: Bool

    private let paces: [Double] = [0.5, 1.0, 1.5, 2.0]

    private var currentWeight: Double? { Double(currentWeightText.trimmingCharacters(in: .whitespaces)) }
    private var goalWeight: Double? { Double(goalWeightText.trimmingCharacters(in: .whitespaces)) }
    private var totalHeightInches: Double { Double(heightFeet * 12 + heightInches) }

    private var goalsValid: Bool {
        guard let c = currentWeight, let g = goalWeight else { return false }
        return c > 50 && c < 800 && g > 50 && g <= c
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case 0: profileStep
                case 1: goalsStep
                case 2: budgetStep
                case 3: scheduleStep
                case 4: hydrationStep
                case 5: labsStep
                default: privacyStep
                }
            }
            .themedForm()
            .navigationTitle(titles[step])
            .toolbar {
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { step -= 1 }
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

    private let titles = ["About You", "Your Goal", "Your Budget", "Workout Days", "Hydration", "Blood Work", "Photo Privacy"]

    // MARK: Step 1 — profile

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
            Section("Activity Level") {
                Picker("Activity", selection: $activity) {
                    ForEach(ActivityLevel.allCases) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Text(activity.detail).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button("Continue") { step = 1 }
            }
        }
    }

    // MARK: Step 2 — goals

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
                Button("Continue") { step = 2 }
                    .disabled(!goalsValid)
            }
        }
    }

    // MARK: Step 3 — budget preview

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
                    Button("Looks Good") { step = 3 }
                }
            }
        }
    }

    // MARK: Step 4 — workout schedule

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
                Text(selectedWeekdays.isEmpty
                     ? "Example: many people start with Monday, Wednesday, and Friday. Workouts only count against your goals on days you pick — you can also skip this and set it up later in the Workouts tab."
                     : "Workouts only count against your daily goals on days you pick. Fine-tune per-day workouts later in the Workouts tab.")
            }
            Section("Default Workout") {
                TextField("Name (e.g., Gym, Run)", text: $workoutName)
                Stepper("Minutes: \(workoutMinutes)", value: $workoutMinutes, in: 5...300, step: 5)
                DatePicker("Time", selection: $workoutTime, displayedComponents: .hourAndMinute)
            }
            Section {
                Button(selectedWeekdays.isEmpty ? "Skip for Now" : "Continue") { step = 4 }
            }
        }
    }

    // MARK: Step 5 — hydration

    private var hydrationStep: some View {
        Form {
            Section(footer: Text("Set the step to your bottle size so logging is one tap.")) {
                Stepper("Daily goal: \(waterGoal) oz", value: $waterGoal, in: 32...256, step: 8)
                Stepper("Log step: \(waterStep) oz", value: $waterStep, in: 1...128)
            }
            Section {
                Button("Continue") { step = 5 }
            }
        }
    }

    // MARK: Step 6 — blood work (optional)

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
                Button("Continue") { step = 6 }
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

    // MARK: Step 7 — photo privacy PIN + create

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
                Text("Your progress photos stay on this device and are locked behind Face ID. Set a backup PIN for when Face ID fails — or if you'd rather unlock with a PIN. Leave blank to skip; you can add one later in Settings → Security.")
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
                    .disabled(!goalsValid || !pinValid)
            }
        }
    }

    private func createPlan() {
        if pin.count >= 4, pin == pinConfirm {
            PinStore.set(pin)
        }
        guard let c = currentWeight, let g = goalWeight else { return }
        let profile = UserProfile(birthDate: birthDate,
                                  heightInches: totalHeightInches,
                                  sex: sex,
                                  activityLevel: activity)
        let plan = Plan(startDate: Date(),
                        startingWeight: c,
                        goalWeight: g,
                        paceLbsPerWeek: pace,
                        waterGoalOunces: waterGoal,
                        waterStepOunces: waterStep,
                        proteinTargetGrams: CalorieEngine.proteinTargetGrams(goalWeightLbs: g))

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
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).bold() }
    }
}
