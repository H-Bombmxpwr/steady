import Foundation
import SwiftData

/// One sweat test — the standard field protocol: weigh in before (dry, minimal
/// clothing), train, towel off, weigh again, and record everything you drank.
/// The mass you're missing, plus what you put in, is what you sweated out.
///
/// Two or three of these in different conditions beat any formula: published
/// sweat rates span 0.3–2.4 L/hr between people doing the same session, which
/// is why generic "drink 20 oz an hour" advice is wrong for most athletes in
/// both directions.
@Model
final class SweatTest {
    var date: Date
    var preWeightLbs: Double
    var postWeightLbs: Double
    /// Everything drunk during the session.
    var fluidOunces: Double
    var minutes: Int
    var categoryRaw: String = WorkoutCategory.cardio.rawValue
    var intensityRaw: String = WorkoutIntensity.moderate.rawValue
    /// Conditions during the test, so a cool-morning result isn't applied to
    /// an August afternoon. Filled from the weather service when available.
    var tempF: Double?
    var humidityPercent: Double?
    var notes: String?
    var createdAt: Date = Date()

    init(date: Date = Date(),
         preWeightLbs: Double,
         postWeightLbs: Double,
         fluidOunces: Double,
         minutes: Int,
         category: WorkoutCategory = .cardio,
         intensity: WorkoutIntensity = .moderate,
         tempF: Double? = nil,
         humidityPercent: Double? = nil,
         notes: String? = nil) {
        self.date = date
        self.preWeightLbs = preWeightLbs
        self.postWeightLbs = postWeightLbs
        self.fluidOunces = fluidOunces
        self.minutes = minutes
        self.categoryRaw = category.rawValue
        self.intensityRaw = intensity.rawValue
        self.tempF = tempF
        self.humidityPercent = humidityPercent
        self.notes = notes
        self.createdAt = Date()
    }

    var category: WorkoutCategory {
        get { WorkoutCategory(rawValue: categoryRaw) ?? .cardio }
        set { categoryRaw = newValue.rawValue }
    }

    var intensity: WorkoutIntensity {
        get { WorkoutIntensity(rawValue: intensityRaw) ?? .moderate }
        set { intensityRaw = newValue.rawValue }
    }

    var hours: Double { Double(max(1, minutes)) / 60.0 }

    /// Total sweat volume: the mass you lost (1 kg ≈ 1 L of water) plus every
    /// ounce you drank, which had already replaced some of it.
    var sweatLiters: Double {
        let lostLiters = (preWeightLbs - postWeightLbs) * 0.45359237
        let drankLiters = fluidOunces * 0.0295735
        return max(0, lostLiters + drankLiters)
    }

    var sweatRateLitersPerHour: Double { sweatLiters / hours }

    /// The number people actually act on — how much to drink per hour.
    var sweatRateOuncesPerHour: Double { sweatRateLitersPerHour * 33.814 }

    /// Body mass lost as a percentage. Past about 2% is where endurance
    /// performance measurably falls off.
    var dehydrationPercent: Double {
        guard preWeightLbs > 0 else { return 0 }
        return (preWeightLbs - postWeightLbs) / preWeightLbs * 100
    }

    /// A sanity check — a "sweat rate" of 6 L/hr means the scale or the units
    /// were wrong, and a negative one means they gained weight.
    var isPlausible: Bool {
        minutes >= 20 && sweatRateLitersPerHour > 0.1 && sweatRateLitersPerHour < 4.0
    }

    var conditionsText: String? {
        guard let tempF else { return nil }
        var text = "\(Int(tempF.rounded()))°F"
        if let humidityPercent { text += " · \(Int(humidityPercent.rounded()))% RH" }
        return text
    }
}

// MARK: - Salt loss

/// How salty someone's sweat is. Measuring it needs a patch test most people
/// won't do, but self-report tracks it well enough to matter: sweat sodium
/// ranges roughly 200–2000 mg/L, and the difference between the ends is
/// several grams of sodium across a long day.
enum SaltLoss: String, Codable, CaseIterable, Identifiable {
    case low, typical, salty

