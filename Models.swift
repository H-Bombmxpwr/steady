
import Foundation
import SwiftData

@Model
final class ChallengeState {
    var createdAt: Date
    var startDate: Date
    var dietName: String
    var dietDescription: String
    var dietLocked: Bool
    var totalDays: Int
    var allowAlcoholMonthly: Bool

    // NEW
    var startingWeight: Double?        // lbs (or kg—your choice; UI will label)
    var waterStepOunces: Int   // input step for Water steppers


    @Relationship(deleteRule: .cascade) var days: [DayEntry]
    @Relationship(deleteRule: .cascade) var presets: [WorkoutPreset]

    init(startDate: Date,
             dietName: String,
             dietDescription: String,
             totalDays: Int = 75,
             startingWeight: Double? = nil,
             waterStepOunces: Int = 8) {          // <- default 8 oz
            self.createdAt = Date()
            self.startDate = Calendar.current.startOfDay(for: startDate)
            self.dietName = dietName
            self.dietDescription = dietDescription
            self.dietLocked = true
            self.totalDays = totalDays
            self.allowAlcoholMonthly = true
            self.startingWeight = startingWeight
            self.days = []
            self.presets = []
            self.waterStepOunces = max(1, waterStepOunces)
        }
    }

@Model
final class DayEntry {
    var date: Date
    var workout1Minutes: Int
    var workout1Outdoor: Bool
    var workout2Minutes: Int
    var workout2Outdoor: Bool
    var waterOunces: Int
    var pagesRead: Int
    var dietCompliant: Bool
    var alcoholUsed: Bool
    @Relationship(deleteRule: .cascade) var photos: [PhotoEntry]

    // NEW
    var weight: Double?   // same unit as startingWeight

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.workout1Minutes = 0
        self.workout1Outdoor = false
        self.workout2Minutes = 0
        self.workout2Outdoor = false
        self.waterOunces = 0
        self.pagesRead = 0
        self.dietCompliant = false
        self.alcoholUsed = false
        self.photos = []
        self.weight = nil
    }

    var isComplete: Bool {
        let workoutsOK = workout1Minutes >= 45 && workout2Minutes >= 45 && (workout1Outdoor || workout2Outdoor)
        let waterOK = waterOunces >= 128
        let readOK = pagesRead >= 10
        let photoOK = !photos.isEmpty
        return workoutsOK && waterOK && readOK && dietCompliant && photoOK
    }
}


@Model
final class PhotoEntry {
    var filename: String
    var createdAt: Date

    init(filename: String) {
        self.filename = filename
        self.createdAt = Date()
    }
}

@Model
final class WorkoutPreset {
    var name: String
    var defaultMinutes: Int
    var outdoor: Bool
    var notes: String?

    init(name: String, defaultMinutes: Int = 45, outdoor: Bool = false, notes: String? = nil) {
        self.name = name
        self.defaultMinutes = defaultMinutes
        self.outdoor = outdoor
        self.notes = notes
    }
}
