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
///
/// Three things make the ideas usable rather than decorative:
///
/// - **Eating out.** "Cook this at home" is the wrong answer when you're
///   already in the car. Tapping Restaurants asks for location *then*, turns
///   one fix into a neighbourhood name, and searches real menus near it.
/// - **Refresh, one at a time.** Three ideas where you like two is the normal
///   case. Each row can be swapped on its own, and the ones on screen are sent
///   as a do-not-repeat list so a refresh is genuinely different.
/// - **Keeping one.** An idea worth eating twice belongs in Saved Meals, so it
///   logs in a tap next time rather than being re-asked for.
struct MealIdeasView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var day: DayLog
    let targets: DailyTargets
    var labs: AIFoodEstimator.LabSnapshot?
    var preferences: FoodPreferences = .empty
    /// Which meal these get logged under. Defaults to whatever's next.
    var meal: Meal = .suggested()
    /// The specific meal target, when the ask came from the day plan.
    var brief: AIFoodEstimator.MealBrief?

    /// Where the ideas are coming from.
    private enum Source: Hashable {
        case home
        /// Restaurants near a resolved place name.
        case nearby(String)

        var isNearby: Bool { if case .nearby = self { return true } else { return false } }
        var placeName: String? { if case .nearby(let p) = self { return p } else { return nil } }
    }

    @State private var source: Source = .home
    @State private var suggestions: [AIFoodEstimator.MealSuggestion] = []
    @State private var loading = false
    @State private var error: String?
    @State private var loggedIDs: Set<UUID> = []
    @State private var savedIDs: Set<UUID> = []
    /// Rows waiting on their own replacement.
    @State private var refreshingIDs: Set<UUID> = []
    @State private var locating = false
    @State private var showLocationExplainer = false

    private var remainingCalories: Int { max(0, targets.calories - day.totalCalories) }
    private var remainingProtein: Int { max(0, targets.proteinGrams - day.totalProtein) }

    var body: some View {
        NavigationStack {
            Form {
                targetSection
                sourceSection

                if !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions) { s in
                            suggestionRow(s)
                        }
                    } header: {
                        Text(source.isNearby ? "Near You" : "Ideas That Fit")
                    } footer: {
                        Text(source.isNearby
                             ? "Menus and nutrition change and chains vary by location — treat these as a starting point and fix any number after logging. Tap ↻ on one you don't fancy."
                             : "Estimates — every number stays editable after logging. Tap ↻ on one you don't fancy.")
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button {
                            self.error = nil
                            Task { await load(reset: true) }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(loadingLine).foregroundStyle(.secondary)
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
            .confirmationDialog("Find food near you?",
                                isPresented: $showLocationExplainer,
                                titleVisibility: .visible) {
                Button("Use My Location Once") {
                    Task { await loadNearby() }
                }
                Button("Not Now", role: .cancel) {}
            } message: {
                Text("Steady checks where you are once, right now, to work out the neighbourhood to search — that neighbourhood name is all that's sent. Your location isn't saved, isn't kept in history, and never leaves the device.")
            }
            .task { await load() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var targetSection: some View {
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
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section {
            Button {
                Haptics.tap()
                if source.isNearby {
                    // Already out — this is "look again".
                    Task { await loadNearby() }
                } else if PlaceLocator.shared.needsPermission {
                    showLocationExplainer = true
                } else {
                    Task { await loadNearby() }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.headline)
                        .foregroundStyle(source.isNearby ? Theme.accent : Theme.foodTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.isNearby ? "Look again near you" : "Feeling restaurants?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(source.placeName.map { "Searching menus around \($0)" }
                             ?? "Healthy orders at real places near you, sized to this meal")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if locating { ProgressView() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locating || loading)
            .accessibilityIdentifier("ideas.restaurants")

            if source.isNearby {
                Button {
                    Haptics.tap()
                    source = .home
                    Task { await load(reset: true) }
                } label: {
                    Label("Back to at-home ideas", systemImage: "house")
                        .font(.caption.bold())
                }
            }
        } footer: {
            Text(source.isNearby
                 ? "Location was used once to name the neighbourhood and wasn't stored."
                 : "Location is only ever checked when you tap this, and never saved.")
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
            if let restaurant = s.restaurant, !restaurant.isEmpty {
                Label(restaurant, systemImage: "fork.knife")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
            if let order = s.order, !order.isEmpty {
                Label(order, systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !s.why.isEmpty {
                Text(s.why).font(.caption).foregroundStyle(.secondary)
            }
            if let assumed = s.assumed, !assumed.isEmpty {
                Text(assumed).font(.caption2).foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
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

                Button {
                    save(s)
                } label: {
                    Label(savedIDs.contains(s.id) ? "Saved" : "Save",
                          systemImage: savedIDs.contains(s.id) ? "bookmark.fill" : "bookmark")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .tint(savedIDs.contains(s.id) ? .green : Theme.foodTint)
                .disabled(savedIDs.contains(s.id))

                Button {
                    Task { await refresh(s) }
                } label: {
                    if refreshingIDs.contains(s.id) {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.bold())
                    }
                }
                .buttonStyle(.bordered)
                .tint(Theme.textDim)
                .disabled(refreshingIDs.contains(s.id) || loading)
                .accessibilityLabel("Swap this idea for another")
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var loadingLine: String {
        if locating { return "Working out what's around you…" }
        return source.isNearby ? "Reading menus near you…" : "Thinking about what fits…"
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

    // MARK: - Actions

    private func log(_ s: AIFoodEstimator.MealSuggestion) {
        let food = FoodLog(name: logName(s), calories: s.calories,
                           proteinGrams: s.proteinGrams, grams: s.grams,
                           source: "ai", density: s.density, facts: s.facts)
        day.addFood(food, meal: meal)
        loggedIDs.insert(s.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Keep it for next time. One item, one serving — the same shape as a meal
    /// snapshotted off a day's log, so it lands in Saved Meals and logs in a
    /// tap from Add Food.
    private func save(_ s: AIFoodEstimator.MealSuggestion) {
        let saved = SavedMeal(name: logName(s), servings: 1, defaultMeal: meal)
        saved.notes = [s.order, s.assumed].compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        saved.items.append(SavedMealItem(name: logName(s),
                                         orderIndex: 0,
                                         calories: s.calories,
                                         proteinGrams: s.proteinGrams,
                                         grams: s.grams,
                                         source: "ai",
                                         density: s.density,
                                         facts: s.facts))
        context.insert(saved)
        try? context.save()
        savedIDs.insert(s.id)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// "Chicken bowl — Sweetgreen (Ballard)" reads better in a log than either
    /// half on its own, and a month later it's the only thing that says where
    /// the numbers came from.
    private func logName(_ s: AIFoodEstimator.MealSuggestion) -> String {
        guard let restaurant = s.restaurant, !restaurant.isEmpty else { return s.name }
        return "\(s.name) — \(restaurant)"
    }

    /// Swap one idea for something else, telling the model what's already on
    /// screen so it doesn't hand back the same thing in a different order.
    private func refresh(_ s: AIFoodEstimator.MealSuggestion) async {
        refreshingIDs.insert(s.id)
        defer { refreshingIDs.remove(s.id) }
        do {
            let replacements = try await ask(count: 1,
                                             avoid: suggestions.map(\.name),
                                             nearby: source.placeName)
            guard let replacement = replacements.first,
                  let index = suggestions.firstIndex(where: { $0.id == s.id }) else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                suggestions[index] = replacement
            }
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func load(reset: Bool = false) async {
        if reset {
            suggestions = []
            loggedIDs = []
            savedIDs = []
        }
        guard suggestions.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            suggestions = try await ask(count: 3, avoid: [], nearby: source.placeName)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Ask where you are — once — and then ask for menus around there.
    private func loadNearby() async {
        locating = true
        error = nil
        do {
            let place = try await PlaceLocator.shared.nearbyPlaceName()
            locating = false
            source = .nearby(place)
            suggestions = []
            loggedIDs = []
            savedIDs = []
            loading = true
            defer { loading = false }
            suggestions = try await ask(count: 3, avoid: [], nearby: place)
        } catch {
            locating = false
            self.error = error.localizedDescription
        }
    }

    private func ask(count: Int, avoid: [String],
                     nearby: String?) async throws -> [AIFoodEstimator.MealSuggestion] {
        try await AIFoodEstimator.suggestMeals(
            meal: (brief?.label ?? meal.label).lowercased(),
            remainingCalories: remainingCalories,
            remainingProtein: remainingProtein,
            eatenToday: day.foods.map(\.name),
            labs: labs,
            preferences: preferences,
            brief: brief,
            count: count,
            avoid: avoid,
            nearby: nearby)
    }
}
