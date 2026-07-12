import Foundation
import SwiftData

/// Which meal of the day a food was logged under. Day totals always span
/// every meal; this only drives grouping and defaults.
enum Meal: String, CaseIterable, Identifiable, Codable {
    case breakfast
    case morningSnack = "morning_snack"
    case lunch
    case afternoonSnack = "afternoon_snack"
    case dinner
    case dessert

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .morningSnack: return "Morning Snack"
        case .lunch: return "Lunch"
        case .afternoonSnack: return "Afternoon Snack"
        case .dinner: return "Dinner"
        case .dessert: return "Dessert"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .morningSnack: return "carrot.fill"
        case .lunch: return "sun.max.fill"
        case .afternoonSnack: return "leaf.fill"
        case .dinner: return "moon.stars.fill"
        case .dessert: return "birthday.cake.fill"
        }
    }

    /// Sensible default for "log food right now".
    static func suggested(at date: Date = Date()) -> Meal {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = (comps.hour ?? 12) * 60 + (comps.minute ?? 0)
        switch minutes {
        case ..<(10 * 60): return .breakfast
        case ..<(11 * 60 + 30): return .morningSnack
        case ..<(14 * 60 + 30): return .lunch
        case ..<(17 * 60): return .afternoonSnack
        case ..<(20 * 60 + 30): return .dinner
        default: return .dessert
        }
    }
}

/// Micronutrients + macro detail for one logged portion (grams / mg as
/// named). Everything defaults to 0 so pre-existing logs migrate cleanly
/// and manual entries just leave what they don't know.
struct NutritionFacts: Codable, Equatable {
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var saturatedFatGrams: Double = 0
    var transFatGrams: Double = 0
    var cholesterolMg: Double = 0
    var sodiumMg: Double = 0
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var addedSugarGrams: Double = 0
    var potassiumMg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0

    mutating func add(_ other: NutritionFacts) {
        carbsGrams += other.carbsGrams
        fatGrams += other.fatGrams
        saturatedFatGrams += other.saturatedFatGrams
        transFatGrams += other.transFatGrams
        cholesterolMg += other.cholesterolMg
        sodiumMg += other.sodiumMg
        fiberGrams += other.fiberGrams
        sugarGrams += other.sugarGrams
        addedSugarGrams += other.addedSugarGrams
        potassiumMg += other.potassiumMg
        calciumMg += other.calciumMg
        ironMg += other.ironMg
    }

    func scaled(by factor: Double) -> NutritionFacts {
        NutritionFacts(carbsGrams: carbsGrams * factor,
                       fatGrams: fatGrams * factor,
                       saturatedFatGrams: saturatedFatGrams * factor,
                       transFatGrams: transFatGrams * factor,
                       cholesterolMg: cholesterolMg * factor,
                       sodiumMg: sodiumMg * factor,
                       fiberGrams: fiberGrams * factor,
                       sugarGrams: sugarGrams * factor,
                       addedSugarGrams: addedSugarGrams * factor,
                       potassiumMg: potassiumMg * factor,
                       calciumMg: calciumMg * factor,
                       ironMg: ironMg * factor)
    }
}

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

    /// Anything at all logged this day — what keeps a relaxed streak alive.
    var hasActivity: Bool {
        weight != nil || waterOunces > 0 || totalCalories > 0 || !foods.isEmpty
            || !workouts.isEmpty || !photos.isEmpty || !takenSupplements.isEmpty
            || standardDrinks > 0 || !(notes ?? "").isEmpty
    }

    /// Whole-day micronutrient totals across every meal's logged foods.
    var totalFacts: NutritionFacts {
        foods.reduce(into: NutritionFacts()) { $0.add($1.facts) }
    }

    func foods(for meal: Meal?) -> [FoodLog] {
        foods.filter { $0.meal == meal }.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Food mutations — the only way food should be added or removed.
    // Each one updates the relationship array (so views refresh immediately)
    // AND saves right away (so nothing depends on an onDisappear that may
    // never run). Deleting only via `context.delete` leaves the tombstoned
    // object in `foods` until some later save — that was the "delete never
    // works until I relaunch" bug.

    func addFood(_ log: FoodLog, meal: Meal?) {
        if let meal { log.meal = meal }
        foods.append(log)
        try? modelContext?.save()
    }

    func removeFood(_ log: FoodLog) {
        foods.removeAll { $0.persistentModelID == log.persistentModelID }
        log.modelContext?.delete(log)
        try? modelContext?.save()
    }

    /// Deletes everything logged under one meal (nil = the "Other" group).
    func removeMeal(_ meal: Meal?) {
        let doomed = foods(for: meal)
        let doomedIDs = Set(doomed.map(\.persistentModelID))
        foods.removeAll { doomedIDs.contains($0.persistentModelID) }
        doomed.forEach { $0.modelContext?.delete($0) }
        try? modelContext?.save()
    }
}

