import Foundation
import WidgetKit

/// The precomputed numbers the widget needs but must not compute itself.
/// Widget extensions live under a ~30 MB memory cap; opening the SwiftData
/// stack (let alone walking `plan.days`, which faults every logged day plus
/// its foods/workouts/photos) can spike past that at render time and get the
/// process killed. So the APP writes this tiny snapshot — targets, streak,
/// AND today's live totals — whenever it runs, and the widget only reads it
/// back. The render path never touches the database.
struct WidgetSnapshot: Codable {
    var hasPlan = false
    var calorieBudget = 2000
    var proteinTarget = 120
    var waterGoal = 96
    var waterStep = 8
    var streak = 0
    var goalDate: Date?

    // Today's live totals + the day they belong to, so the widget can tell a
    // fresh snapshot from a stale one (app hasn't run since midnight) without
    // a fetch.
    var caloriesEaten = 0
    var protein = 0
    var waterOz = 0
    var dayDate: Date?

    // Extra stats the large widget has room for.
    var currentWeight: Double = 0    // latest logged weight (lb)
    var startingWeight: Double = 0   // to show pounds lost
    var carbs = 0                    // today's carbs (g)
    var workoutMinutes = 0           // today's logged workout minutes

    // Mealtime check-ins (lock-screen widget + Live Activity). Optional so a
    // snapshot written before these existed still decodes.
    var meals: [MealMoment]?
    var mealsLogged: [String]?

    static let key = "widget.snapshot"
    /// Mirrored by the app's studio so widgets can draw the buddy.
    static let buddySpeciesKey = "buddy.species"
    static let buddyNameKey = "buddy.name"

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults(suiteName: appGroupID)?.set(data, forKey: Self.key)
        }
    }
}

extension WidgetSnapshot {
    /// A copy of this snapshot advanced to `date` with the day's progress
    /// cleared. The timeline uses it for a future-dated midnight entry so the
    /// widget rolls over on its own — targets and streak survive, today's
    /// totals reset — even when no reload lands before morning.
    func rolledOver(to date: Date) -> WidgetSnapshot {
        var s = self
        s.caloriesEaten = 0
        s.protein = 0
        s.waterOz = 0
        s.carbs = 0
        s.workoutMinutes = 0
        s.dayDate = Calendar.current.startOfDay(for: date)
        return s
    }

    /// Updates just today's live totals in the cached snapshot, then reloads
    /// timelines. Cheap by construction: it reads only the day row it is
    /// handed and never walks `plan.days`, so mutation points can call it on
    /// every edit. Targets, streak, and weight keep whatever the last full
    /// `build` wrote — those change rarely and are refreshed on launch and
    /// on background.
    static func refreshTotals(from day: DayLog) {
        guard var cached = load(), cached.hasPlan else { return }
        let today = Calendar.current.startOfDay(for: Date())
        // Editing a past day must not overwrite today's cached numbers.
        guard Calendar.current.isDate(day.date, inSameDayAs: today) else { return }
        cached.caloriesEaten = day.totalCalories
        cached.protein = day.totalProtein
        cached.waterOz = day.waterOunces
        cached.carbs = Int(day.totalFacts.carbsGrams.rounded())
        cached.workoutMinutes = day.workouts.reduce(0) { $0 + $1.minutes }
        cached.mealsLogged = Self.loggedMeals(day)
        // A weigh-in logged today is the newest weight there is, and the large
        // widget shows it — waiting for the next full build means the widget
        // disagrees with the app all morning.
        if let weight = day.weight, weight > 0 { cached.currentWeight = weight }
        cached.dayDate = today
        cached.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Build the full cache the widget reads — targets, streak, and today's
    /// live totals. This walks history for the streak, so it must run in the
    /// APP process only; the widget just calls `load()`.
    static func build(plan: Plan, profile: UserProfile, today: DayLog?) -> WidgetSnapshot {
        let targets = CalorieEngine.targets(profile: profile, plan: plan)
        var s = WidgetSnapshot()
        s.hasPlan = true
        s.calorieBudget = targets.calories
        s.proteinTarget = targets.proteinGrams
        s.waterGoal = targets.waterOunces
        s.waterStep = max(1, plan.waterStepOunces)
        s.streak = CalorieEngine.streakStats(plan: plan, targets: targets).current
        s.goalDate = plan.projectedGoalDate
        s.caloriesEaten = today?.totalCalories ?? 0
        s.protein = today?.totalProtein ?? 0
        s.waterOz = today?.waterOunces ?? 0
        s.dayDate = Calendar.current.startOfDay(for: Date())
        s.currentWeight = plan.currentWeight
        s.startingWeight = plan.startingWeight
        s.carbs = Int((today?.totalFacts.carbsGrams ?? 0).rounded())
        s.workoutMinutes = today?.workouts.reduce(0) { $0 + $1.minutes } ?? 0
        s.meals = mealMoments(plan: plan)
        s.mealsLogged = today.map(loggedMeals) ?? []
        return s
    }

    static func loggedMeals(_ day: DayLog) -> [String] {
        Array(Set(day.foods.map(\.mealRaw).filter { !$0.isEmpty }))
    }

    /// The meals this person actually eats, from their meal schedule (or the
    /// default one if they never opened it).
    static func mealMoments(plan: Plan) -> [MealMoment] {
        let slots = plan.mealSlots.isEmpty ? MealSlot.defaultSchedule() : plan.mealSlots
        return slots.filter(\.enabled)
            .sorted { $0.minutesOfDay < $1.minutesOfDay }
            .map { MealMoment(meal: $0.mealRaw, label: $0.label, minutes: $0.minutesOfDay) }
    }
}

// MARK: - Mealtime

/// One scheduled meal: which, what it's called, minutes past midnight.
struct MealMoment: Codable, Hashable {
    var meal: String
    var label: String
    var minutes: Int
}

/// Where a moment in the day sits against the meal schedule. The lock-screen
/// widget and the Live Activity both render from this, so they always agree.
enum MealState: Equatable {
    /// A meal's window is open and nothing's logged for it yet.
    case due(MealMoment, start: Date, end: Date)
    /// The window is open and it's already logged.
    case logged(MealMoment, next: (MealMoment, Date)?)
    /// Between meals.
    case upcoming(MealMoment, at: Date)
    /// Last meal's window has closed.
    case wrapped

