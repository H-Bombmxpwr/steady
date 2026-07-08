import Foundation
import SwiftData

enum BiologicalSex: String, Codable, CaseIterable, Identifiable {
    case male, female
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
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

    init(birthDate: Date, heightInches: Double, sex: BiologicalSex, activityLevel: ActivityLevel) {
        self.createdAt = Date()
        self.birthDate = birthDate
        self.heightInches = heightInches
        self.sexRaw = sex.rawValue
        self.activityRaw = activityLevel.rawValue
    }

    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var activityLevel: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .moderate }
        set { activityRaw = newValue.rawValue }
    }

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year ?? 30
    }
}
