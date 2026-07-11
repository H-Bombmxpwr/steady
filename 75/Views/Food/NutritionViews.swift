import SwiftUI
import SwiftData

// MARK: - Shared nutrient rows

/// Label/value rows for a `NutritionFacts` block. `compact` hides zeros —
/// used inline on portion/custom sheets; the full report shows everything.
struct NutritionFactsRows: View {
    let facts: NutritionFacts
    var compact = false

    private var rows: [(name: String, value: Double, unit: String)] {
        [("Carbs", facts.carbsGrams, "g"),
         ("Fiber", facts.fiberGrams, "g"),
         ("Total Sugar", facts.sugarGrams, "g"),
         ("Added Sugar", facts.addedSugarGrams, "g"),
         ("Fat", facts.fatGrams, "g"),
         ("Saturated Fat", facts.saturatedFatGrams, "g"),
         ("Trans Fat", facts.transFatGrams, "g"),
         ("Cholesterol", facts.cholesterolMg, "mg"),
         ("Sodium", facts.sodiumMg, "mg"),
         ("Potassium", facts.potassiumMg, "mg"),
         ("Calcium", facts.calciumMg, "mg"),
         ("Iron", facts.ironMg, "mg")]
    }

    var body: some View {
        ForEach(rows.filter { !compact || $0.value > 0 }, id: \.name) { row in
            HStack {
                Text(row.name)
                Spacer()
                Text(Nutrient.format(row.value, unit: row.unit))
                    .foregroundStyle(.secondary)
            }
            .font(compact ? .subheadline : .body)
        }
    }
}

enum Nutrient {
    static func format(_ value: Double, unit: String) -> String {
        let shown: String
        if unit == "mg" || value >= 10 {
            shown = "\(Int(value.rounded()))"
        } else {
            shown = value.formatted(.number.precision(.fractionLength(0...1)))
        }
        return unit.isEmpty ? shown : "\(shown) \(unit)"
    }
}

// MARK: - Single food detail (editable)

