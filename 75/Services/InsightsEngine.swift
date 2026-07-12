import Foundation
import SwiftUI

/// Mines the last 90 days for cause-and-effect patterns in the user's own
/// data — all computed locally, shown only when both sides of a comparison
/// have enough days to mean something.
enum InsightsEngine {

    struct Pattern: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let detail: String
    }

    /// Minimum days on EACH side of a split before a pattern is trusted.
    private static let minSample = 4

    static func patterns(plan: Plan, sleep: [Date: Double]) -> [Pattern] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let cutoff = cal.date(byAdding: .day, value: -90, to: today) else { return [] }
        let days = plan.days
            .filter { $0.date >= cutoff && $0.date < today }
            .sorted { $0.date < $1.date }
        guard !days.isEmpty else { return [] }

        let weightByDate = Dictionary(uniqueKeysWithValues:
            days.compactMap { d in d.weight.map { (d.date, $0) } })

        /// Morning-after scale move for a day: weight(next) - weight(same).
        func nextDayDelta(_ d: DayLog) -> Double? {
            guard let next = cal.date(byAdding: .day, value: 1, to: d.date),
                  let w0 = weightByDate[d.date], let w1 = weightByDate[next] else { return nil }
            return w1 - w0
        }

        var out: [Pattern] = []

        // 1. Alcohol → next-morning weight
        let drinkDeltas = days.filter { $0.standardDrinks > 0 }.compactMap(nextDayDelta)
        let dryDeltas = days.filter { $0.standardDrinks == 0 && $0.hasActivity }.compactMap(nextDayDelta)
        if drinkDeltas.count >= minSample, dryDeltas.count >= minSample {
            let diff = avg(drinkDeltas) - avg(dryDeltas)
            if diff >= 0.25 {
                out.append(Pattern(
                    id: "alcohol-weight", icon: "wineglass.fill", tint: Theme.alcoholTint,
                    title: "Drinks show up on the scale",
                    detail: String(format: "Mornings after alcohol run %+.1f lb vs %+.1f lb after dry days (%d nights compared). Some is water weight — but it stalls the trend.",
                                   avg(drinkDeltas), avg(dryDeltas), drinkDeltas.count)))
            }
        }

        // 2. Short sleep → same-day calories
        let eaten = days.filter { $0.totalCalories > 0 }
        let shortSleep = eaten.filter { (sleep[$0.date] ?? 0) > 0 && sleep[$0.date]! < 6.5 }
        let restedSleep = eaten.filter { (sleep[$0.date] ?? 0) >= 7 }
        if shortSleep.count >= minSample, restedSleep.count >= minSample {
            let diff = avg(shortSleep.map { Double($0.totalCalories) })
                     - avg(restedSleep.map { Double($0.totalCalories) })
            if diff >= 100 {
                out.append(Pattern(
                    id: "sleep-calories", icon: "moon.zzz.fill", tint: Theme.sleepTint,
                    title: "Short sleep, bigger appetite",
                    detail: "You eat about \(Int(diff.rounded())) more calories on days after less than 6½ hours of sleep (\(shortSleep.count) short nights vs \(restedSleep.count) rested). Protecting sleep protects the budget."))
            }
        }

        // 3. Salty days → next-morning weight
        let salty = days.filter { $0.totalFacts.sodiumMg > 2300 }.compactMap(nextDayDelta)
        let mild = days.filter { $0.totalFacts.sodiumMg > 0 && $0.totalFacts.sodiumMg <= 2300 }
            .compactMap(nextDayDelta)
        if salty.count >= minSample, mild.count >= minSample {
            let diff = avg(salty) - avg(mild)
            if diff >= 0.25 {
                out.append(Pattern(
                    id: "sodium-weight", icon: "drop.triangle.fill", tint: Theme.weightTint,
                    title: "Salty days spike the scale",
                    detail: String(format: "The morning after 2,300+ mg sodium the scale moves %+.1f lb vs %+.1f lb after lighter days. It's water, not fat — don't let it rattle you.",
                                   avg(salty), avg(mild))))
            }
        }

        // 4. Workout days vs rest days → intake
        let workoutDays = eaten.filter { !$0.workouts.isEmpty }
        let restDays = eaten.filter { $0.workouts.isEmpty }
        if workoutDays.count >= minSample, restDays.count >= minSample {
            let diff = avg(workoutDays.map { Double($0.totalCalories) })
                     - avg(restDays.map { Double($0.totalCalories) })
            if diff >= 150 {
                out.append(Pattern(
                    id: "workout-calories", icon: "figure.run", tint: Theme.workoutTint,
                    title: "Training days eat bigger",
                    detail: "You average \(Int(diff.rounded())) more calories on workout days. Fine if it's fueling sessions — just know the 'I earned it' meals can outrun the burn."))
            } else if diff <= -150 {
                out.append(Pattern(
                    id: "workout-calories", icon: "figure.run", tint: Theme.workoutTint,
                    title: "Workouts keep the kitchen honest",
                    detail: "On workout days you eat about \(Int(-diff.rounded())) fewer calories — training days are your best eating days too."))
            }
        }

        // 5. Weekends vs weekdays → intake
        let weekend = eaten.filter { cal.isDateInWeekend($0.date) }
        let weekday = eaten.filter { !cal.isDateInWeekend($0.date) }
        if weekend.count >= minSample, weekday.count >= minSample {
            let diff = avg(weekend.map { Double($0.totalCalories) })
                     - avg(weekday.map { Double($0.totalCalories) })
            if diff >= 150 {
                out.append(Pattern(
                    id: "weekend-calories", icon: "calendar.badge.exclamationmark", tint: Theme.foodTint,
                    title: "Weekends run hot",
                    detail: "Saturdays and Sundays average \(Int(diff.rounded())) calories over your weekdays — roughly \(Int((diff * 2 / 7).rounded())) a day spread across the week. Worth planning weekend meals first."))
            }
        }

        return out
    }

    private static func avg(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
