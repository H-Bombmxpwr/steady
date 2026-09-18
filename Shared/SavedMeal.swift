import Foundation
import SwiftData

/// A meal worth repeating — a named snapshot of logged foods ("my usual
/// breakfast", "chipotle order") that re-logs in one tap from Add Food.
@Model
final class SavedMeal {
    var name: String
    var createdAt: Date

    // Additive and defaulted — meals saved before recipes existed are simply
    // one-serving meals with no source, which is exactly what they were.

    /// How many servings the stored items add up to. A meal snapshotted from
    /// a day's log is one serving by definition; a recipe usually isn't, and
    /// storing the batch with its yield is what lets "I ate a third of it"
    /// be a stepper rather than mental arithmetic.
    var servings: Double = 1
    /// Where a recipe came from, so it can be opened again.
    var sourceURL: String?
    /// The cook's notes / method, kept verbatim when a recipe was imported.
    var notes: String?
    /// Which meal this usually gets logged under, pre-selecting the picker.
    var defaultMealRaw: String?

    @Relationship(deleteRule: .cascade) var items: [SavedMealItem] = []

    init(name: String, servings: Double = 1, sourceURL: String? = nil,
         notes: String? = nil, defaultMeal: Meal? = nil) {
        self.name = name
        self.createdAt = Date()
        self.servings = max(0.25, servings)
        self.sourceURL = sourceURL
        self.notes = notes
        self.defaultMealRaw = defaultMeal?.rawValue
    }

    var orderedItems: [SavedMealItem] {
        items.sorted { $0.orderIndex < $1.orderIndex }
    }

    var defaultMeal: Meal? {
        get { defaultMealRaw.flatMap(Meal.init(rawValue:)) }
        set { defaultMealRaw = newValue?.rawValue }
    }

    var isRecipe: Bool { servings > 1 || !(sourceURL ?? "").isEmpty }

    /// Totals for the whole batch as stored.
    var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int { items.reduce(0) { $0 + $1.proteinGrams } }

    /// Totals for one serving — what the row in Add Food should actually say.
    var caloriesPerServing: Int { Int((Double(totalCalories) / max(0.25, servings)).rounded()) }
    var proteinPerServing: Int { Int((Double(totalProtein) / max(0.25, servings)).rounded()) }

    /// The fraction of the stored batch represented by `count` servings.
    func factor(forServings count: Double) -> Double {
        count / max(0.25, servings)
    }

    /// Fresh logs for however many servings are being eaten. Every number —
    /// calories, protein, the whole micronutrient panel — scales together.
    func makeLogs(servings count: Double, meal: Meal?) -> [FoodLog] {
        let f = factor(forServings: count)
        return orderedItems.map { $0.makeLog(scaledBy: f, meal: meal) }
    }

    /// "Serves 4 · 520 cal each"
    var servingSummary: String {
        let each = "\(caloriesPerServing) cal · \(proteinPerServing) g protein each"
        guard servings > 1 else { return "\(totalCalories) cal · \(totalProtein) g protein" }
        return "Serves \(servings.formatted()) · \(each)"
    }
}

/// One food inside a saved meal — everything needed to mint a fresh
/// FoodLog, including the full nutrition panel.
@Model
final class SavedMealItem {
    var name: String
    var orderIndex: Int = 0
    var calories: Int
    var proteinGrams: Int
    var grams: Double?
    var source: String
    var density: String?
    var facts: NutritionFacts = NutritionFacts()

    init(name: String, orderIndex: Int = 0, calories: Int, proteinGrams: Int,
         grams: Double? = nil, source: String = "custom", density: String? = nil,
         facts: NutritionFacts = NutritionFacts()) {
        self.name = name
        self.orderIndex = orderIndex
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.grams = grams
        self.source = source
        self.density = density
        self.facts = facts
    }

    /// Snapshot a logged food.
    convenience init(food: FoodLog, orderIndex: Int) {
        self.init(name: food.name, orderIndex: orderIndex,
                  calories: food.calories, proteinGrams: food.proteinGrams,
                  grams: food.grams, source: food.source, density: food.density,
                  facts: food.facts)
    }

    /// Mint a fresh log entry from this saved item, optionally scaled to a
    /// fraction of the stored batch.
    func makeLog(scaledBy factor: Double = 1, meal: Meal? = nil) -> FoodLog {
        FoodLog(name: name,
                calories: Int((Double(calories) * factor).rounded()),
                proteinGrams: Int((Double(proteinGrams) * factor).rounded()),
                grams: grams.map { $0 * factor },
                source: source,
                density: density,
                meal: meal,
                facts: facts.scaled(by: factor))
    }
}
