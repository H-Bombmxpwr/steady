import Foundation
import SwiftData

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female, unspecified

    var id: String { rawValue }

    var label: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        case .unspecified: return "Prefer not to say"
        }
    }
}

enum ActivityLevel: String, Codable, CaseIterable, Identifiable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    /// TDEE multiplier applied to BMR.
    var factor: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.375
        case .moderate:   return 1.55
        case .active:     return 1.725
        case .veryActive: return 1.9
        }
    }

    /// The same multiplier with *planned training taken out* — everything the
    /// body spends on daily life, walking around, and fidgeting, but not the
    /// sessions themselves.
    ///
    /// Athlete mode counts each session's burn individually, so it must start
    /// from this rather than `factor` (which already assumes "exercise 3–5
    /// days/week") or every training day would be paid for twice.
    var nonExerciseFactor: Double {
        switch self {
        case .sedentary:  return 1.2
        case .light:      return 1.25
        case .moderate:   return 1.3
        case .active:     return 1.35
        case .veryActive: return 1.45   // physical job, not the workouts
        }
    }

    var label: String {
        switch self {
        case .sedentary:  return "Sedentary"
        case .light:      return "Lightly active"
        case .moderate:   return "Moderately active"
        case .active:     return "Active"
        case .veryActive: return "Very active"
        }
    }

    var detail: String {
        switch self {
        case .sedentary:  return "Desk job, little exercise"
        case .light:      return "Exercise 1–3 days/week"
        case .moderate:   return "Exercise 3–5 days/week"
        case .active:     return "Exercise 6–7 days/week"
        case .veryActive: return "Hard training or physical job"
        }
    }
}

@Model
final class UserProfile {
    var createdAt: Date
    var birthDate: Date
    var heightInches: Double
    var sexRaw: String
    var activityRaw: String

    // Additive (defaulted) so profiles created before modes existed migrate
    // straight into the weight-loss experience they already had.

    /// Which experience this person picked at setup — see `AppMode`.
    var modeRaw: String = AppMode.weightLoss.rawValue
    /// The general-health add-on: labs, sleep, steps, and nutrition quality
    /// surface on whichever dashboard the mode chose. Off unless asked for.
    var generalHealth: Bool = false
    /// Cycle tracking. Offered at setup when it's relevant, switchable any
    /// time in Settings, and stored only on this device.
    var cycleTracking: Bool = false
    /// Whether we've already offered cycle tracking, so the prompt appears
    /// once rather than every time Settings opens.
    var cycleTrackingOffered: Bool = false

    init(birthDate: Date, heightInches: Double, sex: BiologicalSex, activityLevel: ActivityLevel,
         mode: AppMode = .weightLoss, generalHealth: Bool = false) {
        self.createdAt = Date()
        self.birthDate = birthDate
        self.heightInches = heightInches
        self.sexRaw = sex.rawValue
        self.activityRaw = activityLevel.rawValue
        self.modeRaw = mode.rawValue
        self.generalHealth = generalHealth
    }

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .unspecified }
        set { sexRaw = newValue.rawValue }
    }

    var mode: AppMode {
        get { AppMode(rawValue: modeRaw) ?? .weightLoss }
        set { modeRaw = newValue.rawValue }
    }

    /// Whether to raise cycle tracking at all. Offered outright when the
    /// profile says female; asked as a question when it says prefer-not-to-say,
    /// since we genuinely don't know and shouldn't assume either way.
    var cycleTrackingRelevant: Bool { sex == .female || sex == .unspecified }

    /// Female profiles get it offered on by default; unspecified profiles get
    /// asked with nothing pre-selected.
    var cycleTrackingSuggested: Bool { sex == .female }

    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 30
    }
}