    var id: String { rawValue }

    var label: String {
        switch self {
        case .low: return "Not salty"
        case .typical: return "Typical"
        case .salty: return "Salty sweater"
        }
    }

    /// The tell, in plain language — this is what people can actually answer.
    var cue: String {
        switch self {
        case .low: return "No grit or stinging, kit stays clean"
        case .typical: return "Faint marks on a dark shirt now and then"
        case .salty: return "White crust on skin and kit, sweat stings the eyes"
        }
    }

    /// mg of sodium per liter of sweat.
    var sodiumMgPerLiter: Double {
        switch self {
        case .low: return 400
        case .typical: return 900
        case .salty: return 1500
        }
    }

    static let storageKey = "sweat.saltLoss"
}

// MARK: - Learned sweat profile

/// What the sweat tests add up to. `nil` everywhere until at least one
/// plausible test exists — the fueling engine falls back to its generic
/// guidance rather than inventing a number.
struct SweatProfile {
    let litersPerHour: Double
    let saltLoss: SaltLoss
    let testCount: Int
    /// Average conditions across the tests that fed this, so the UI can say
    /// "measured at 68°F" and the engine can extrapolate to a hotter day.
    let baselineTempF: Double?
    /// The metabolic intensity of the sessions this was measured on, as a MET
    /// value. Sweat rate tracks the heat a body is producing, so a rate
    /// measured on a hard ride must be scaled down before it's applied to a
    /// stretching session — otherwise 25 minutes of mobility inherits a
    /// cyclist's hydration plan.
    let baselineMET: Double

    var ouncesPerHour: Double { litersPerHour * 33.814 }
    var sodiumMgPerHour: Double { litersPerHour * saltLoss.sodiumMgPerLiter }

    /// This rate rescaled for a session of a different metabolic demand.
    func litersPerHour(forMET met: Double) -> Double {
        guard baselineMET > 0 else { return litersPerHour }
        // Sweating doesn't scale all the way to zero with effort — resting
        // insensible losses continue — so the floor keeps it sane.
        return litersPerHour * max(0.35, met / baselineMET)
    }
}

enum SweatEngine {

    /// Blend the plausible tests into one rate, weighting recent tests and
    /// tests that match the session type being planned. Hard efforts sweat
    /// more than easy ones, so an easy-ride test shouldn't set the rate for a
    /// threshold session — the intensity ratio corrects for that.
    static func profile(tests: [SweatTest],
                        saltLoss: SaltLoss,
                        matching category: WorkoutCategory? = nil,
                        intensity: WorkoutIntensity? = nil) -> SweatProfile? {
        let usable = tests.filter(\.isPlausible)
        guard !usable.isEmpty else { return nil }

        let newest = usable.map(\.date).max() ?? Date()
        var weightedSum = 0.0
        var weightTotal = 0.0
        var tempSum = 0.0
        var tempCount = 0.0
        var metSum = 0.0

        for test in usable {
            // Halve the weight every 120 days — a rate measured last winter
            // still counts, just less than one from last week.
            let ageDays = max(0, test.date.days(to: newest))
            var weight = pow(0.5, Double(ageDays) / 120.0)
            if let category, test.category == category { weight *= 2.0 }
            if let intensity, test.intensity == intensity { weight *= 1.5 }

            // Normalize the test onto the target intensity's burn level;
            // sweat scales with heat produced, which is what burnFactor is.
            var rate = test.sweatRateLitersPerHour
            if let intensity {
                rate *= intensity.burnFactor / test.intensity.burnFactor
            }

            weightedSum += rate * weight
            weightTotal += weight
            metSum += test.category.metEstimate * weight
            if let t = test.tempF { tempSum += t; tempCount += 1 }
        }

        guard weightTotal > 0 else { return nil }
        return SweatProfile(litersPerHour: weightedSum / weightTotal,
                            saltLoss: saltLoss,
                            testCount: usable.count,
                            baselineTempF: tempCount > 0 ? tempSum / tempCount : nil,
                            baselineMET: metSum / weightTotal)
    }
}

