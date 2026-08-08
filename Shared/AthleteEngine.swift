import Foundation

/// How much work a day actually contains. Carbohydrate need tracks training
/// load far more closely than it tracks bodyweight or bodyfat goals, which is
/// why athlete mode periodizes carbs by the day instead of holding one macro
/// split all week.
enum TrainingLoad: String, CaseIterable, Identifiable {
    case rest, light, moderate, heavy, extreme

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rest: return "Rest"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        case .extreme: return "Very heavy"
        }
    }

    /// Daily carbohydrate, g per kg bodyweight.
    ///
    /// The ISSN / ACSM bands run 3–5 (rest), 5–7 (about an hour), 6–10
    /// (1–3 hours) and 8–12 (extreme). These sit mid-band rather than at the
    /// top of it: overshooting leaves no calories for the fat floor, which
    /// then pushes the day's total above maintenance-plus-training on a day
    /// that didn't earn it.
    var carbsPerKg: Double {
        switch self {
        case .rest:     return 3.5
        case .light:    return 4.5
        case .moderate: return 5.5
        case .heavy:    return 7.0
        case .extreme:  return 9.0
        }
    }

    /// Daily protein, g per kg. Higher on hard days and in a deficit — the
    /// job is protecting lean mass while the training load does damage.
    var proteinPerKg: Double {
        switch self {
        case .rest, .light: return 1.6
        case .moderate:     return 1.7
        case .heavy:        return 1.9
        case .extreme:      return 2.0
        }
    }

    /// Describes the *demand*, not the clock — a published TSS can make a
    /// ninety-minute day rank below a long easy one, so asserting durations
    /// here would contradict the card right above it.
    var detail: String {
        switch self {
        case .rest:
            return "No session planned. Carbs come down, protein stays put."
        case .light:
            return "Low demand. Don't over-fuel an easy day."
        case .moderate:
            return "A solid, ordinary day of work. Carbs up a little, protein steady."
        case .heavy:
            return "A demanding day. Carbs matter, and timing them around the session matters more."
        case .extreme:
            return "A very big day. Eating enough is the hardest part of it."
        }
    }

    var tint: String { rawValue }
}

/// The day's macro plan in athlete mode.
struct AthleteTargets {
    let load: TrainingLoad
    let calories: Int
    let carbGrams: Int
    let proteinGrams: Int
    let fatGrams: Int
    let waterOunces: Int
    /// Estimated calories the day's training costs, already inside `calories`.
    let trainingBurn: Int
    /// Total planned training minutes.
    let trainingMinutes: Int
}

enum AthleteEngine {

    /// Classify the day from what's planned. Duration does most of the work;
    /// intensity and TSS pull a day up a band when it's genuinely hard rather
    /// than merely long.
    static func load(for sessions: [TrainingSession]) -> TrainingLoad {
        guard !sessions.isEmpty else { return .rest }

        // Weight the minutes by how hard they are, so 60 min of intervals
        // outranks 60 min of easy spinning.
        let weighted = sessions.reduce(0.0) {
            $0 + Double($1.minutes) * $1.intensity.burnFactor
        }
        let tss = sessions.compactMap(\.tss).reduce(0, +)

        // TSS is the better signal whenever the plan published one — 100 TSS
        // is by definition an hour at threshold, so an ordinary hard hour is
        // squarely a moderate day, not a heavy one.
        if tss > 0 {
            switch tss {
            case ..<40:   return .light
            case ..<110:  return .moderate
            case ..<220:  return .heavy
            default:      return .extreme
            }
        }

        switch weighted {
        case ..<30:   return .rest
        case ..<60:   return .light
        case ..<110:  return .moderate
        case ..<230:  return .heavy
        default:      return .extreme
        }
    }

    /// Build the day's athlete targets.
    ///
    /// Calories start at maintenance (the adaptive TDEE when it's learned
    /// enough to be trusted, the formula otherwise) and add the day's training
    /// on top — an athlete eating a fixed budget on a rest day and a five-hour
    /// day is under-fueling one of them. A deliberate body-composition deficit
    /// is subtracted only when the athlete has asked for one.
    static func targets(profile: UserProfile,
                        plan: Plan,
                        maintenanceTDEE: Double,
                        sessions: [TrainingSession],
                        weather: WeatherContext? = nil,
                        cyclePhase: CyclePhase? = nil) -> AthleteTargets {
        let load = load(for: sessions)
        let kg = max(30, plan.currentWeight * 0.45359237)
        let sweat = plan.sweatProfile()

        let plans = sessions.map {
            FuelingEngine.plan(for: $0,
                               bodyweightLbs: plan.currentWeight,
                               sweat: sweat,
                               weather: plan.weatherAwareFueling ? weather : nil,
                               cyclePhase: cyclePhase)
        }
        let burn = plans.reduce(0) { $0 + $1.burnCalories }
        let sessionFluid = plans.reduce(0) { $0 + $1.totalFluidOz }
        let minutes = sessions.reduce(0) { $0 + $1.minutes }

        // Maintenance already contains an activity multiplier for daily life;
        // the session burn is the training on top of that.
        var calories = maintenanceTDEE + Double(burn)
        if !plan.eatAtMaintenance, plan.paceLbsPerWeek > 0 {
            // A body-composition block. Athletes lose performance fast in a
            // steep deficit, so this is capped well under the weight-loss
            // pace — about 1 lb/week at most, whatever the plan says.
            let pace = min(1.0, plan.paceLbsPerWeek)
            calories -= pace * 3500.0 / 7.0
        }

        // Protein first — it's the target that shouldn't flex.
        var proteinPerKg = load.proteinPerKg
        if !plan.eatAtMaintenance { proteinPerKg = max(proteinPerKg, 2.0) }
        let protein = proteinPerKg * kg

        let carbs = load.carbsPerKg * kg

        // Fat takes what's left, with a floor — going too low costs hormones
        // and fat-soluble vitamin absorption, so calories give way instead.
        let remaining = calories - (protein * 4 + carbs * 4)
        let fat = max(kg * 0.7, remaining / 9)
        let finalCalories = protein * 4 + carbs * 4 + fat * 9

        let water = plan.waterGoalOunces + sessionFluid

        return AthleteTargets(load: load,
                              calories: Int(finalCalories.rounded()),
                              carbGrams: Int(carbs.rounded()),
                              proteinGrams: Int(protein.rounded()),
                              fatGrams: Int(fat.rounded()),
                              waterOunces: water,
                              trainingBurn: burn,
                              trainingMinutes: minutes)
    }

    /// A plain-language line for the dashboard: what today asks of you.
    static func summary(_ targets: AthleteTargets) -> String {
        switch targets.load {
        case .rest:
            return "Rest day. Protein holds at \(targets.proteinGrams) g — that's what recovery is built from."
        case .light:
            return "Light day. \(targets.carbGrams) g carbs is plenty; don't over-fuel an easy session."
        case .moderate:
            return "\(targets.trainingMinutes) min planned. \(targets.carbGrams) g carbs across the day, most of it around the session."
        case .heavy:
            return "Big day — \(targets.trainingMinutes) min. \(targets.carbGrams) g carbs, and start topping up before you're empty."
        case .extreme:
            return "\(targets.trainingMinutes) min of training. Eating \(targets.carbGrams) g carbs takes planning — spread it, don't stack it."
        }
    }
}
