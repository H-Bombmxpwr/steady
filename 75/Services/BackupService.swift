import Foundation
import SwiftUI

// Plain codable forms (avoid encoding SwiftData @Model types directly)
struct BackupPayload: Codable {
    struct BPhoto: Codable {
        let filename: String
        let createdAt: Date
        let base64JPEG: String   // embedded photo
    }
    struct BWorkout: Codable {
        let name: String
        let minutes: Int
        let outdoor: Bool
        let createdAt: Date
    }
    struct BFood: Codable {
        let name: String
        let calories: Int
        let proteinGrams: Int
        let grams: Double?
        let source: String
    }
    struct BDay: Codable {
        let date: Date
        let weight: Double?
        let waterOunces: Int
        let caloriesEaten: Int
        let proteinGrams: Int
        let standardDrinks: Double
        let takenSupplements: [String]
        let notes: String?
        let workouts: [BWorkout]
        let foods: [BFood]
        let photos: [BPhoto]
    }
    struct BScheduleEntry: Codable {
        let weekday: Int
        let name: String
        let minutes: Int
        let hour: Int
        let minute: Int
    }
    struct BSupplement: Codable {
        let name: String
        let hour: Int
        let minute: Int
        let remind: Bool
    }
    struct BPreset: Codable {
        let name: String
        let defaultMinutes: Int
        let outdoor: Bool
        let notes: String?
    }
    struct BProfile: Codable {
        let birthDate: Date
        let heightInches: Double
        let sex: String
        let activityLevel: String
    }

    let version: Int
    let exportedAt: Date

    // Plan-level
    let createdAt: Date
    let startDate: Date
    let startingWeight: Double
    let goalWeight: Double
    let paceLbsPerWeek: Double
    let waterGoalOunces: Int
    let waterStepOunces: Int
    let proteinTargetGrams: Int
    let calorieBudgetOverride: Int?

    let profile: BProfile
    let days: [BDay]
    let presets: [BPreset]
    let schedule: [BScheduleEntry]
    let supplements: [BSupplement]
}

enum BackupService {
    /// Builds a single JSON file containing profile, plan, days, presets, and embedded photos.
    static func exportJSON(profile: UserProfile, plan: Plan) throws -> URL {
        let sortedDays = plan.days.sorted { $0.date < $1.date }

        let bDays: [BackupPayload.BDay] = sortedDays.map { d in
            let photos: [BackupPayload.BPhoto] = d.photos.compactMap { p in
                let url = photosDir().appendingPathComponent(p.filename)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return .init(filename: p.filename, createdAt: p.createdAt, base64JPEG: data.base64EncodedString())
            }
            let workouts: [BackupPayload.BWorkout] = d.workouts.map {
                .init(name: $0.name, minutes: $0.minutes, outdoor: $0.outdoor, createdAt: $0.createdAt)
            }
            let foods: [BackupPayload.BFood] = d.foods.map {
                .init(name: $0.name, calories: $0.calories, proteinGrams: $0.proteinGrams,
                      grams: $0.grams, source: $0.source)
            }
            return .init(
                date: d.date,
                weight: d.weight,
                waterOunces: d.waterOunces,
                caloriesEaten: d.caloriesEaten,
                proteinGrams: d.proteinGrams,
                standardDrinks: d.standardDrinks,
                takenSupplements: d.takenSupplements,
                notes: d.notes,
                workouts: workouts,
                foods: foods,
                photos: photos
            )
        }

        let bPresets: [BackupPayload.BPreset] = plan.presets.map {
            .init(name: $0.name, defaultMinutes: $0.defaultMinutes, outdoor: $0.outdoor, notes: $0.notes)
        }

        let payload = BackupPayload(
            version: 2,
            exportedAt: Date(),
            createdAt: plan.createdAt,
            startDate: plan.startDate,
            startingWeight: plan.startingWeight,
            goalWeight: plan.goalWeight,
            paceLbsPerWeek: plan.paceLbsPerWeek,
            waterGoalOunces: plan.waterGoalOunces,
            waterStepOunces: plan.waterStepOunces,
            proteinTargetGrams: plan.proteinTargetGrams,
            calorieBudgetOverride: plan.calorieBudgetOverride,
            profile: .init(birthDate: profile.birthDate,
                           heightInches: profile.heightInches,
                           sex: profile.sexRaw,
                           activityLevel: profile.activityRaw),
            days: bDays,
            presets: bPresets,
            schedule: plan.schedule.map {
                .init(weekday: $0.weekday, name: $0.name, minutes: $0.minutes,
                      hour: $0.hour, minute: $0.minute)
            },
            supplements: plan.supplements.map {
                .init(name: $0.name, hour: $0.hour, minute: $0.minute, remind: $0.remind)
            }
        )

        // Encode JSON
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try enc.encode(payload)

        // Write to a temp file
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("75-fitness-\(Int(Date().timeIntervalSince1970)).75-backup.json")
        try data.write(to: outURL, options: .atomic)
        return outURL
    }
}