// MARK: - Weather

/// The conditions a session will actually happen in. Heat and humidity drive
/// sweat rate harder than anything except intensity, and an athlete who nails
/// their fueling in April can be badly under-hydrated in July on the identical
/// ride.
struct WeatherContext: Equatable {
    let tempF: Double
    let humidityPercent: Double
    /// Apparent temperature — what the body has to cope with once humidity
    /// stops sweat evaporating. Rothfusz regression, the NWS heat index.
    let heatIndexF: Double
    let conditionDescription: String?
    let capturedAt: Date

    init(tempF: Double, humidityPercent: Double, conditionDescription: String? = nil,
         capturedAt: Date = Date()) {
        self.tempF = tempF
        self.humidityPercent = humidityPercent
        self.heatIndexF = WeatherContext.heatIndex(tempF: tempF, humidity: humidityPercent)
        self.conditionDescription = conditionDescription
        self.capturedAt = capturedAt
    }

    /// NWS heat index. Below 80°F the regression misbehaves, so the simple
    /// Steadman average is used there instead.
    static func heatIndex(tempF t: Double, humidity r: Double) -> Double {
        let simple = 0.5 * (t + 61.0 + ((t - 68.0) * 1.2) + (r * 0.094))
        guard (simple + t) / 2 >= 80 else { return simple }

        var hi = -42.379 + 2.04901523 * t + 10.14333127 * r
            - 0.22475541 * t * r - 0.00683783 * t * t
            - 0.05481717 * r * r + 0.00122874 * t * t * r
            + 0.00085282 * t * r * r - 0.00000199 * t * t * r * r

        // The two documented corrections at the dry and humid extremes.
        if r < 13 && t >= 80 && t <= 112 {
            hi -= ((13 - r) / 4) * sqrt((17 - abs(t - 95)) / 17)
        } else if r > 85 && t >= 80 && t <= 87 {
            hi += ((r - 85) / 10) * ((87 - t) / 5)
        }
        return hi
    }

    enum Severity: String {
        case cold, cool, mild, warm, hot, extreme

        var label: String {
            switch self {
            case .cold: return "Cold"
            case .cool: return "Cool"
            case .mild: return "Mild"
            case .warm: return "Warm"
            case .hot: return "Hot"
            case .extreme: return "Dangerous heat"
            }
        }

        var icon: String {
            switch self {
            case .cold: return "snowflake"
            case .cool: return "wind"
            case .mild: return "sun.min"
            case .warm: return "sun.max"
            case .hot: return "thermometer.sun.fill"
            case .extreme: return "exclamationmark.triangle.fill"
            }
        }
    }

    var severity: Severity {
        switch heatIndexF {
        case ..<40:  return .cold
        case ..<60:  return .cool
        case ..<75:  return .mild
        case ..<85:  return .warm
        case ..<103: return .hot
        default:     return .extreme
        }
    }

    /// Scales the fluid target. Anchored at ~70°F = 1.0; sweat rate roughly
    /// doubles between a cool morning and a hot humid afternoon, which is the
    /// range this spans. Cold weather still needs fluid — hence the 0.85 floor.
    var fluidMultiplier: Double {
        let delta = heatIndexF - 70
        return min(1.9, max(0.85, 1.0 + delta * 0.012))
    }

    /// Sodium scales with sweat volume, so it rides the same curve.
    var sodiumMultiplier: Double { fluidMultiplier }

    /// Cold and heat both cut the carb-burning efficiency argument differently;
    /// in real heat, gut tolerance drops and glycogen use rises, so the honest
    /// advice is "same carbs, more fluid, and expect to feel worse".
    var advisory: String? {
        switch severity {
        case .extreme:
            return "Dangerous heat. Move the session earlier, cut the intensity, or take it indoors — no fueling plan makes this safe."
        case .hot:
            return "Hot. Start fully hydrated, drink to the higher end, and don't chase your usual paces."
        case .cold:
            return "Cold. Thirst drops in the cold but you're still losing fluid — drink on schedule, not on thirst."
        default:
            return nil
        }
    }
}
