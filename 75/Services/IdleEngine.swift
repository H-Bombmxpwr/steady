import Foundation

// MARK: - The idle layer
//
// The studio earns on its own, Cookie Clicker style: you buy promo
// "generators" (busking, open mics, radio play…) that each pay notes per
// second, and every copy of one costs 15% more than the last, so each
// purchase pays itself back a little more slowly than the one before. What
// keeps that from being a game about *time* rather than *you* is that every
// multiplier on top of it comes from the log:
//
//     rate = Σ(level × base) × progress × health × hype × collection
//
// * progress   — ×20 by the goal, growing smoothly with how far along you
//                are (the prestige layer), ×2 more once you're there.
// * health     — ×0.5 … ×1.5 from the quality of what you've been eating.
// * hype       — +5% per sound-check item done today. Resets at midnight.
// * collection — +3% per piece of gear, +10% per bandmate.
//
// Everything weight-related is measured as a *fraction* of the way from
// starting weight to goal weight, never in pounds, so 15 lb to lose and 80
// lb to lose play the same game at different speeds — both max out the room
// right as they arrive.
//
// And it's weight that moves it, not time. Generators and gear unlock at
// fractions of the way to the goal, the last of each only at the goal
// itself, and each generator's level is capped by progress too. If the
// trend stalls, so does the studio: within the unlocked tier, 15% price
// growth against flat output means more time buys less and less, and the
// cap stops it outright. The game can't be finished before you are.

struct Generator: Identifiable, Hashable {
    let id: String
    let name: String
    let sprite: String
    /// Notes per second per level.
    let baseRate: Double
    let baseCost: Double
    /// Fraction of the way from start weight to goal weight.
    let unlockAt: Double
    let blurb: String

    func cost(level: Int) -> Double { baseCost * pow(IdleEngine.costGrowth, Double(level)) }

    /// The most copies progress allows: 10 at the start, 100 at the goal.
    static func levelCap(progress: Double) -> Int { 10 + Int(90 * min(1, max(0, progress))) }
}

/// How the buddy's doing, from what you've been eating.
enum BuddyHealth: String {
    case thriving, healthy, okay, queasy, sick

    init(score: Double) {
        switch score {
        case 0.75...: self = .thriving
        case 0.6..<0.75: self = .healthy
        case 0.45..<0.6: self = .okay
        case 0.3..<0.45: self = .queasy
        default: self = .sick
        }
    }

    var label: String { rawValue.capitalized }

    var sprite: String {
        switch self {
        case .thriving: return "smiling_face_with_hearts"
        case .healthy: return "slightly_smiling_face"
        case .okay: return "neutral_face"
        case .queasy: return "nauseated_face"
        case .sick: return "face_with_thermometer"
        }
    }

    var isUnwell: Bool { self == .queasy || self == .sick }
}

enum IdleEngine {
    static let costGrowth = 1.15
    /// Royalties pile up for this long, then the jar's full. Long enough to
    /// cover a night's sleep; short enough that opening the app daily matters.
    static let jarHours = 12.0

    static let generators: [Generator] = [
        Generator(id: "busk", name: "Busking", sprite: "guitar", baseRate: 0.1, baseCost: 15, unlockAt: 0,
                  blurb: "An open guitar case outside the grocery store."),
        Generator(id: "openmic", name: "Open Mic", sprite: "microphone", baseRate: 1, baseCost: 100, unlockAt: 0,
                  blurb: "Thursday nights. Seven people, two of them listening."),
        Generator(id: "radio", name: "Radio Play", sprite: "radio", baseRate: 8, baseCost: 1_100, unlockAt: 0.1,
                  blurb: "College station, 2 a.m. slot. It counts."),
        Generator(id: "playlist", name: "Playlists", sprite: "mobile_phone", baseRate: 47, baseCost: 12_000, unlockAt: 0.2,
                  blurb: "Someone put you on “songs for the gym.” Fitting."),
        Generator(id: "bus", name: "Tour Bus", sprite: "bus", baseRate: 260, baseCost: 130_000, unlockAt: 0.35,
                  blurb: "Twelve cities. One working outlet."),
        Generator(id: "arena", name: "Arena Shows", sprite: "stadium", baseRate: 1_400, baseCost: 1_400_000, unlockAt: 0.5,
                  blurb: "Halfway to goal, and the lights are bigger."),
        Generator(id: "label", name: "Label Deal", sprite: "money_bag", baseRate: 7_800, baseCost: 20_000_000, unlockAt: 0.7,
                  blurb: "They want a second album. You want a second track."),
        Generator(id: "world", name: "World Tour", sprite: "airplane", baseRate: 44_000, baseCost: 330_000_000, unlockAt: 1.0,
                  blurb: "Only at your goal weight. Every city. Earned."),
    ]

    static func generator(_ id: String) -> Generator? { generators.first { $0.id == id } }

    static func baseRate(levels: [String: Int]) -> Double {
        generators.reduce(0) { $0 + Double(levels[$1.id] ?? 0) * $1.baseRate }
    }

    // MARK: Multipliers

