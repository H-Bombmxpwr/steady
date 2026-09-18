import SwiftUI
import SwiftData

/// "What should I eat?" — Gemini suggests meals that fit, and each idea logs
/// with one tap as a normal editable FoodLog.
///
/// "Fit" means one of two things. Opened from the day plan, it means this
/// meal's own target — its calories, carbs, protein, and fat, plus whether
/// it's feeding a session in an hour — which is a far sharper question than
/// the one this screen used to ask. Opened from anywhere else, it falls back
/// to what's left of the day.
///
/// Either way the suggestions are bounded by what the user can actually buy
/// and will actually eat (Settings → Food Preferences), and steered by labs
/// when those are shared.
struct MealIdeasView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog
    let targets: DailyTargets
    var labs: AIFoodEstimator.LabSnapshot?
    var preferences: FoodPreferences = .empty
    /// Which meal these get logged under. Defaults to whatever's next.
    var meal: Meal = .suggested()
    /// The specific meal target, when the ask came from the day plan.
    var brief: AIFoodEstimator.MealBrief?

    @State private var suggestions: [AIFoodEstimator.MealSuggestion] = []
    @State private var error: String?
    @State private var loggedIDs: Set<UUID> = []

    private var remainingCalories: Int { max(0, targets.calories - day.totalCalories) }
    private var remainingProtein: Int { max(0, targets.proteinGrams - day.totalProtein) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        if let brief {
                            stat("\(brief.calories)", "cal target", tint: Theme.foodTint)
                            stat("\(brief.carbGrams) g", "carbs", tint: Theme.foodTint)
                            stat("\(brief.proteinGrams) g", "protein", tint: Theme.workoutTint)
                        } else {
                            stat("\(remainingCalories)", "cal left", tint: Theme.foodTint)
                            stat("\(remainingProtein) g", "protein to go", tint: Theme.workoutTint)
                        }
                        stat(brief?.label ?? meal.label,
                             brief == nil ? "up next" : "this meal",
                             tint: meal.color)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                } footer: {
                    if !preferences.isEmpty {
                        Text(preferenceFooter)
                    }
                }

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { s in
                            suggestionRow(s)
                        }
                    } header: {
                        Text("Ideas That Fit")
                    } footer: {
                        Text("Estimates — every number stays editable after logging.")
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button {
                            self.error = nil
                            Task { await load() }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Thinking about what fits…").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .themedForm()
            .navigationTitle("What Should I Eat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func suggestionRow(_ s: AIFoodEstimator.MealSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(s.calories) cal · \(s.proteinGrams) g")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !s.why.isEmpty {
                Text(s.why).font(.caption).foregroundStyle(.secondary)
            }
            if let assumed = s.assumed, !assumed.isEmpty {
                Text(assumed).font(.caption2).foregroundStyle(.tertiary)
            }
            Button {
                log(s)
            } label: {
                Label(loggedIDs.contains(s.id) ? "Logged" : "Log to \(meal.label)",
                      systemImage: loggedIDs.contains(s.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .tint(loggedIDs.contains(s.id) ? .green : Theme.accent)
            .disabled(loggedIDs.contains(s.id))
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func log(_ s: AIFoodEstimator.MealSuggestion) {
        let food = FoodLog(name: s.name, calories: s.calories,
                           proteinGrams: s.proteinGrams, grams: s.grams,
                           source: "ai", density: s.density, facts: s.facts)
        day.addFood(food, meal: meal)
        loggedIDs.insert(s.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private var preferenceFooter: String {
        var parts: [String] = []
        if !preferences.stores.isEmpty {
            parts.append("Shopping at \(preferences.stores.joined(separator: ", "))")
        }
        if !preferences.dislikes.isEmpty {
            parts.append("skipping \(preferences.dislikes.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ") + "."
    }

    private func load() async {
        guard suggestions.isEmpty else { return }
        do {
            suggestions = try await AIFoodEstimator.suggestMeals(
                meal: (brief?.label ?? meal.label).lowercased(),
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                eatenToday: day.foods.map(\.name),
                labs: labs,
                preferences: preferences,
                brief: brief)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
