import Foundation

/// Local, deterministic sports-nutrition math — no network, no AI. Turns a
/// workout (type × intensity × duration × bodyweight) into a fueling plan:
/// carbs per hour during the session, fluids and sodium, a pre-load, and
/// recovery carbs + protein. Numbers follow mainstream endurance guidance
/// (ACSM / ISSN): ~30–60 g carb/hr for 1–2.5 h, up to ~90 g/hr beyond that,
/// 0.4–0.8 L fluid/hr, ~300–700 mg sodium/hr, and 1 g/kg carb + ~0.3 g/kg
/// protein for recovery. It's guidance, not a prescription.
///
/// Two inputs sharpen it when they exist. A measured sweat rate replaces the
/// generic fluid table outright — published rates span 0.3–2.4 L/hr for the
/// same session, so a personal number beats any average. Local heat and
/// humidity then scale both fluid and sodium, because the identical ride in
/// April and July are not the same hydration problem.
struct FuelingPlan: Identifiable {
    let id = UUID()
    let category: WorkoutCategory
    let intensity: WorkoutIntensity
    let minutes: Int

    let carbsPerHour: Int         // during the session (g/hr); 0 when not needed
    let duringCarbs: Int          // total during-session carbs (g)
    let fluidOzPerHour: Int
    let sodiumMgPerHour: Int
    let preCarbs: Int             // top-up in the hour or two before
    let recoveryCarbs: Int        // after, to refill glycogen
    let recoveryProtein: Int      // after, for repair
    let burnCalories: Int         // estimated session energy cost

    /// True when the fluid and sodium numbers came from this athlete's own
    /// sweat tests rather than the generic table.
    let fluidIsMeasured: Bool
    /// The conditions folded into the numbers, when weather was available.
    let weather: WeatherContext?
    /// Anything worth saying out loud — heat warnings, sweat-test nudges.
    let advisories: [String]

    /// Endurance sessions long enough to need carbs mid-workout.
    var needsInWorkoutFuel: Bool { carbsPerHour > 0 }

    /// Total fluid across the session.
    var totalFluidOz: Int {
        Int((Double(fluidOzPerHour) * Double(minutes) / 60.0).rounded())
    }

    var headline: String {
        if needsInWorkoutFuel {
            return "Aim for \(carbsPerHour) g carbs/hr during — about \(duringCarbs) g across the session."
        }
        if minutes >= 45 && (category == .cardio || category == .sports) {
            return "Short enough to run on breakfast — just hydrate and refuel after."
        }
        return "Fuel is mostly before and after — protein for recovery matters most."
    }

    /// Why the carbs are what they are — the reasoning, in one line, keyed to
    /// the type of workout rather than a generic number.
    var carbRationale: String {
        switch category {
        case .cardio, .sports:
            if needsInWorkoutFuel {
                return "Endurance work past an hour outruns stored glycogen, so carbs go in during the session — not just around it."
            }
            return "Under an hour, stored glycogen covers it. Eating during would be fuel you don't need."
        case .strength:
            return "Lifting is powered by glycogen but spends it slowly. Carbs before to train hard, carbs and protein after to rebuild."
        case .mobility:
            return "Low demand — no special fueling. Normal meals cover this."
        case .other:
            return "Fueled as a moderate mixed session: something before, protein and carbs after."
        }
    }
}

enum FuelingEngine {
    /// The practical ceiling on drinking during exercise. Beyond roughly a
    /// liter an hour most people can't absorb it, and pushing past sweat
    /// losses is how hyponatremia happens — this caps the advice even when a
    /// measured sweat rate is higher.
    static let maxFluidOzPerHour = 34

    /// Which workout types burn glycogen fast enough that mid-session carbs
    /// help. Strength/mobility get pre/post guidance only.
    private static func isEndurance(_ c: WorkoutCategory) -> Bool {
        c == .cardio || c == .sports
    }

    /// MET estimate for the burn calculation, before the intensity factor.
    private static func baseMET(_ c: WorkoutCategory) -> Double {
        switch c {
        case .cardio:   return 8.5
        case .sports:   return 7.5
        case .strength: return 5.0
        case .mobility: return 2.8
        case .other:    return 6.0
        }
    }

