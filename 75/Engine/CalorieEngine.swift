import Foundation

/// Daily targets derived from the user's profile and plan.
struct DailyTargets {
    let calories: Int
    let proteinGrams: Int
    let waterOunces: Int
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

    /// Fraction of daily goals met — drives calendar/day completion UI.
    /// Scored: calories logged & within budget, protein, water, a workout, a photo.
    static func completionFraction(day: DayLog, targets: DailyTargets) -> Double {
        let checks: [Bool] = [
            day.caloriesEaten > 0 && day.caloriesEaten <= targets.calories,
            day.proteinGrams >= targets.proteinGrams,
            day.waterOunces >= targets.waterOunces,
            !day.workouts.isEmpty,
            !day.photos.isEmpty
        ]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }
}
