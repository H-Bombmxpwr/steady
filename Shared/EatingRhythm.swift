import Foundation

/// *When* the eating happens, not just how much of it there was.
///
/// Every other statistic in the app collapses a day to totals, which throws
/// away the thing the day plan is built around: a day is a sequence. Two people
/// eating 2,400 calories — one across three sittings finishing at seven, one
/// mostly after nine at night — have the same charts everywhere else in Stats
/// and completely different days. Now that a logged food knows when it was
/// *eaten* rather than when it was typed in, that sequence is finally
/// measurable, and this is the arithmetic behind it.
///
/// Everything here reads `FoodLog.occurredAt`, so a meal logged two hours late
/// and then corrected counts at the time it happened.
enum EatingRhythm {

    /// How one meal slot actually behaves, across a range of days.
    struct MealTiming: Identifiable {
        let meal: Meal
        /// Mean clock time it's eaten, as minutes past midnight.
        let averageMinutesOfDay: Int
        /// How much it moves around: the mean distance from its own average.
        /// A breakfast at 6:30 every day and one that wanders between 6 and 11
        /// are different habits with the same average.
        let swingMinutes: Int
        let averageCalories: Int
        let averageProtein: Int
        /// Days in range where this meal had anything logged against it.
        let daysLogged: Int

        var id: String { meal.rawValue }

        var timeString: String {
            let comps = DateComponents(hour: averageMinutesOfDay / 60,
                                       minute: averageMinutesOfDay % 60)
            let date = Calendar.current.date(from: comps) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }

        /// "±25 min" — only worth saying when it's actually loose.
        var swingString: String? {
            guard swingMinutes >= 20 else { return nil }
            return "±\(swingMinutes) min"
        }
    }

    /// One slice of the clock, with the macros that landed in it. Calories are
    /// split by macro so the bar says what kind of food it was, not just how
    /// much — the late-night bucket being all fat and sugar is the finding.
    struct Bucket: Identifiable {
        let startMinutes: Int
        let widthMinutes: Int
        let carbCalories: Double
        let proteinCalories: Double
        let fatCalories: Double
        /// What was logged, for the buckets where the macro panel was blank.
        let loggedCalories: Double

        var id: Int { startMinutes }

        /// The macro calories add up to less than the logged total whenever a
        /// food was logged without its panel (a bare quick-add). The remainder
        /// is still energy and still has to appear somewhere.
        var unattributedCalories: Double {
            max(0, loggedCalories - (carbCalories + proteinCalories + fatCalories))
        }

        var totalCalories: Double {
            carbCalories + proteinCalories + fatCalories + unattributedCalories
        }

        var label: String {
            let comps = DateComponents(hour: startMinutes / 60, minute: startMinutes % 60)
            let date = Calendar.current.date(from: comps) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }
    }

    /// The day's shape: when the first and last food typically land, and how
    /// long the window between them runs. Averaged over days that logged at
    /// least one food.
    struct Window {
        let averageFirstMinutes: Int
        let averageLastMinutes: Int
        let daysCounted: Int

        var hours: Double { Double(max(0, averageLastMinutes - averageFirstMinutes)) / 60 }

        var firstString: String { Self.clock(averageFirstMinutes) }
        var lastString: String { Self.clock(averageLastMinutes) }

        private static func clock(_ minutes: Int) -> String {
            let comps = DateComponents(hour: minutes / 60, minute: minutes % 60)
            let date = Calendar.current.date(from: comps) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }
    }

    // MARK: - Per-meal timing

    /// One row per meal that actually got eaten in the range, in clock order.
    static func timings(days: [DayLog]) -> [MealTiming] {
        Meal.allCases.compactMap { meal -> MealTiming? in
            // A meal's numbers come from the days it happened on. Averaging in
            // the days it didn't would report a breakfast of 90 calories for
            // someone who eats a proper one four days a week.
            var minutes: [Int] = []
            var calories: [Int] = []
            var protein: [Int] = []
            for day in days {
                let foods = day.foods(for: meal)
                guard let first = foods.first else { continue }
                minutes.append(first.minutesOfDay)
                calories.append(foods.reduce(0) { $0 + $1.calories })
                protein.append(foods.reduce(0) { $0 + $1.proteinGrams })
            }
            guard !minutes.isEmpty else { return nil }
            let mean = Double(minutes.reduce(0, +)) / Double(minutes.count)
            let swing = minutes.reduce(0.0) { $0 + abs(Double($1) - mean) } / Double(minutes.count)
            return MealTiming(meal: meal,
                              averageMinutesOfDay: Int(mean.rounded()),
                              swingMinutes: Int(swing.rounded()),
                              averageCalories: calories.reduce(0, +) / calories.count,
                              averageProtein: protein.reduce(0, +) / protein.count,
                              daysLogged: minutes.count)
        }
        .sorted { $0.averageMinutesOfDay < $1.averageMinutesOfDay }
    }

    // MARK: - Energy across the clock

    /// Calories by time of day, split by macro, averaged per logging day so a
    /// week and a quarter are read the same way.
    ///
    /// Buckets with nothing in them are kept: the gaps are the point — a flat
    /// stretch from two until seven is a five-hour hole, and dropping it would
    /// draw the day as if the food were continuous.
    static func byTimeOfDay(days: [DayLog], bucketHours: Int = 2) -> [Bucket] {
        let width = max(1, min(6, bucketHours)) * 60
        let bucketCount = (24 * 60) / width
        let loggingDays = days.filter { !$0.foods.isEmpty }.count
        guard loggingDays > 0 else { return [] }

        var carbs = [Double](repeating: 0, count: bucketCount)
        var protein = [Double](repeating: 0, count: bucketCount)
        var fat = [Double](repeating: 0, count: bucketCount)
        var logged = [Double](repeating: 0, count: bucketCount)

        for day in days {
            for food in day.foods {
                let index = min(bucketCount - 1, max(0, food.minutesOfDay / width))
                carbs[index] += food.facts.carbsGrams * 4
                protein[index] += Double(food.proteinGrams) * 4
                fat[index] += food.facts.fatGrams * 9
                logged[index] += Double(food.calories)
            }
        }

        let perDay = Double(loggingDays)
        return (0..<bucketCount).map { i in
            Bucket(startMinutes: i * width,
                   widthMinutes: width,
                   carbCalories: carbs[i] / perDay,
                   proteinCalories: protein[i] / perDay,
                   fatCalories: fat[i] / perDay,
                   loggedCalories: logged[i] / perDay)
        }
    }

    // MARK: - The window

    static func window(days: [DayLog]) -> Window? {
        var firsts: [Int] = []
        var lasts: [Int] = []
        for day in days {
            let times = day.foods.map(\.minutesOfDay).sorted()
            guard let first = times.first, let last = times.last else { continue }
            firsts.append(first)
            lasts.append(last)
        }
        guard !firsts.isEmpty else { return nil }
        return Window(averageFirstMinutes: firsts.reduce(0, +) / firsts.count,
                      averageLastMinutes: lasts.reduce(0, +) / lasts.count,
                      daysCounted: firsts.count)
    }

    /// Share of the day's calories eaten after a given hour — the "how much of
    /// my day lands at night" number, which is the one people actually want
    /// from a timing chart.
    static func shareAfter(hour: Int, days: [DayLog]) -> Double? {
        let cutoff = hour * 60
        var late = 0.0
        var all = 0.0
        for day in days {
            for food in day.foods {
                all += Double(food.calories)
                if food.minutesOfDay >= cutoff { late += Double(food.calories) }
            }
        }
        guard all > 0 else { return nil }
        return late / all
    }
}
