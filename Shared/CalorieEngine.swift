import Foundation

/// Daily targets derived from the user's profile and plan.
struct DailyTargets {
    let calories: Int
    let proteinGrams: Int
    let waterOunces: Int
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

/// Energy-balance math: Mifflin-St Jeor BMR, activity-scaled TDEE, and a
/// deficit-based daily calorie budget with safety floors.
enum CalorieEngine {

    static func bmr(sex: BiologicalSex, weightLbs: Double, heightInches: Double, ageYears: Int) -> Double {
        let kg = weightLbs * 0.45359237
        let cm = heightInches * 2.54
        let base = 10.0 * kg + 6.25 * cm - 5.0 * Double(ageYears)
        return sex == .male ? base + 5 : base - 161
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
        let floor = sex == .male ? 1500.0 : 1200.0
        return Int(max(floor, tdee - deficit).rounded())
    }

    /// 0.8 g protein per lb of goal body weight (muscle retention in a deficit).
    static func proteinTargetGrams(goalWeightLbs: Double) -> Int {
        Int((goalWeightLbs * 0.8).rounded())
    }

    /// Today's targets. TDEE tracks the current (latest logged) weight so the
    /// budget adjusts as weight comes down; a manual override wins if set.
    static func targets(profile: UserProfile, plan: Plan) -> DailyTargets {
        let t = tdee(sex: profile.sex,
                     weightLbs: plan.currentWeight,
                     heightInches: profile.heightInches,
                     ageYears: profile.ageYears,
                     activity: profile.activityLevel)
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

    /// A day "counts" for the streak when ≥ 75% of its applicable goals are met.
    static func dayMet(day: DayLog, targets: DailyTargets, workoutScheduled: Bool) -> Bool {
        completionFraction(day: day, targets: targets, workoutScheduled: workoutScheduled) >= 0.75
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
            return dayMet(day: day, targets: targets, workoutScheduled: plan.isWorkoutScheduled(on: date))
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
}
