import Foundation

// The studio has two independent paths: weight milestones and consistent
// logging. Shop access uses whichever is further along. Weight trophies stay
// exclusive to the tour; weekly record rewards continue during maintenance.

struct Generator: Identifiable, Hashable {
    let id: String
    let name: String
    let sprite: String
    /// Notes per second per level.
    let baseRate: Double
    let baseCost: Double
    /// Fraction of studio progression (weight milestones or logging days).
    let unlockAt: Double
    let blurb: String

    func cost(level: Int) -> Double { baseCost * pow(IdleEngine.costGrowth, Double(level)) }

    /// The most copies progress allows: 10 at the start, 100 at the goal.
    static func levelCap(progress: Double) -> Int { 10 + Int(90 * min(1, max(0, progress))) }
}

/// A positive nutrition-bonus indicator; the buddy never gets sick from logs.
enum BuddyHealth: String {
    case thriving, healthy, okay

    init(score: Double) {
        switch score {
        case 0.75...: self = .thriving
        case 0.6..<0.75: self = .healthy
        default: self = .okay
        }
    }

    var label: String { rawValue.capitalized }

    var sprite: String {
        switch self {
        case .thriving: return "smiling_face_with_hearts"
        case .healthy: return "slightly_smiling_face"
        case .okay: return "neutral_face"
        }
    }
}

enum IdleEngine {
    static let costGrowth = 1.15
    /// Royalties pile up for this long, then the jar's full. Long enough to
    /// cover a full day, so one daily check-in can collect all passive income.
    static let jarHours = 24.0
    static let daysPerTier = 7
    static let loggingDaysToComplete = 63

    static func studioProgress(weight: Double, loggingDays: Int) -> Double {
        min(1, max(0, max(weight, Double(loggingDays) / Double(loggingDaysToComplete))))
    }

    static func loggingDaysRequired(progress: Double) -> Int {
        Int((progress * Double(loggingDaysToComplete) - 1e-9).rounded(.up))
    }

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
                  blurb: "The crowd is growing, and the lights are bigger."),
        Generator(id: "label", name: "Label Deal", sprite: "money_bag", baseRate: 7_800, baseCost: 20_000_000, unlockAt: 0.7,
                  blurb: "They want a second album. You want a second track."),
        Generator(id: "world", name: "World Tour", sprite: "airplane", baseRate: 44_000, baseCost: 330_000_000, unlockAt: 1.0,
                  blurb: "Nine weeks of sound checks, or your goal weight. Every city. Earned."),
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

    /// ×1 at the start, approaching ×20, then ×40 at full studio progress.
    static func progressMultiplier(_ progress: Double) -> Double {
        let p = min(1, max(0, progress))
        return pow(20, p) * (p >= 1 - 1e-9 ? 2 : 1)
    }

    /// A positive bonus only: baseline ×1, up to ×1.25.
    static func healthMultiplier(_ score: Double) -> Double { 1 + 0.25 * min(1, max(0, score)) }

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

    // MARK: Positive nutrition bonus

    /// Rewards recorded protein and fiber, never classifies food by density.
    /// Missing nutrition data yields no bonus, never an earnings penalty.
    static func nutritionScore(_ day: DayLog, targets: DailyTargets) -> Double {
        let protein = targets.proteinGrams > 0
            ? min(1, Double(day.totalProtein) / Double(targets.proteinGrams)) : 0
        let fiber = day.foods.reduce(0.0) { $0 + $1.facts.fiberGrams }
        // A game bonus threshold, not an individual dietary prescription.
        return 0.5 * max(0, protein) + 0.5 * min(1, max(0, fiber) / 20)
    }

    /// Use completed days so editing today's meals cannot reprice yesterday.
    static func health(plan: Plan, targets: DailyTargets, today: Date = Date()) -> Double {
        let cal = Calendar.current
        let end = cal.startOfDay(for: today)
        let start = cal.date(byAdding: .day, value: -7, to: end)!
        let days = plan.days.filter { $0.date >= start && $0.date < end && $0.totalCalories > 0 }
        guard !days.isEmpty else { return 0 }
        return days.reduce(0) { $0 + nutritionScore($1, targets: targets) } / Double(days.count)
    }

    static func goalProgress(start: Double, goal: Double, best: Double) -> Double {
        guard start.isFinite, goal.isFinite, best.isFinite, start > goal else { return 0 }
        return min(1, max(0, (start - best) / (start - goal)))
    }

    static func recordPrice(rate: Double, bought: Int) -> Double {
        // Three to twelve hours, rather than tripling forever.
        max(200, max(0, rate) * 3600 * min(12, 3 + Double(max(0, bought))))
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
