import Foundation

/// Daily targets derived from the user's profile and plan.
///
/// Carbs and fat are only filled in by athlete mode, which periodizes macros
/// against the day's training load; weight-loss mode leaves them nil and keeps
/// the original calories/protein/water contract untouched.
struct DailyTargets {
    let calories: Int
    let proteinGrams: Int
    let waterOunces: Int
    var carbGrams: Int? = nil
    var fatGrams: Int? = nil
    var trainingLoad: TrainingLoad? = nil
}

/// A smoothed weight sample.
struct TrendPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let raw: Double?
    let trend: Double
}

/// Habit stats for the dashboard.
struct StreakStats {
    let current: Int          // consecutive "goals met" days ending today/yesterday
    let consistency: Double   // fraction of days since start that met goals
    let daysTracked: Int
}

/// Rolling 7-day summary for the weekly insight card.
struct WeeklyInsight {
    let avgCalories: Int
    let calorieBudget: Int
    let daysMet: Int
    let daysApplicable: Int
    let trendDelta7d: Double? // smoothed weight change over last 7 days
    let suggestion: String
}

/// What the adaptive engine learned from recent logs — shown in Settings so
/// the budget never changes silently.
struct AdaptiveTDEE {
    let observed: Double      // TDEE implied by intake vs weight change
    let formula: Double       // Mifflin-St Jeor × activity, for comparison
    let blended: Double       // what the budget actually uses
    let loggedDays: Int       // food-logged days that fed the estimate
    let spanDays: Int         // days between first and last weigh-in used
}

/// Energy-balance math: Mifflin-St Jeor BMR, activity-scaled TDEE, and a
/// deficit-based daily calorie budget with safety floors.
enum CalorieEngine {

