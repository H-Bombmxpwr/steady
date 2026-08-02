import Foundation

/// Local, deterministic sports-nutrition math — no network, no AI. Turns a
/// workout (type × intensity × duration × bodyweight) into a fueling plan:
/// carbs per hour during the session, fluids and sodium, a pre-load, and
/// recovery carbs + protein. Numbers follow mainstream endurance guidance
/// (ACSM / ISSN): ~30–60 g carb/hr for 1–2.5 h, up to ~90 g/hr beyond that,
/// 0.4–0.8 L fluid/hr, ~300–700 mg sodium/hr, and 1 g/kg carb + ~0.3 g/kg
/// protein for recovery. It's guidance, not a prescription.
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

    /// Endurance sessions long enough to need carbs mid-workout.
    var needsInWorkoutFuel: Bool { carbsPerHour > 0 }

    var headline: String {
        if needsInWorkoutFuel {
            return "Aim for \(carbsPerHour) g carbs/hr during — about \(duringCarbs) g across the session."
        }
        if minutes >= 45 && (category == .cardio || category == .sports) {
            return "Short enough to run on breakfast — just hydrate and refuel after."
        }
        return "Fuel is mostly before and after — protein for recovery matters most."
    }
}

enum FuelingEngine {
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
                     bodyweightLbs: Double) -> FuelingPlan {
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

        // --- Fluids & sodium (matter most on long or hard endurance days)
        let longEnough = isEndurance(category) && hours >= 1.0
        let fluidOzPerHour: Int
        let sodiumMgPerHour: Int
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
                           fluidOzPerHour: fluidOzPerHour,
                           sodiumMgPerHour: sodiumMgPerHour,
                           preCarbs: preCarbs,
                           recoveryCarbs: recoveryCarbs,
                           recoveryProtein: recoveryProtein,
                           burnCalories: Int(burn.rounded()))
    }
}
