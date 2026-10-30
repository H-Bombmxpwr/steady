import Foundation

// MARK: - Why this exists
//
// The numbers alone weren't bringing anyone back. A trend line that moves a
// tenth of a pound a day is honest, but it's not a reason to open an app on a
// Tuesday. This layer borrows what works in Focus Friend and Finch — a small
// creature whose world grows because of what *you* did, a currency for the
// behaviour, a shop to spend it in — and points it at the two things the
// weight-loss research keeps finding actually matter: self-monitoring (weighing
// in, logging food) and showing up again after a bad day.
//
// The rules that fall out of that:
//
// * **Reward the process, not the scale.** Daily notes come from logging, not
//   from the number going down. A day's weight is mostly water; paying out on
//   it would punish honest weigh-ins on salty days.
// * **Reward real loss on the trend.** The scale only pays out through the
//   smoothed trend, and only for *new lows*, so noise can't take anything back.
// * **Nothing is ever lost.** No dying pet, no shrinking balance. Missing days
//   just means the buddy is pleased to see you — the "what-the-hell effect"
//   (one slip → give up) is what kills most diets, so a slip costs nothing.
// * **The buddy isn't an AI.** Every line is written by hand and filled in from
//   your own numbers, so what it says is always true.

/// One of the daily "sound check" items — the logging behaviours that pay
/// notes. Done-ness is read straight off the day's log, never stored, so the
/// stats and the rewards can't disagree.
enum Chore: String, CaseIterable, Identifiable {
    case weighIn, firstFood, threeMeals, underBudget, protein, water, moved, photo

    var id: String { rawValue }

    var notes: Int {
        switch self {
        case .weighIn: return 10
        case .firstFood: return 10
        case .threeMeals: return 15
        case .underBudget: return 10
        case .protein: return 10
        case .water: return 5
        case .moved: return 10
        case .photo: return 5
        }
    }

    var label: String {
        switch self {
        case .weighIn: return "Weigh in"
        case .firstFood: return "Log a food"
        case .threeMeals: return "Log 3 meals"
        case .underBudget: return "Yesterday on target"
        case .protein: return "Hit protein"
        case .water: return "Hit water"
        case .moved: return "Move"
        case .photo: return "Progress photo"
        }
    }

    var icon: String {
        switch self {
        case .weighIn: return "scalemass.fill"
        case .firstFood: return "fork.knife"
        case .threeMeals: return "list.bullet"
        case .underBudget: return "checkmark.seal.fill"
        case .protein: return "bolt.fill"
        case .water: return "drop.fill"
        case .moved: return "figure.run"
        case .photo: return "camera.fill"
        }
    }

    static var dailyMax: Int { allCases.reduce(0) { $0 + $1.notes } }
}

/// Where the buddy's head is at. Picked from the data, not at random.
enum BuddyMood: Equatable {
    case sleeping, waiting, peckish, content, proud, newLow, welcomeBack
}

/// The weight journey as a record of ten tracks, each a tenth of the way from
/// where this tour started to the goal — 1.5 lb each with 15 to lose, 5 lb
/// each with 50. Small, finishable chunks: the goal-gradient effect says effort
/// picks up as the next finish line gets close, and the goal itself is never
/// close. Ten every time, so everyone unlocks the same gear on the way.
struct Tour: Equatable {
    static let trackCount = 10

    let number: Int
    let start: Double
    let goal: Double
    /// Smoothed trend weight right now.
    let current: Double
    /// Lowest the trend has been since this tour started.
    let best: Double

    var total: Double { max(0, start - goal) }
    var trackCount: Int { Self.trackCount }
    var trackPounds: Double { total / Double(Self.trackCount) }

    /// Pounds down on the trend right now (negative when up).
    var lostNow: Double { start - current }
    /// Pounds down at the trend's best — what rewards are paid against, so a
    /// rebound never takes a finished track back.
    var lostBest: Double { max(0, start - best) }

    var progress: Double { total > 0 ? min(1, max(0, lostNow / total)) : 1 }

    func trackEnd(_ index: Int) -> Double { total * Double(index) / Double(Self.trackCount) }

    var tracksDone: Int {
        guard total > 0 else { return 0 }
        return (1...trackCount).filter { lostBest + 1e-6 >= trackEnd($0) }.count
    }

    var finished: Bool { tracksDone >= trackCount }

    /// The track being worked on (1-based), or nil once the goal is reached.
    var currentTrack: Int? { finished ? nil : tracksDone + 1 }

    /// Pounds still to go, from today's trend, to finish the current track.
    var toNextTrack: Double? {
        guard let t = currentTrack else { return nil }
        return max(0, trackEnd(t) - lostNow)
    }

    /// Whole pounds off the trend at its best — each one is a record.
    var poundsBanked: Int { Int((min(total, lostBest) + 1e-6).rounded(.down)) }

    /// The trend weight that earns the next record.
    var nextRecordAt: Double { start - Double(poundsBanked + 1) }