    static func bmr(sex: BiologicalSex, weightLbs: Double, heightInches: Double, ageYears: Int) -> Double {
        let kg = weightLbs * 0.45359237
        let cm = heightInches * 2.54
        let base = 10.0 * kg + 6.25 * cm - 5.0 * Double(ageYears)
        switch sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78   // midpoint of the male/female constants
        }
    }

    static func tdee(sex: BiologicalSex, weightLbs: Double, heightInches: Double,
                     ageYears: Int, activity: ActivityLevel) -> Double {
        bmr(sex: sex, weightLbs: weightLbs, heightInches: heightInches, ageYears: ageYears) * activity.factor
    }

    /// 1 lb of fat ≈ 3500 kcal, so pace (lb/week) sets the daily deficit.
    /// Floors: 1500 kcal (male) / 1200 kcal (female) — below these, budgets
    /// are widely considered unsafe without medical supervision.
    static func dailyBudget(tdee: Double, paceLbsPerWeek: Double, sex: BiologicalSex) -> Int {
        let deficit = paceLbsPerWeek * 3500.0 / 7.0
        let floor: Double
        switch sex {
        case .male: floor = 1500
        case .female: floor = 1200
        case .unspecified: floor = 1350
        }
        return Int(max(floor, tdee - deficit).rounded())
    }

    /// 0.8 g protein per lb of goal body weight (muscle retention in a deficit).
    static func proteinTargetGrams(goalWeightLbs: Double) -> Int {
        Int((goalWeightLbs * 0.8).rounded())
    }

    // MARK: - Adaptive TDEE

    /// Learn the real burn rate from the user's own data: over the last 28
    /// full days, average logged intake minus the calories the weight trend
    /// says were stored/lost (3500 kcal/lb) is the TDEE that actually
    /// happened. Needs 14+ food-logged days and weigh-ins spanning 14+ days,
    /// otherwise returns nil and the formula stands alone.
    static func adaptiveTDEE(profile: UserProfile, plan: Plan) -> AdaptiveTDEE? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let windowStart = cal.date(byAdding: .day, value: -28, to: today) else { return nil }

        // Today is partial — a half-logged day would drag the average down.
        let logged = plan.days.filter {
            $0.date >= windowStart && $0.date < today && $0.totalCalories > 0
        }
        guard logged.count >= 14 else { return nil }

        let trendInWindow = weightTrend(plan: plan).filter { $0.date >= windowStart && $0.date <= today }
        guard let first = trendInWindow.first, let last = trendInWindow.last else { return nil }
        let spanDays = first.date.days(to: last.date)
        guard spanDays >= 14 else { return nil }

        let avgIntake = Double(logged.reduce(0) { $0 + $1.totalCalories }) / Double(logged.count)
        let lbsPerDay = (last.trend - first.trend) / Double(spanDays)
        let formula = tdee(sex: profile.sex,
                           weightLbs: plan.currentWeight,
                           heightInches: profile.heightInches,
                           ageYears: profile.ageYears,
                           activity: profile.activityLevel)
        // Clamp: unlogged snacks or a scale jump can imply absurd burn rates.
        let observed = min(max(avgIntake - lbsPerDay * 3500.0, formula * 0.6), formula * 1.5)

        // The formula keeps at least a 20% anchor; trust in the observed
        // number grows with how much of the window was actually logged.
        let weight = min(0.8, Double(logged.count) / 28.0)
        let blended = formula * (1 - weight) + observed * weight
        return AdaptiveTDEE(observed: observed, formula: formula, blended: blended,
                            loggedDays: logged.count, spanDays: spanDays)
    }

    // MARK: - Maintenance

    /// Average calories the last 28 days of *logged* training actually cost,
    /// per day. Used to strip training out of a learned TDEE so athlete mode
    /// can add each day's own session back without counting it twice.
    static func averageLoggedTrainingBurn(plan: Plan, days: Int = 28) -> Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let start = cal.date(byAdding: .day, value: -days, to: today) else { return 0 }
        let window = plan.days.filter { $0.date >= start && $0.date < today }
        guard !window.isEmpty else { return 0 }

        let total = window.reduce(0.0) { sum, day in
            sum + day.workouts.reduce(0.0) { inner, workout in
                inner + Double(FuelingEngine.plan(category: workout.category,
                                                  intensity: .moderate,
                                                  minutes: workout.minutes,
                                                  bodyweightLbs: plan.currentWeight).burnCalories)
            }
        }
        return total / Double(days)
    }

    /// What the body costs *before* today's session — everything except the
    /// planned training, which athlete mode adds back per day.
    ///
    /// This is the piece that stops the double count. `ActivityLevel.factor`
    /// already bakes in "exercise 3–5 days a week", and a learned TDEE
    /// contains whatever training actually happened. Adding a session burn on
    /// top of either would feed an athlete their hardest day twice.
    static func maintenanceTDEE(profile: UserProfile, plan: Plan) -> Double {
        if plan.adaptiveBudget, let adaptive = adaptiveTDEE(profile: profile, plan: plan) {
            // The learned number is total burn including training. Subtract
            // the training it saw to get the everything-else baseline.
            let baseline = adaptive.blended - averageLoggedTrainingBurn(plan: plan)
            // Never let the subtraction fall below resting metabolism.
            let floor = bmr(sex: profile.sex, weightLbs: plan.currentWeight,
                            heightInches: profile.heightInches, ageYears: profile.ageYears)
            return max(floor * 1.15, baseline)
        }
        // Formula path: use the non-exercise multiplier, since the sessions
        // are counted individually.
        return bmr(sex: profile.sex, weightLbs: plan.currentWeight,
                   heightInches: profile.heightInches, ageYears: profile.ageYears)
            * profile.activityLevel.nonExerciseFactor
    }

    /// Today's targets. TDEE tracks the current (latest logged) weight so the
    /// budget adjusts as weight comes down; when adaptive budgeting is on and
    /// there's enough history, the learned TDEE replaces the formula. A
    /// manual override wins over both.
    static func targets(profile: UserProfile, plan: Plan) -> DailyTargets {
        // Athlete mode's whole target set is a function of the day's training,
        // so "today" is the only sensible answer to an undated question.
        if profile.mode == .athlete {
            return targets(profile: profile, plan: plan,
                           on: Calendar.current.startOfDay(for: Date()))
        }

        var t = tdee(sex: profile.sex,
                     weightLbs: plan.currentWeight,
                     heightInches: profile.heightInches,
                     ageYears: profile.ageYears,
                     activity: profile.activityLevel)
        if plan.adaptiveBudget, let adaptive = adaptiveTDEE(profile: profile, plan: plan) {
            t = adaptive.blended
        }
        let calories = plan.calorieBudgetOverride
            ?? dailyBudget(tdee: t, paceLbsPerWeek: plan.paceLbsPerWeek, sex: profile.sex)
        return DailyTargets(calories: calories,
                            proteinGrams: plan.proteinTargetGrams,
                            waterOunces: plan.waterGoalOunces)
    }

    // MARK: - Daily goal scoring

    /// The pass/fail checks that apply to a given day. A workout only counts
    /// against you on days you scheduled one (or any day if no schedule set).
    static func checks(day: DayLog, targets: DailyTargets, workoutScheduled: Bool) -> [Bool] {
        var result: [Bool] = [
            day.totalCalories > 0 && day.totalCalories <= targets.calories,
            day.totalProtein >= targets.proteinGrams,
            day.waterOunces >= targets.waterOunces,
            !day.photos.isEmpty
        ]
        if workoutScheduled {
            result.append(!day.workouts.isEmpty)
        }
        return result
    }

    static func completionFraction(day: DayLog, targets: DailyTargets, workoutScheduled: Bool) -> Double {
        let c = checks(day: day, targets: targets, workoutScheduled: workoutScheduled)
        return Double(c.filter { $0 }.count) / Double(max(1, c.count))
    }

    /// ≥ 75% of the day's applicable goals met — the "on target" measure.
    static func dayMet(day: DayLog, targets: DailyTargets, workoutScheduled: Bool) -> Bool {
        completionFraction(day: day, targets: targets, workoutScheduled: workoutScheduled) >= 0.75
    }

    /// Whether a day keeps the streak alive, honoring the plan's streak
    /// style: strict = goals met; relaxed (default) = anything logged.
    static func dayCounts(day: DayLog, plan: Plan, targets: DailyTargets) -> Bool {
        plan.strictStreak
            ? dayMet(day: day, targets: targets,
                     workoutScheduled: plan.isWorkoutScheduled(on: day.date))
            : day.hasActivity
    }

    // MARK: - Weight trend (exponentially weighted moving average)

    /// Smoothing factor 0.25: responsive enough for sparse logging while still
    /// damping daily water-weight noise.
    static func weightTrend(plan: Plan) -> [TrendPoint] {
        let weighed = plan.days
            .compactMap { d -> (Date, Double)? in d.weight.map { (d.date, $0) } }
            .sorted { $0.0 < $1.0 }
        guard !weighed.isEmpty else { return [] }

        var trend = weighed[0].1
        var points: [TrendPoint] = []
        for (date, raw) in weighed {
            trend += 0.25 * (raw - trend)
            points.append(TrendPoint(date: date, raw: raw, trend: trend))
        }
        return points
    }

    /// Latest smoothed weight (the headline number).
    static func trendWeight(plan: Plan) -> Double {
        weightTrend(plan: plan).last?.trend ?? plan.startingWeight
    }

    // MARK: - Streaks

    static func streakStats(plan: Plan, targets: DailyTargets) -> StreakStats {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let byDate = Dictionary(uniqueKeysWithValues: plan.days.map { (cal.startOfDay(for: $0.date), $0) })

        func met(_ date: Date) -> Bool {
            guard let day = byDate[date] else { return false }
            return dayCounts(day: day, plan: plan, targets: targets)
        }

        // Current streak: walk back from today; today only breaks the streak
        // once it's over (i.e., an unmet *past* day ends the walk).
        var streak = 0
        var cursor = today
        if met(cursor) { streak += 1 }
        while true {
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            if prev < plan.startDate { break }
            if met(prev) { streak += 1; cursor = prev } else { break }
        }

        // Consistency: met days / elapsed days (excluding today unless met)
        let elapsed = max(1, plan.startDate.days(to: today) + 1)
        var metCount = 0
        var d = plan.startDate
        while d <= today {
            if met(d) { metCount += 1 }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? today.addingTimeInterval(1)
        }
        return StreakStats(current: streak,
                           consistency: Double(metCount) / Double(elapsed),
                           daysTracked: plan.days.count)
    }

    // MARK: - Weekly insight

    static func weeklyInsight(plan: Plan, targets: DailyTargets) -> WeeklyInsight {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today)!
        let window = plan.days.filter { $0.date >= weekAgo && $0.date <= today }

        let loggedDays = window.filter { $0.totalCalories > 0 }
        let avgCal = loggedDays.isEmpty ? 0 : loggedDays.reduce(0) { $0 + $1.totalCalories } / loggedDays.count
        let daysMet = window.filter {
            dayMet(day: $0, targets: targets, workoutScheduled: plan.isWorkoutScheduled(on: $0.date))
        }.count

        let trend = weightTrend(plan: plan)
        var delta: Double? = nil
        if let last = trend.last, let weekAgoPoint = trend.last(where: { $0.date <= weekAgo }) {
            delta = last.trend - weekAgoPoint.trend
        }

        let suggestion: String
        if loggedDays.count < 4 {
            suggestion = "Log food more consistently — the budget only works when it sees what you eat."
        } else if avgCal > targets.calories {
            suggestion = "You averaged \(avgCal - targets.calories) cal over budget. Try front-loading protein to stay full."
        } else if let d = delta, d > 0 {
            suggestion = "Trend ticked up despite logging — water weight is normal; hold the plan for another week."
        } else {
            suggestion = "On track. Keep the streak alive this week."
        }

        return WeeklyInsight(avgCalories: avgCal,
                             calorieBudget: targets.calories,
                             daysMet: daysMet,
                             daysApplicable: min(7, plan.startDate.days(to: today) + 1),
                             trendDelta7d: delta,
                             suggestion: suggestion)
    }

    // MARK: - Training-day fueling

    /// Fueling plans for every session planned on `date`, sized to the user's
    /// current weight and sharpened by their sweat tests, the weather, and
    /// (when tracked) the cycle phase.
    ///
    /// Reads `plan.sessions(on:)`, so an imported TrainingPeaks plan overrides
    /// the standing weekly schedule rather than double-counting with it.
    static func fuelingPlans(plan: Plan,
                             on date: Date,
                             weather: WeatherContext? = nil,
                             cyclePhase: CyclePhase? = nil) -> [FuelingPlan] {
        let sweat = plan.sweatProfile()
        return plan.sessions(on: date).map {
            FuelingEngine.plan(for: $0,
                               bodyweightLbs: plan.currentWeight,
                               sweat: sweat,
                               weather: plan.weatherAwareFueling ? weather : nil,
                               cyclePhase: cyclePhase)
        }
    }

    /// Estimated calories the day's planned training burns — the amount to
    /// add back to the budget on a training day.
    static func trainingBurn(plan: Plan, on date: Date) -> Int {
        fuelingPlans(plan: plan, on: date).reduce(0) { $0 + $1.burnCalories }
    }

    /// Extra water the day's planned training calls for, from each session's
    /// fluid guidance (oz/hr × duration).
    static func trainingFluidOunces(plan: Plan, on date: Date) -> Int {
        fuelingPlans(plan: plan, on: date).reduce(0) { $0 + $1.totalFluidOz }
    }

    /// Targets for a specific day.
    ///
    /// In weight-loss mode this is the base budget plus the day's training
    /// burn, so eating the fuel doesn't read as going "over". In athlete mode
    /// the whole calculation is different — maintenance plus training, with
    /// carbs periodized to the load — and `AthleteEngine` owns it.
    static func targets(profile: UserProfile,
                        plan: Plan,
                        on date: Date,
                        weather: WeatherContext? = nil,
                        cyclePhase: CyclePhase? = nil) -> DailyTargets {
        if profile.mode == .athlete {
            let a = AthleteEngine.targets(profile: profile,
                                          plan: plan,
                                          maintenanceTDEE: maintenanceTDEE(profile: profile, plan: plan),
                                          sessions: plan.sessions(on: date),
                                          weather: weather,
                                          cyclePhase: cyclePhase)
            // A manual override still wins — but only over the calorie total;
            // the macro split stays keyed to the day's training load.
            return DailyTargets(calories: plan.calorieBudgetOverride ?? a.calories,
                                proteinGrams: a.proteinGrams,
                                waterOunces: a.waterOunces,
                                carbGrams: a.carbGrams,
                                fatGrams: a.fatGrams,
                                trainingLoad: a.load)
        }

        let base = targets(profile: profile, plan: plan)
        guard plan.fuelTrainingDays else { return base }
        let plans = fuelingPlans(plan: plan, on: date, weather: weather, cyclePhase: cyclePhase)
        let bump = plans.reduce(0) { $0 + $1.burnCalories }
        guard bump > 0 else { return base }
        return DailyTargets(calories: base.calories + bump,
                            proteinGrams: base.proteinGrams,
                            waterOunces: base.waterOunces
                                + plans.reduce(0) { $0 + $1.totalFluidOz })
    }

    /// Athlete-mode day targets with the full picture attached.
    static func athleteTargets(profile: UserProfile,
                               plan: Plan,
                               on date: Date,
                               weather: WeatherContext? = nil,
                               cyclePhase: CyclePhase? = nil) -> AthleteTargets {
        AthleteEngine.targets(profile: profile,
                              plan: plan,
                              maintenanceTDEE: maintenanceTDEE(profile: profile, plan: plan),
                              sessions: plan.sessions(on: date),
                              weather: weather,
                              cyclePhase: cyclePhase)
    }
}
