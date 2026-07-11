import Foundation
import SwiftData

@Model
final class DayLog {
    var date: Date
    var weight: Double?               // lb
    var waterOunces: Int
    var caloriesEaten: Int            // manual quick-add, on top of logged foods
    var proteinGrams: Int             // manual quick-add, on top of logged foods
    var standardDrinks: Double = 0    // 1 std drink = 14 g alcohol (12 oz beer / 5 oz wine / 1.5 oz spirits)
    var takenSupplements: [String] = []
    var notes: String?

    @Relationship(deleteRule: .cascade) var workouts: [WorkoutLog]
    @Relationship(deleteRule: .cascade) var foods: [FoodLog]
    @Relationship(deleteRule: .cascade) var photos: [PhotoEntry]

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.weight = nil
        self.waterOunces = 0
        self.caloriesEaten = 0
        self.proteinGrams = 0
        self.standardDrinks = 0
        self.takenSupplements = []
        self.notes = nil
        self.workouts = []
        self.foods = []
        self.photos = []
    }

    var workoutMinutes: Int { workouts.reduce(0) { $0 + $1.minutes } }

    /// ~98 kcal per standard drink (14 g ethanol × 7 kcal/g), counted so
    /// drinks don't silently escape the budget.
    var alcoholCalories: Int { Int((standardDrinks * 98).rounded()) }

    var foodCalories: Int { foods.reduce(0) { $0 + $1.calories } }
    var foodProtein: Int { foods.reduce(0) { $0 + $1.proteinGrams } }

    var totalCalories: Int { caloriesEaten + foodCalories + alcoholCalories }
    var totalProtein: Int { proteinGrams + foodProtein }
}

@Model
final class WorkoutLog {
    var name: String
    var minutes: Int
    var outdoor: Bool
    var categoryRaw: String = WorkoutCategory.other.rawValue
    var createdAt: Date
    @Relationship(deleteRule: .cascade) var sets: [SetLog] = []

    init(name: String, minutes: Int, outdoor: Bool = false, category: WorkoutCategory = .other) {
        self.name = name
        self.minutes = minutes
        self.outdoor = outdoor
        self.categoryRaw = category.rawValue
        self.createdAt = Date()
        self.sets = []
    }

    var category: WorkoutCategory {
        get { WorkoutCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

/// One performed set — the strength log behind progressive-overload history.
@Model
final class SetLog {
    var exerciseName: String
    var setIndex: Int = 0
    var reps: Int = 0
    var weightLbs: Double?
    var createdAt: Date = Date()

    init(exerciseName: String, setIndex: Int = 0, reps: Int = 0, weightLbs: Double? = nil) {
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.reps = reps
        self.weightLbs = weightLbs
        self.createdAt = Date()
    }
}

@Model
final class FoodLog {
    var name: String
    var calories: Int
    var proteinGrams: Int
    var grams: Double?                // portion size when known
    var source: String                // "off" | "barcode" | "custom" | "ai"
    var density: String? = nil        // calorie density: "green" | "orange" | "red"
    var createdAt: Date

    init(name: String, calories: Int, proteinGrams: Int, grams: Double? = nil,
         source: String = "custom", density: String? = nil) {
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.grams = grams
        self.source = source
        self.density = density
        self.createdAt = Date()
    }
}

@Model
final class PhotoEntry {
    var filename: String
    var createdAt: Date

    init(filename: String) {
        self.filename = filename
        self.createdAt = Date()
    }
}