    /// Worth offering a fresh tour: the trend has drifted above where this one
    /// started, so the bar is behind you and every track is out of reach
    /// until you climb back. Starting over from here is the "fresh start
    /// effect" — a new beginning makes people try again.
    var freshStartSuggested: Bool { current > start + 0.5 }

    /// The name on each track. Written once; long tours reuse with a suffix.
    static func trackName(_ index: Int) -> String {
        let names = ["Sound Check", "First Verse", "The Hook", "Bridge", "Key Change",
                     "Second Wind", "Deep Cut", "The B-Side", "Slow Burn", "Crescendo",
                     "Night Drive", "Long Way Home", "Feedback", "Encore Please", "Last Call"]
        let base = names[(index - 1) % names.count]
        let round = (index - 1) / names.count
        return round == 0 ? base : "\(base) (Reprise)"
    }
}

enum BuddyEngine {

    // MARK: Chores

    /// Distinct meals with something logged in them. Foods from before meals
    /// existed share one bucket.
    static func mealsLogged(_ day: DayLog) -> Int {
        let named = Set(day.foods.map(\.mealRaw).filter { !$0.isEmpty }).count
        let legacy = day.foods.contains { $0.mealRaw.isEmpty } ? 1 : 0
        let quick = day.foods.isEmpty && day.caloriesEaten > 0 ? 1 : 0
        return named + legacy + quick
    }

    static func choresDone(day: DayLog, targets: DailyTargets, now: Date = Date()) -> Set<Chore> {
        var done = Set<Chore>()
        let meals = mealsLogged(day)
        if day.weight != nil { done.insert(.weighIn) }
        if day.totalCalories > 0 || !day.foods.isEmpty { done.insert(.firstFood) }
        if meals >= 3 { done.insert(.threeMeals) }
        // Only a completed day in range earns this; a partial or very low
        // intake must never pay a calorie-outcome reward.
        if day.date < Calendar.current.startOfDay(for: now), meals >= 3,
           targets.calories > 0,
           Double(day.totalCalories) >= Double(targets.calories) * 0.9,
           Double(day.totalCalories) <= Double(targets.calories) * 1.1 {
            done.insert(.underBudget)
        }
        if targets.proteinGrams > 0, day.totalProtein >= targets.proteinGrams { done.insert(.protein) }
        if targets.waterOunces > 0, day.waterOunces >= targets.waterOunces { done.insert(.water) }
        if !day.workouts.isEmpty { done.insert(.moved) }
        if !day.photos.isEmpty { done.insert(.photo) }
        return done
    }

    static func notes(day: DayLog, targets: DailyTargets) -> Int {
        choresDone(day: day, targets: targets).reduce(0) { $0 + $1.notes }
    }

    /// Every note the logs have earned, start of plan through today. Derived,
    /// not stored: edit a past day and its notes follow, and there's no way
    /// for a reward to drift out of step with the log it's for.
    static func notesFromLogs(plan: Plan, targets: DailyTargets, today: Date = Date()) -> Int {
        let end = Calendar.current.startOfDay(for: today)
        let start = Calendar.current.startOfDay(for: plan.startDate)
        return plan.days
            .filter { $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + notes(day: $1, targets: targets) }
    }

    // MARK: Tour

    static func tour(plan: Plan, number: Int, start: Double, since: Date, goal: Double? = nil, today: Date = Date()) -> Tour {
        let trend = CalorieEngine.weightTrend(plan: plan).filter { $0.date <= today }
        let sinceDay = Calendar.current.startOfDay(for: since)
        let onTour = trend.filter { $0.date >= sinceDay }
        let current = trend.last?.trend ?? start
        let best = min(start, onTour.map(\.trend).min() ?? start)
        return Tour(number: number, start: start, goal: goal ?? plan.goalWeight,
                    current: current, best: best)
    }

    // MARK: Streak cover

    /// Days an Encore should cover: yesterday and the day before, oldest
    /// first, when they broke an otherwise-live streak. Each one used is one
    /// Encore spent.
    static func daysToCover(plan: Plan, targets: DailyTargets, encores: Int,
                            today: Date = Date()) -> [Date] {
        guard encores > 0 else { return [] }
        let cal = Calendar.current
        let today = cal.startOfDay(for: today)
        let byDate = Dictionary(plan.days.map { (cal.startOfDay(for: $0.date), $0) },
                                uniquingKeysWith: { a, _ in a })
        var covered = Set(plan.protectedDays.map { cal.startOfDay(for: $0) })
        func counts(_ d: Date) -> Bool {
            if covered.contains(d) { return true }
            guard let day = byDate[d] else { return false }
            return CalorieEngine.dayCounts(day: day, plan: plan, targets: targets)
        }

        var out: [Date] = []
        var left = encores
        for back in [2, 1] {
            guard left > 0, let d = cal.date(byAdding: .day, value: -back, to: today),
                  let prev = cal.date(byAdding: .day, value: -1, to: d),
                  d >= cal.startOfDay(for: plan.startDate) else { continue }
            if !counts(d) && counts(prev) {
                covered.insert(d)
                out.append(d)
                left -= 1
            }
        }
        return out
    }

