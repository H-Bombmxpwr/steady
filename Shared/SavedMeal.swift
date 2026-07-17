import Foundation
import SwiftData

/// A meal worth repeating — a named snapshot of logged foods ("my usual
/// breakfast", "chipotle order") that re-logs in one tap from Add Food.
@Model
final class SavedMeal {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var items: [SavedMealItem] = []

    init(name: String) {
        self.name = name
        self.createdAt = Date()
    }

    var orderedItems: [SavedMealItem] {
        items.sorted { $0.orderIndex < $1.orderIndex }
    }

    var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Int { items.reduce(0) { $0 + $1.proteinGrams } }
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

    /// Mint a fresh log entry from this saved item.
    func makeLog() -> FoodLog {
        FoodLog(name: name, calories: calories, proteinGrams: proteinGrams,
                grams: grams, source: source, density: density, facts: facts)
    }
}