    static func plan(category: WorkoutCategory,
                     intensity: WorkoutIntensity,
                     minutes: Int,
                     bodyweightLbs: Double,
                     sweat: SweatProfile? = nil,
                     weather: WeatherContext? = nil,
                     cyclePhase: CyclePhase? = nil) -> FuelingPlan {
        let kg = max(30, bodyweightLbs * 0.45359237)
        let hours = Double(max(0, minutes)) / 60.0

        // Session burn: MET × kg × hours, scaled by how hard it is.
        let burn = baseMET(category) * intensity.burnFactor * kg * hours

        // --- During-session carbs (endurance only, and only once it runs long)
        var perHour = 0
        if isEndurance(category) {
            switch hours {
            case ..<1.0:  perHour = 0            // running on what's already stored
            case ..<1.5:  perHour = 30           // 45–90 min: the low end of the range
            case ..<2.5:  perHour = 55           // 1.5–2.5 h: classic 30–60 g/hr
            default:      perHour = 80           // 2.5 h+: multiple-carb territory, up to 90
            }
            // Nudge within the guidance band for how hard the effort is.
            if perHour > 0 {
                switch intensity {
                case .easy:     perHour = max(20, perHour - 10)
                case .moderate: break
                case .hard:     perHour = min(90, perHour + 10)
                }
            }
        }
        let duringCarbs = Int((Double(perHour) * hours).rounded())

        // --- Fluids & sodium
        let longEnough = isEndurance(category) && hours >= 1.0
        var fluidOzPerHour: Double
        var sodiumMgPerHour: Double
        var advisories: [String] = []

        if let sweat {
            // Rescale the measured rate for this session's metabolic demand
            // before anything else. A rate measured on a hard ride would
            // otherwise hand a 25-minute mobility session a cyclist's
            // hydration plan.
            let scaled = sweat.litersPerHour(forMET: baseMET(category) * intensity.burnFactor)
            // Replace ~80% of measured losses. Full replacement is rarely
            // achievable mid-session and isn't the target anyway — staying
            // inside about 2% body-mass loss is.
            fluidOzPerHour = scaled * 33.814 * 0.8
            sodiumMgPerHour = scaled * sweat.saltLoss.sodiumMgPerLiter
            // A rate measured in the cold, applied on a hot day, would
            // under-call it. Scale from the test conditions, not from 70°F.
            if let weather, let baseline = sweat.baselineTempF {
                let baselineContext = WeatherContext(tempF: baseline, humidityPercent: 50)
                let ratio = weather.fluidMultiplier / baselineContext.fluidMultiplier
                fluidOzPerHour *= ratio
                sodiumMgPerHour *= ratio
            }
        } else {
            if isEndurance(category) {
                switch intensity {
                case .easy:     fluidOzPerHour = 16; sodiumMgPerHour = longEnough ? 300 : 0
                case .moderate: fluidOzPerHour = 20; sodiumMgPerHour = longEnough ? 500 : 200
                case .hard:     fluidOzPerHour = 24; sodiumMgPerHour = longEnough ? 700 : 300
                }
            } else {
                fluidOzPerHour = 12
                sodiumMgPerHour = 0
            }
            if let weather {
                fluidOzPerHour *= weather.fluidMultiplier
                sodiumMgPerHour *= weather.sodiumMultiplier
            }
            if hours >= 1.0 && isEndurance(category) {
                advisories.append("These fluid numbers are population averages. One sweat test replaces them with yours — sweat rates vary several-fold between people.")
            }
        }

        // Slightly higher core temperature in the luteal phase means sweating
        // starts sooner. Small, but it's the one phase effect with a number.
        if let cyclePhase {
            fluidOzPerHour *= cyclePhase.fluidMultiplier
            sodiumMgPerHour *= cyclePhase.fluidMultiplier
        }

        if let advisory = weather?.advisory { advisories.insert(advisory, at: 0) }

        let cappedFluid = min(Double(maxFluidOzPerHour), fluidOzPerHour)
        if fluidOzPerHour > Double(maxFluidOzPerHour) {
            // Sodium rides along with the fluid: a target you can't drink
            // isn't a target. The shortfall is real, which is what the
            // advisory is for — make it up at the table, not mid-session.
            sodiumMgPerHour *= cappedFluid / fluidOzPerHour
            advisories.append("Your losses run higher than most people can absorb mid-session — capped at \(maxFluidOzPerHour) oz/hr here. Start fully topped up, expect to finish down a little, and make up the rest of the fluid and salt afterwards.")
        }
        // Sodium guidance is meaningless on a session that barely raises a
        // sweat; it just makes the card look busy.
        if minutes < 30 && !isEndurance(category) { sodiumMgPerHour = 0 }

        // --- Pre-load: a light carb top-up before endurance work
        var preCarbs = 0
        if isEndurance(category) && hours >= 1.0 {
            // ~0.5 g/kg before a moderate session, a touch more before long/hard
            let perKg = hours >= 2.0 ? 1.0 : 0.5
            preCarbs = Int((kg * perKg * intensity.burnFactor).rounded())
        } else if category == .strength {
            preCarbs = Int((kg * 0.3).rounded())    // a little to train hard on
        }

        // --- Recovery: refill glycogen + protein for repair
        let recoveryCarbs: Int
        if isEndurance(category) {
            // ~1 g/kg after a real endurance session, scaled down for short/easy
            let perKg = hours >= 1.0 ? 1.0 : 0.5
            recoveryCarbs = Int((kg * perKg).rounded())
        } else {
            recoveryCarbs = Int((kg * 0.5).rounded())
        }
        // 0.3 g/kg protein (≈20–35 g) after any real session
        let recoveryProtein = minutes >= 20 ? Int((kg * 0.3).rounded()) : 0

        return FuelingPlan(category: category,
                           intensity: intensity,
                           minutes: minutes,
                           carbsPerHour: perHour,
                           duringCarbs: duringCarbs,
                           fluidOzPerHour: Int(cappedFluid.rounded()),
                           sodiumMgPerHour: Int(sodiumMgPerHour.rounded()),
                           preCarbs: preCarbs,
                           recoveryCarbs: recoveryCarbs,
                           recoveryProtein: recoveryProtein,
                           burnCalories: Int(burn.rounded()),
                           fluidIsMeasured: sweat != nil,
                           weather: weather,
                           advisories: advisories)
    }

    /// The plan for a session, wired to everything the app knows: the
    /// athlete's sweat tests, today's weather, and the cycle phase.
    static func plan(for session: TrainingSession,
                     bodyweightLbs: Double,
                     sweat: SweatProfile? = nil,
                     weather: WeatherContext? = nil,
                     cyclePhase: CyclePhase? = nil) -> FuelingPlan {
        plan(category: session.category,
             intensity: session.intensity,
             minutes: session.minutes,
             bodyweightLbs: bodyweightLbs,
             sweat: sweat,
             weather: weather,
             cyclePhase: cyclePhase)
    }
}