    // MARK: Mood

    /// Days since anything was last logged before today (0 = logged
    /// yesterday or today; nil = nothing logged yet at all).
    static func daysAway(plan: Plan, today: Date = Date()) -> Int? {
        let today = Calendar.current.startOfDay(for: today)
        guard let last = plan.days
            .filter({ $0.date < today && $0.hasActivity })
            .map(\.date).max() else { return nil }
        return max(0, last.days(to: today) - 1)
    }

    static func mood(done: Set<Chore>, hour: Int, newLowToday: Bool,
                     daysAway: Int?, loggedToday: Bool) -> BuddyMood {
        if newLowToday { return .newLow }
        if let away = daysAway, away >= 2, !loggedToday { return .welcomeBack }
        if hour >= 23 || hour < 5 { return .sleeping }
        if done.count >= 5 { return .proud }
        if !done.contains(.weighIn), hour < 12 { return .waiting }
        if !done.contains(.firstFood), hour >= 11 { return .peckish }
        return .content
    }

    // MARK: Lines
    //
    // Hand-written. The buddy is a small, earnest music nerd who runs a
    // one-room studio and treats your logging like gigs. It is never
    // disappointed in you and never says "you got this".

    struct LineContext {
        var name: String
        var mood: BuddyMood
        var done: Set<Chore>
        var tour: Tour
        var records: Int
        var daysAway: Int?
        var nowPlaying: String?
        /// Change in the trend over the last week, if there's a week of it.
        var weekDelta: Double?
        var health: BuddyHealth = .okay
    }

    static func line(_ c: LineContext, seed: Int) -> String {
        let lb = { (x: Double) in x.formatted(.number.precision(.fractionLength(1))) }
        var pool: [String]
        switch c.mood {
        case .newLow:
            pool = [
                "New low on the trend. That's a record dig — go pick something good.",
                "\(lb(c.tour.lostBest)) lb down on the trend. I'm putting that on the wall.",
                "The trend just hit a number it's never seen before. Crate's open."
            ]
        case .welcomeBack:
            let away = c.daysAway ?? 2
            pool = [
                "Oh — you're back. I kept the needle warm. Today counts the same as any day.",
                "\(away) days off the road. Happens on every tour. Weigh in and we're playing again.",
                "No catching up needed. Just today. That's the whole setlist."
            ]
        case .sleeping:
            pool = [
                "(asleep on the speaker)",
                "Studio's closed. Whatever today was, it's logged or it isn't. Sleep.",
                "Five more minutes. Then sound check."
            ]
        case .waiting:
            pool = [
                "Morning. Scale first, then coffee. That's the rule I just made up.",
                "A weigh-in adds to the sound check. The trend handles the ups and downs.",
                "One number before breakfast and the trend gets smarter."
            ]
        case .peckish:
            pool = [
                "Nothing logged yet. Not judging, just looking at an empty plate.",
                "Whatever you ate, log it. Bad days still count as data.",
                "Log the day you actually had. The math works either way."
            ]
        case .proud:
            pool = [
                "\(c.done.count) of \(Chore.allCases.count) on the sound check. That's a tight set.",
                "Today sounds good from here. I'm not even going to touch the mix.",
                "Days like this are boring on paper. That's why they work."
            ]
        case .content:
            if let delta = c.weekDelta, delta > 0.3 {
                pool = [
                    "Trend's up \(lb(delta)) this week. Scales hold water, not opinions. Keep logging.",
                    "Up a bit this week. The tracks you've finished stay finished."
                ]
            } else if let toNext = c.tour.toNextTrack, let t = c.tour.currentTrack, toNext < 2 {
                pool = [
                    "\(lb(toNext)) lb to finish “\(Tour.trackName(t))”. We're in the last chorus.",
                    "Track \(t) is almost done. \(lb(toNext)) lb on the trend."
                ]
            } else {
                pool = [
                    c.tour.nextRecordAt >= c.tour.goal
                        ? "Next weight record when the trend hits \(lb(c.tour.nextRecordAt))."
                        : "The weight goal is covered. Sound-check days keep the records coming.",
                    c.records == 0
                        ? "The crate's empty. Your first pound or seven sound-check days earns a record."
                        : "\(c.records) record\(c.records == 1 ? "" : "s") in the crate. Weight milestones, sound checks, and good finds.",
                    "Steady beats loud. Log the next thing you eat."
                ]
            }
        }
        if c.health == .thriving, c.mood == .content || c.mood == .proud {
            pool.append("Protein and fiber logged. A little extra energy for the studio.")
        }
        if let song = c.nowPlaying, c.mood != .sleeping {
            pool.append("Still spinning \(song). Good pick.")
        }
        return pool[abs(seed) % pool.count]
    }
}
