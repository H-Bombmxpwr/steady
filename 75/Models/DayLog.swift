import Foundation
import SwiftData

@Model
final class DayLog {
    var date: Date
    var weight: Double?               // lb
    var waterOunces: Int
    var caloriesEaten: Int
    var proteinGrams: Int
    var alcoholDrinks: Int
    var notes: String?

    @Relationship(deleteRule: .cascade) var workouts: [WorkoutLog]
    @Relationship(deleteRule: .cascade) var photos: [PhotoEntry]

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
        self.weight = nil
        self.waterOunces = 0
        self.caloriesEaten = 0
        self.proteinGrams = 0
        self.alcoholDrinks = 0
        self.notes = nil
        self.workouts = []
        self.photos = []
    }

    var workoutMinutes: Int { workouts.reduce(0) { $0 + $1.minutes } }
}

@Model
final class WorkoutLog {
    var name: String
    var minutes: Int
    var outdoor: Bool
    var createdAt: Date

    init(name: String, minutes: Int, outdoor: Bool = false) {
        self.name = name
        self.minutes = minutes
        self.outdoor = outdoor
        self.createdAt = Date()
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