    struct Multipliers: Equatable {
        var progress = 1.0
        var health = 1.0
        var hype = 1.0
        var collection = 1.0
        var total: Double { progress * health * hype * collection }
    }

    /// ×1 at the start, ×20 at the goal, exponential in between — and ×2
    /// more for getting there.
    static func progressMultiplier(_ progress: Double) -> Double {
        let p = min(1, max(0, progress))
        return pow(20, p) * (p >= 1 - 1e-9 ? 2 : 1)
    }

    /// ×0.5 when the buddy's at its sickest, ×1.5 when it's thriving.
    static func healthMultiplier(_ score: Double) -> Double { 0.5 + min(1, max(0, score)) }

    static func hypeMultiplier(choresDone: Int) -> Double { 1 + 0.05 * Double(choresDone) }

    static func collectionMultiplier(gear: Int, bandmates: Int) -> Double {
        1 + 0.03 * Double(gear) + 0.1 * Double(bandmates)
    }

    // MARK: Logging pays a slice of the studio

    /// A sound-check item pays some minutes of the studio's current output
    /// (or its flat value, early on when that's bigger). Logging stays worth
    /// doing at every stage instead of becoming pocket change.
    static func minutes(for chore: Chore) -> Double {
        switch chore {
        case .weighIn: return 30
        case .firstFood: return 15
        case .threeMeals: return 30
        case .underBudget: return 20
        case .protein: return 20
        case .water: return 10
        case .moved: return 20
        case .photo: return 10
        }
    }

    static func payout(for chore: Chore, rate: Double) -> Double {
        max(Double(chore.notes), rate * 60 * minutes(for: chore))
    }

    // MARK: Food quality → health

    /// 0 (junk) … 1 (whole food) for one logged food. Calorie density does
    /// most of the work — the green/orange/red the app already shows — and
    /// fiber and added sugar nudge it.
    static func foodScore(_ food: FoodLog) -> Double {
        var density = food.density
        if density == nil, let grams = food.grams, grams > 0, food.calories > 0 {
            let kcalPerGram = Double(food.calories) / grams
            density = kcalPerGram < 1.0 ? "green" : (kcalPerGram < 2.4 ? "orange" : "red")
        }
        var score: Double
        switch density {
        case "green": score = 0.9
        case "orange": score = 0.55
        case "red": score = 0.15
        default: score = 0.5
        }
        if food.calories > 0 {
            let per100 = 100 / Double(food.calories)
            let facts = food.facts
            score += min(0.1, facts.fiberGrams * per100 * 0.03)
            score -= min(0.25, facts.addedSugarGrams * per100 * 0.02)
        }
        return min(1, max(0, score))
    }

    /// A day's food quality, weighted by calories so a side salad can't
    /// launder a large pizza. Nil when nothing's logged.
    static func dayQuality(_ day: DayLog) -> Double? {
        let foods = day.foods.filter { $0.calories > 0 }
        guard !foods.isEmpty else { return nil }
        let weight = foods.reduce(0.0) { $0 + Double($1.calories) }
        var q = foods.reduce(0.0) { $0 + foodScore($1) * Double($1.calories) } / weight
        q -= 0.05 * day.standardDrinks
        return min(1, max(0, q))
    }

    /// The buddy's health: a moving average over the last week of logged
    /// days, starting from neutral. One bad dinner dents it; a bad week makes
    /// it sick; good food brings it back just as fast. Days with nothing
    /// logged don't count either way.
    static func health(plan: Plan, today: Date = Date()) -> Double {
        let cal = Calendar.current
        let end = cal.startOfDay(for: today)
        guard let start = cal.date(byAdding: .day, value: -6, to: end) else { return 0.5 }
        let days = plan.days
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
        var h = 0.5
        for day in days {
            if let q = dayQuality(day) { h += 0.5 * (q - h) }
        }
        return h
    }

    // MARK: Normalized to the goal

    /// How far from the starting weight to the goal the trend has ever got,
    /// 0…1. Everything that unlocks, unlocks against this.
    static func goalProgress(plan: Plan) -> Double {
        let total = plan.startingWeight - plan.goalWeight
        guard total > 0 else { return 1 }
        let best = CalorieEngine.weightTrend(plan: plan).map(\.trend).min() ?? plan.startingWeight
        return min(1, max(0, (plan.startingWeight - best) / total))
    }

    /// The trend weight that unlocks something at `fraction` of the way.
    static func unlockWeight(_ fraction: Double, plan: Plan) -> Double {
        plan.startingWeight - fraction * max(0, plan.startingWeight - plan.goalWeight)
    }

    // MARK: Numbers

    /// 999 · 12.3K · 4.56M · 7.89B · 1.2T …
    static func format(_ x: Double) -> String {
        guard x.isFinite else { return "∞" }
        if x < 1000 { return x < 10 ? x.formatted(.number.precision(.fractionLength(0...1))) : "\(Int(x))" }
        let units = ["K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
        var v = x
        var i = -1
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        let digits = v < 10 ? 2 : (v < 100 ? 1 : 0)
        return v.formatted(.number.precision(.fractionLength(digits))) + units[i]
    }
}
