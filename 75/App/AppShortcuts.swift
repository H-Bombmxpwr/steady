import AppIntents
import SwiftData
import WidgetKit
import Foundation

// MARK: - Intents ("Hey Siri, log water in 75")

/// Adds one bottle/step of water to today — same as the widget button.
struct QuickLogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Adds one bottle/step of water to today's log.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared.container)
        guard let plan = try? context.fetch(FetchDescriptor<Plan>()).first else {
            return .result(dialog: "Set up your plan in the app first.")
        }
        let day = ensureDay(plan: plan, date: Date())
        let step = max(1, plan.waterStepOunces)
        day.waterOunces += step
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Added \(step) ounces — \(day.waterOunces) total today.")
    }
}

/// Describe a meal by voice; it's itemized with full nutrition and logged
/// to the current meal of the day.
struct LogMealIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a Meal"
    static var description = IntentDescription("Describe what you ate and it's logged with full nutrition.")

    @Parameter(title: "What did you eat?",
               requestValueDialog: "What did you eat?")
    var mealDescription: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = ModelContext(PersistenceController.shared.container)
        guard let plan = try? context.fetch(FetchDescriptor<Plan>()).first else {
            return .result(dialog: "Set up your plan in the app first.")
        }
        let breakdown: AIFoodEstimator.MealBreakdown
        do {
            breakdown = try await AIFoodEstimator.mealBreakdown(description: mealDescription)
        } catch {
            return .result(dialog: "Couldn't estimate that meal — check your connection and try again.")
        }
        let day = ensureDay(plan: plan, date: Date())
        let meal = Meal.suggested()
        for item in breakdown.items {
            day.addFood(FoodLog(name: item.name,
                                calories: item.calories,
                                proteinGrams: item.proteinGrams,
                                grams: item.grams,
                                source: "ai",
                                density: item.density,
                                facts: item.facts),
                        meal: meal)
        }
        WidgetCenter.shared.reloadAllTimelines()
        let cal = breakdown.items.reduce(0) { $0 + $1.calories }
        let protein = breakdown.items.reduce(0) { $0 + $1.proteinGrams }
        return .result(dialog: """
        Logged \(breakdown.items.count) item\(breakdown.items.count == 1 ? "" : "s") \
        to \(meal.label.lowercased()) — \(cal) calories, \(protein) grams of protein.
        """)
    }
}

/// Jumps straight into today's log.
struct OpenTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Today"
    static var description = IntentDescription("Opens today's log.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "seventyfive://today")!))
    }
}

// MARK: - Shortcut phrases

struct SeventyFiveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: QuickLogWaterIntent(),
                    phrases: ["Log water in \(.applicationName)",
                              "Add water in \(.applicationName)"],
                    shortTitle: "Log Water",
                    systemImageName: "drop.fill")
        AppShortcut(intent: LogMealIntent(),
                    phrases: ["Log a meal in \(.applicationName)",
                              "Log food in \(.applicationName)"],
                    shortTitle: "Log Meal",
                    systemImageName: "fork.knife")
        AppShortcut(intent: OpenTodayIntent(),
                    phrases: ["Open today in \(.applicationName)"],
                    shortTitle: "Today",
                    systemImageName: "square.and.pencil")
    }
}
