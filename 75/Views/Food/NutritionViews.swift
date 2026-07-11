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

// MARK: - Single food detail

/// Nutrition-label style detail for one logged food (tap a row on the day).
struct FoodNutritionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let food: FoodLog

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        if let d = FoodDensity(rawValue: food.density ?? "") {
                            Circle().fill(d.color).frame(width: 10, height: 10)
                        }
                        Text(food.name).font(.headline)
                    }
                    if let meal = food.meal {
                        HStack {
                            Text("Meal")
                            Spacer()
                            Label(meal.label, systemImage: meal.icon)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let g = food.grams {
                        HStack {
                            Text("Portion")
                            Spacer()
                            Text("\(Int(g)) g").foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        Text("\(food.calories) cal").bold()
                    }
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text("\(food.proteinGrams) g").bold()
                    }
                    NutritionFactsRows(facts: food.facts)
                } header: {
                    Text("Nutrition")
                } footer: {
                    if food.facts == NutritionFacts() {
                        Text("No detailed nutrition was recorded for this item — foods logged via AI or the database carry the full panel.")
                    } else if food.source == "ai" || food.source == "custom" {
                        Text("AI-estimated values — treat as close, not exact.")
                    }
                }
            }
            .themedForm()
            .navigationTitle("Food Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .themedRoot()
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Whole-day nutrition report

/// Noom-level day report: energy + macro split, "keep under" limits,
/// "get enough" goals, calorie-density mix, and per-meal breakdown —
/// built from the detailed nutrition every logged food now carries.
struct DayNutritionView: View {
    let day: DayLog
    let targets: DailyTargets

    private var facts: NutritionFacts { day.totalFacts }

    // Macro calories only cover itemized foods (quick-add is calories-only).
    private var proteinCal: Double { Double(day.foodProtein) * 4 }
    private var carbsCal: Double { facts.carbsGrams * 4 }
    private var fatCal: Double { facts.fatGrams * 9 }
    private var macroCal: Double { max(proteinCal + carbsCal + fatCal, 1) }

    var body: some View {
        Form {
            Section("Energy") {
                TargetRow(label: "Calories", value: Double(day.totalCalories),
                          target: Double(targets.calories), unit: "cal", limit: true)
                if day.alcoholCalories > 0 {
                    HStack {
                        Text("From alcohol")
                        Spacer()
                        Text("\(day.alcoholCalories) cal").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                TargetRow(label: "Protein", value: Double(day.totalProtein),
                          target: Double(targets.proteinGrams), unit: "g")
                macroRow("Protein", grams: Double(day.foodProtein), cal: proteinCal)
                macroRow("Carbs", grams: facts.carbsGrams, cal: carbsCal)
                macroRow("Fat", grams: facts.fatGrams, cal: fatCal)
            } header: {
                Text("Macros")
            } footer: {
                Text("Percentages are the calorie split across itemized foods. A rough guide: 10–35% protein, 45–65% carbs, 20–35% fat.")
            }

            Section {
                TargetRow(label: "Saturated Fat", value: facts.saturatedFatGrams,
                          target: 20, unit: "g", limit: true)
                HStack {
                    Text("Trans Fat")
                    Spacer()
                    Text(Nutrient.format(facts.transFatGrams, unit: "g"))
                        .foregroundStyle(facts.transFatGrams > 0 ? Theme.danger : .secondary)
                }
                TargetRow(label: "Cholesterol", value: facts.cholesterolMg,
                          target: 300, unit: "mg", limit: true)
                TargetRow(label: "Sodium", value: facts.sodiumMg,
                          target: 2300, unit: "mg", limit: true)
                TargetRow(label: "Added Sugar", value: facts.addedSugarGrams,
                          target: 50, unit: "g", limit: true)
                HStack {
                    Text("Total Sugar")
                    Spacer()
                    Text(Nutrient.format(facts.sugarGrams, unit: "g"))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Keep Under")
            } footer: {
                Text("Daily limits: ≤20 g saturated fat, 0 g trans fat, ≤300 mg cholesterol, ≤2,300 mg sodium, ≤50 g added sugar.")
            }

            Section {
                TargetRow(label: "Fiber", value: facts.fiberGrams, target: 28, unit: "g")
                TargetRow(label: "Potassium", value: facts.potassiumMg,
                          target: 4700, unit: "mg")
                TargetRow(label: "Calcium", value: facts.calciumMg,
                          target: 1300, unit: "mg")
                TargetRow(label: "Iron", value: facts.ironMg, target: 18, unit: "mg")
            } header: {
                Text("Get Enough")
            } footer: {
                Text("FDA daily values. Database entries sometimes omit micronutrients, so these can read low — AI-logged meals carry the full panel.")
            }

            if !day.foods.isEmpty {
                Section {
                    densityRow(.green)
                    densityRow(.orange)
                    densityRow(.red)
                } header: {
                    Text("Calorie Density Mix")
                } footer: {
                    Text("Noom-style: aim for most of your calories from green (under 1 cal/g) foods, and keep red (over 2.4 cal/g) portions small.")
                }

                Section("By Meal") {
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
