import SwiftUI
import SwiftData

/// Everything eaten in one meal — tap a food for its full nutrition,
/// swipe to remove it, add more, or delete the whole meal from the toolbar.
struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog
    let meal: Meal?
    let label: String
    let icon: String

    @State private var inspectedFood: FoodLog?
    @State private var confirmDeleteMeal = false

    private var foods: [FoodLog] { day.foods(for: meal) }
    private var calories: Int { foods.reduce(0) { $0 + $1.calories } }
    private var protein: Int { foods.reduce(0) { $0 + $1.proteinGrams } }

    var body: some View {
        Form {
            Section {
                HStack {
                    SectionIcon(systemImage: icon, tint: meal?.color ?? Theme.foodTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.headline)
                        Text("\(calories) cal · \(protein) g protein")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                ForEach(foods) { f in
                    Button { inspectedFood = f } label: {
                        HStack(spacing: 8) {
                            if let d = FoodDensity(rawValue: f.density ?? "") {
                                Circle().fill(d.color).frame(width: 9, height: 9)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).lineLimit(1).foregroundStyle(.primary)
                                Text(subtitle(f))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(f.calories) cal").foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { foods[$0] }.forEach { day.removeFood($0) }
                }
                if let meal {
                    NavigationLink {
                        FoodSearchView(day: day, meal: meal)
                    } label: {
                        Label("Add to \(label)", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            } footer: {
                Text("Tap a food for its full nutrition · swipe to remove it.")
            }
            Section {
                Button(role: .destructive) {
                    confirmDeleteMeal = true
                } label: {
                    Label("Delete \(label)", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .themedForm()
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDeleteMeal = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(Theme.danger)
            }
        }
        .confirmationDialog("Delete \(label)?", isPresented: $confirmDeleteMeal,
                            titleVisibility: .visible) {
            Button("Delete \(foods.count) item\(foods.count == 1 ? "" : "s")",
                   role: .destructive) {
                day.removeMeal(meal)
                dismiss()
            }
        } message: {
            Text("Removes everything logged under \(label) for this day.")
        }
        .sheet(item: $inspectedFood) { FoodNutritionSheet(food: $0) }
    }

    private func subtitle(_ f: FoodLog) -> String {
        var parts: [String] = []
        if let g = f.grams { parts.append("\(Int(g)) g") }
        if f.proteinGrams > 0 { parts.append("\(f.proteinGrams) g protein") }
        if f.source == "barcode" { parts.append("scanned") }
        if f.source == "ai" { parts.append("estimated") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Gemini end-of-day review

/// "Summarize My Day" — Gemini looks at everything eaten vs the targets
/// and suggests concrete swaps for next time.
struct DaySummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let day: DayLog
    let targets: DailyTargets
    var labs: AIFoodEstimator.LabSnapshot? = nil

    @State private var review: AIFoodEstimator.DayReview?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let review {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Circle().fill(Theme.gradient))
                            Text(review.headline)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                    if !review.wins.isEmpty {
                        Section("What Went Well") {
                            ForEach(review.wins, id: \.self) { win in
                                Label {
                                    Text(win)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    if !review.suggestions.isEmpty {
                        Section {
                            ForEach(review.suggestions) { s in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(s.issue)
                                        .font(.subheadline.weight(.semibold))
                                    Label {
                                        Text(s.swap)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } icon: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text("Try These Swaps")
                        } footer: {
                            Text("Based on today's log — take what's useful, skip what isn't.")
                        }
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button {
                            self.error = nil
                            Task { await run() }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Reviewing your day…").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .themedForm()
            .navigationTitle("Day Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await run() }
        }
    }

    private func run() async {
        guard review == nil else { return }
        do {
            review = try await AIFoodEstimator.reviewDay(day: day, targets: targets, labs: labs)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