@Model
final class WorkoutLog {
    var name: String
    var minutes: Int
    var outdoor: Bool
    var categoryRaw: String = WorkoutCategory.other.rawValue
    var createdAt: Date
    /// HealthKit workout UUID when this log was imported from Health
    /// (Apple Watch, Garmin…) — the dedupe key so re-imports are no-ops.
    var healthKitID: String? = nil
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
    var mealRaw: String = ""          // Meal.rawValue; "" on logs predating meals
    var favorite: Bool = false        // pinned to Quick Log in Add Food
    var createdAt: Date

    // Micronutrients for this portion (all 0 when the source didn't know).
    var carbsGrams: Double = 0
    var fatGrams: Double = 0
    var saturatedFatGrams: Double = 0
    var transFatGrams: Double = 0
    var cholesterolMg: Double = 0
    var sodiumMg: Double = 0
    var fiberGrams: Double = 0
    var sugarGrams: Double = 0
    var addedSugarGrams: Double = 0
    var potassiumMg: Double = 0
    var calciumMg: Double = 0
    var ironMg: Double = 0

    init(name: String, calories: Int, proteinGrams: Int, grams: Double? = nil,
         source: String = "custom", density: String? = nil,
         meal: Meal? = nil, facts: NutritionFacts = NutritionFacts()) {
        self.name = name
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.grams = grams
        self.source = source
        self.density = density
        self.mealRaw = meal?.rawValue ?? ""
        self.createdAt = Date()
        self.facts = facts
    }

    var meal: Meal? {
        get { Meal(rawValue: mealRaw) }
        set { mealRaw = newValue?.rawValue ?? "" }
    }

    var facts: NutritionFacts {
        get {
            NutritionFacts(carbsGrams: carbsGrams,
                           fatGrams: fatGrams,
                           saturatedFatGrams: saturatedFatGrams,
                           transFatGrams: transFatGrams,
                           cholesterolMg: cholesterolMg,
                           sodiumMg: sodiumMg,
                           fiberGrams: fiberGrams,
                           sugarGrams: sugarGrams,
                           addedSugarGrams: addedSugarGrams,
                           potassiumMg: potassiumMg,
                           calciumMg: calciumMg,
                           ironMg: ironMg)
        }
        set {
            carbsGrams = newValue.carbsGrams
            fatGrams = newValue.fatGrams
            saturatedFatGrams = newValue.saturatedFatGrams
            transFatGrams = newValue.transFatGrams
            cholesterolMg = newValue.cholesterolMg
            sodiumMg = newValue.sodiumMg
            fiberGrams = newValue.fiberGrams
            sugarGrams = newValue.sugarGrams
            addedSugarGrams = newValue.addedSugarGrams
            potassiumMg = newValue.potassiumMg
            calciumMg = newValue.calciumMg
            ironMg = newValue.ironMg
        }
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