    static func == (a: MealState, b: MealState) -> Bool {
        switch (a, b) {
        case let (.due(m1, s1, e1), .due(m2, s2, e2)): return m1 == m2 && s1 == s2 && e1 == e2
        case let (.logged(m1, _), .logged(m2, _)): return m1 == m2
        case let (.upcoming(m1, d1), .upcoming(m2, d2)): return m1 == m2 && d1 == d2
        case (.wrapped, .wrapped): return true
        default: return false
        }
    }
}

extension WidgetSnapshot {
    /// How long after a meal's time it stays "due" — like BeReal's window,
    /// but long enough to actually eat. Never runs into the next meal.
    static let mealWindow: TimeInterval = 90 * 60

    private func windows(on day: Date) -> [(MealMoment, Date, Date)] {
        let start = Calendar.current.startOfDay(for: day)
        let moments = (meals ?? []).sorted { $0.minutes < $1.minutes }
        return moments.enumerated().map { i, m in
            let begin = start.addingTimeInterval(TimeInterval(m.minutes * 60))
            var end = begin.addingTimeInterval(Self.mealWindow)
            if i + 1 < moments.count {
                end = min(end, start.addingTimeInterval(TimeInterval(moments[i + 1].minutes * 60)))
            }
            return (m, begin, end)
        }
    }

    func isLogged(_ meal: MealMoment, on date: Date) -> Bool {
        guard let day = dayDate, Calendar.current.isDate(day, inSameDayAs: date) else { return false }
        return (mealsLogged ?? []).contains(meal.meal)
    }

    func mealState(at date: Date) -> MealState {
        let today = windows(on: date)
        for (m, begin, end) in today where begin <= date && date < end {
            if isLogged(m, on: date) {
                let next = today.first { $0.1 > date }.map { ($0.0, $0.1) }
                return .logged(m, next: next)
            }
            return .due(m, start: begin, end: end)
        }
        if let next = today.first(where: { $0.1 > date }) {
            return .upcoming(next.0, at: next.1)
        }
        return .wrapped
    }

    /// Breakfast, lunch and dinner: the meals worth chasing when they're missed.
    static let majorMeals: Set<String> = [Meal.breakfast.rawValue, Meal.lunch.rawValue, Meal.dinner.rawValue]

    /// The most recent breakfast, lunch or dinner, if its window has closed
    /// with nothing logged. Snacks can slide; these can't.
    func missedMajorMeal(at date: Date) -> (meal: MealMoment, end: Date)? {
        guard let last = windows(on: date).last(where: { Self.majorMeals.contains($0.0.meal) && $0.1 <= date }),
              last.2 <= date, !isLogged(last.0, on: date) else { return nil }
        return (last.0, last.2)
    }

    /// Meals logged out of those scheduled, for the day `date` falls on.
    func mealProgress(at date: Date) -> (logged: Int, planned: Int) {
        let moments = meals ?? []
        return (moments.filter { isLogged($0, on: date) }.count, moments.count)
    }

    /// Every moment the meal state can change between `from` and `to` —
    /// windows opening and closing, and midnight. The widget timeline puts an
    /// entry at each, so it flips at mealtime with no reload and no push.
    func mealBoundaries(from: Date, to: Date) -> [Date] {
        var out: [Date] = []
        var day = Calendar.current.startOfDay(for: from)
        while day < to {
            out.append(day)
            for (_, begin, end) in windows(on: day) { out += [begin, end] }
            day = Calendar.current.date(byAdding: .day, value: 1, to: day) ?? to
        }
        return out.filter { $0 > from && $0 <= to }.sorted()
    }

    static var buddyAsset: String {
        let raw = UserDefaults(suiteName: appGroupID)?.string(forKey: buddySpeciesKey) ?? "penguin"
        return raw == "blackCat" ? "Studio/black_cat" : "Studio/\(raw)"
    }

    static var buddyName: String {
        UserDefaults(suiteName: appGroupID)?.string(forKey: buddyNameKey) ?? "Pip"
    }
}


// MARK: - Buddy stats (home-screen widget)

/// The studio at a glance, written by the app whenever the economy moves.
/// The jar is extrapolated at render time from `rate` and `jarSince`, so the
/// widget's number climbs without a reload.
struct BuddyWidgetStats: Codable {
    static let key = "buddy.widget"

    var name: String
    var asset: String
    var notes: Double
    var rate: Double
    var jarSince: Date
    var jarHours: Double
    var health: String
    var healthMultiplier: Double
    var records: Int
    var track: Int?
    var trackCount: Int
    var toNextTrack: Double?
    var progress: Double

    func jar(at date: Date) -> Double {
        rate * min(jarHours * 3600, max(0, date.timeIntervalSince(jarSince)))
    }

    var jarFullAt: Date { jarSince.addingTimeInterval(jarHours * 3600) }

    static func load() -> BuddyWidgetStats? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BuddyWidgetStats.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults(suiteName: appGroupID)?.set(data, forKey: Self.key)
        }
    }
}
