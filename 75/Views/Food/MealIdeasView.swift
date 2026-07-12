import SwiftUI
import SwiftData

/// "What should I eat?" — Gemini suggests meals that fit what's LEFT of
/// today's budget (calorie ceiling, protein gap, lab-aware when on), and
/// each idea logs with one tap as a normal editable FoodLog.
struct MealIdeasView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog
    let targets: DailyTargets
    var labs: AIFoodEstimator.LabSnapshot?

    @State private var suggestions: [AIFoodEstimator.MealSuggestion] = []
    @State private var error: String?
    @State private var loggedIDs: Set<UUID> = []

    private var remainingCalories: Int { max(0, targets.calories - day.totalCalories) }
    private var remainingProtein: Int { max(0, targets.proteinGrams - day.totalProtein) }
    private var meal: Meal { Meal.suggested() }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        stat("\(remainingCalories)", "cal left", tint: Theme.foodTint)
                        stat("\(remainingProtein) g", "protein to go", tint: Theme.workoutTint)
                        stat(meal.label, "up next", tint: meal.color)
                        Spacer()
                    }
                    .padding(.vertical, 2)
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

    private func load() async {
        guard suggestions.isEmpty else { return }
        do {
            suggestions = try await AIFoodEstimator.suggestMeals(
                meal: meal.label.lowercased(),
                remainingCalories: remainingCalories,
                remainingProtein: remainingProtein,
                eatenToday: day.foods.map(\.name),
                labs: labs)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
