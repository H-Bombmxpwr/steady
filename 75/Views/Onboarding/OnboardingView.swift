import SwiftUI
import SwiftData

/// Multi-step plan setup: profile → goals → budget preview → hydration.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var step = 0

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

    // Hydration
    @State private var waterGoal = 96
    @State private var waterStep = 8

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
                default: hydrationStep
                }
            }
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
    }

    private let titles = ["About You", "Your Goal", "Your Budget", "Hydration"]

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

    // MARK: Step 4 — hydration + create

    private var hydrationStep: some View {
        Form {
            Section(footer: Text("Set the step to your bottle size so logging is one tap.")) {
                Stepper("Daily goal: \(waterGoal) oz", value: $waterGoal, in: 32...256, step: 8)
                Stepper("Log step: \(waterStep) oz", value: $waterStep, in: 1...128)
            }
            Section {
                Button("Start Tracking") { createPlan() }
                    .disabled(!goalsValid)
            }
        }
    }

    private func createPlan() {
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
        context.insert(profile)
        context.insert(plan)
        try? context.save()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).bold() }
    }
}