/// Nutrition label for one logged food — every value is editable in place,
/// so estimates can be corrected after logging. Saves straight to the log;
/// the density color re-buckets from the edited numbers.
struct FoodNutritionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var food: FoodLog

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        if let d = FoodDensity(rawValue: food.density ?? "") {
                            Circle().fill(d.color).frame(width: 10, height: 10)
                        }
                        TextField("Name", text: $food.name)
                            .font(.headline)
                    }
                    Picker("Meal", selection: Binding(
                        get: { food.meal ?? .lunch },
                        set: { food.meal = $0 }
                    )) {
                        ForEach(Meal.allCases) { m in
                            Label(m.label, systemImage: m.icon).tag(m)
                        }
                    }
                    HStack {
                        Text("Portion (g)")
                        Spacer()
                        TextField("–", value: $food.grams, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        TextField("0", value: $food.calories, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .bold()
                    }
                    HStack {
                        Text("Protein (g)")
                        Spacer()
                        TextField("0", value: $food.proteinGrams, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .bold()
                    }
                    editRow("Carbs (g)", $food.carbsGrams)
                    editRow("Fat (g)", $food.fatGrams)
                } header: {
                    Text("Nutrition — tap a value to fix it")
                } footer: {
                    if food.source == "ai" || food.source == "custom" {
                        Text("Estimated values — adjust anything that looks off; changes save automatically.")
                    }
                }
                Section("Detail") {
                    editRow("Saturated Fat (g)", $food.saturatedFatGrams)
                    editRow("Trans Fat (g)", $food.transFatGrams)
                    editRow("Cholesterol (mg)", $food.cholesterolMg)
                    editRow("Sodium (mg)", $food.sodiumMg)
                    editRow("Fiber (g)", $food.fiberGrams)
                    editRow("Total Sugar (g)", $food.sugarGrams)
                    editRow("Added Sugar (g)", $food.addedSugarGrams)
                    editRow("Potassium (mg)", $food.potassiumMg)
                    editRow("Calcium (mg)", $food.calciumMg)
                    editRow("Iron (mg)", $food.ironMg)
                }
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Food Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        rebucketDensity()
                        dismiss()
                    }
                }
            }
            .onDisappear { rebucketDensity() }
        }
        .themedRoot()
        .presentationDetents([.medium, .large])
    }

    private func rebucketDensity() {
        guard let g = food.grams, g > 0, food.calories > 0 else { return }
        food.density = FoodDensity(caloriesPer100g: Double(food.calories) / g * 100)?.rawValue
    }

    private func editRow(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Daily nutrient goals

/// Daily limits/goals. Defaults are FDA daily values; a logged lab panel
/// (opt-in) tightens the relevant ones — framed as talking points for the
/// doctor, not medical advice.
struct NutrientGoals {
    var satFatG = 20.0
    var cholesterolMg = 300.0
    var sodiumMg = 2300.0
    var addedSugarG = 50.0
    var fiberG = 28.0
    var note: String?

    static func adjusted(for labs: LabResult?) -> NutrientGoals {
        var goals = NutrientGoals()
        guard let labs else { return goals }
        var reasons: [String] = []
        if (labs.ldl ?? 0) >= 130 || (labs.triglycerides ?? 0) >= 150 {
            goals.satFatG = 13
            goals.cholesterolMg = 200
            goals.fiberG = 35
            reasons.append("cholesterol")
        }
        if (labs.fastingGlucose ?? 0) >= 100 || (labs.a1c ?? 0) >= 5.7 {
            goals.addedSugarG = 25
            reasons.append("blood sugar")
        }
        if !reasons.isEmpty {
            goals.note = "Some targets are tightened because of the \(reasons.joined(separator: " and ")) numbers you logged. These are general guardrails, not medical advice — bring them to your doctor."
        }
        return goals
    }
}

// MARK: - Whole-day nutrition report

/// Noom-level day report: energy + macro split, "keep under" limits,
/// "get enough" goals, calorie-density mix, and per-meal breakdown —
/// built from the detailed nutrition every logged food now carries.
struct DayNutritionView: View {
    let day: DayLog
    let targets: DailyTargets
    var goals = NutrientGoals()

    private var facts: NutritionFacts { day.totalFacts }

    // Macro calories only cover itemized foods (quick-add is calories-only).
    private var proteinCal: Double { Double(day.foodProtein) * 4 }
    private var carbsCal: Double { facts.carbsGrams * 4 }
    private var fatCal: Double { facts.fatGrams * 9 }
    private var macroCal: Double { max(proteinCal + carbsCal + fatCal, 1) }

    var body: some View {
        Form {
            Section {
                TargetRow(label: "Calories", value: Double(day.totalCalories),
                          target: Double(targets.calories), unit: "cal", limit: true)
                if day.alcoholCalories > 0 {
                    HStack {
                        Text("From alcohol")
                        Spacer()
                        Text("\(day.alcoholCalories) cal").foregroundStyle(.secondary)
                    }
                }
            } header: {
                SectionHeader(icon: "flame.fill", title: "Energy")
            }

            Section {
                TargetRow(label: "Protein", value: Double(day.totalProtein),
                          target: Double(targets.proteinGrams), unit: "g")
                macroRow("Protein", grams: Double(day.foodProtein), cal: proteinCal)
                macroRow("Carbs", grams: facts.carbsGrams, cal: carbsCal)
                macroRow("Fat", grams: facts.fatGrams, cal: fatCal)
            } header: {
                SectionHeader(icon: "chart.pie.fill", title: "Macros")
            } footer: {
                Text("Percentages are the calorie split across itemized foods. A rough guide: 10–35% protein, 45–65% carbs, 20–35% fat.")
            }

            Section {
                TargetRow(label: "Saturated Fat", value: facts.saturatedFatGrams,
                          target: goals.satFatG, unit: "g", limit: true)
                HStack {
                    Text("Trans Fat")
                    Spacer()
                    Text(Nutrient.format(facts.transFatGrams, unit: "g"))
                        .foregroundStyle(facts.transFatGrams > 0 ? Theme.danger : .secondary)
                }
                TargetRow(label: "Cholesterol", value: facts.cholesterolMg,
                          target: goals.cholesterolMg, unit: "mg", limit: true)
                TargetRow(label: "Sodium", value: facts.sodiumMg,
                          target: goals.sodiumMg, unit: "mg", limit: true)
                TargetRow(label: "Added Sugar", value: facts.addedSugarGrams,
                          target: goals.addedSugarG, unit: "g", limit: true)
                HStack {
                    Text("Total Sugar")
                    Spacer()
                    Text(Nutrient.format(facts.sugarGrams, unit: "g"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader(icon: "arrow.down.circle.fill", title: "Keep Under")
            } footer: {
                Text(goals.note ?? "Daily limits: ≤\(Int(goals.satFatG)) g saturated fat, 0 g trans fat, ≤\(Int(goals.cholesterolMg)) mg cholesterol, ≤\(Int(goals.sodiumMg)) mg sodium, ≤\(Int(goals.addedSugarG)) g added sugar.")
            }

            Section {
                TargetRow(label: "Fiber", value: facts.fiberGrams, target: goals.fiberG, unit: "g")
                TargetRow(label: "Potassium", value: facts.potassiumMg,
                          target: 4700, unit: "mg")
                TargetRow(label: "Calcium", value: facts.calciumMg,
                          target: 1300, unit: "mg")
                TargetRow(label: "Iron", value: facts.ironMg, target: 18, unit: "mg")
            } header: {
                SectionHeader(icon: "arrow.up.heart.fill", title: "Get Enough")
            } footer: {
                Text("FDA daily values. Database entries sometimes omit micronutrients, so these can read low — described or photographed meals carry the full panel.")
            }

            if !day.foods.isEmpty {
                Section {
                    densityRow(.green)
                    densityRow(.orange)
                    densityRow(.red)
                } header: {
                    SectionHeader(icon: "circle.hexagongrid.fill", title: "Calorie Density Mix")
                } footer: {
                    Text("Noom-style: aim for most of your calories from green (under 1 cal/g) foods, and keep red (over 2.4 cal/g) portions small.")
                }

                Section {
                    ForEach(Meal.allCases) { meal in
                        let foods = day.foods(for: meal)
                        if !foods.isEmpty {
                            mealRow(label: meal.label, icon: meal.icon, foods: foods)
                        }
                    }
                    let unassigned = day.foods(for: nil)
                    if !unassigned.isEmpty {
                        mealRow(label: "Other", icon: "fork.knife", foods: unassigned)
                    }
                } header: {
                    SectionHeader(icon: "fork.knife", title: "By Meal")
                }
            }
        }
        .themedForm()
        .navigationTitle("Nutrition Report")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func macroRow(_ label: String, grams: Double, cal: Double) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Nutrient.format(grams, unit: "g"))  ·  \(Int((cal / macroCal * 100).rounded()))%")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func densityRow(_ density: FoodDensity) -> some View {
        let foods = day.foods.filter { $0.density == density.rawValue }
        let cal = foods.reduce(0) { $0 + $1.calories }
        let share = day.foodCalories > 0 ? Double(cal) / Double(day.foodCalories) : 0
        return HStack(spacing: 8) {
            Circle().fill(density.color).frame(width: 10, height: 10)
            Text("\(foods.count) item\(foods.count == 1 ? "" : "s")")
            Spacer()
            Text("\(cal) cal · \(Int((share * 100).rounded()))%")
                .foregroundStyle(.secondary)
        }
    }

    private func mealRow(label: String, icon: String, foods: [FoodLog]) -> some View {
        let cal = foods.reduce(0) { $0 + $1.calories }
        let protein = foods.reduce(0) { $0 + $1.proteinGrams }
        return HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text("\(cal) cal · \(protein) g protein")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// Progress toward a daily amount; red bar when a limit is blown.
private struct TargetRow: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String
    var limit = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Nutrient.format(value, unit: "")) / \(Nutrient.format(target, unit: unit))")
                    .font(.subheadline)
                    .foregroundStyle(limit && value > target ? Theme.danger : .secondary)
            }
            GradientBar(value: target > 0 ? value / target : 0, overIsBad: limit)
        }
        .padding(.vertical, 2)
    }
}
