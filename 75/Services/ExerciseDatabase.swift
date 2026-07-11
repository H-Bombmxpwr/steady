import Foundation

/// One exercise from the bundled free-exercise-db extract (public domain,
/// 873 exercises). Loaded lazily like the food database.
struct Exercise: Codable, Identifiable, Hashable {
    let n: String          // name
    let c: String          // category: strength, cardio, stretching, …
    let m: [String]        // primary muscles
    let e: String?         // equipment
    let l: String?         // level
    let i: [String]        // instructions

    var id: String { n }
    var name: String { n }
    var muscles: String { m.map(\.capitalized).joined(separator: ", ") }

    var detail: String {
        var parts = [m.first?.capitalized ?? c.capitalized]
        if let e, e != "body only" { parts.append(e.capitalized) }
        else if e == "body only" { parts.append("Bodyweight") }
        if let l { parts.append(l.capitalized) }
        return parts.joined(separator: " · ")
    }
}

final class ExerciseDatabase {
    static let shared = ExerciseDatabase()

    private var _exercises: [Exercise]?
    private let lock = NSLock()

    var exercises: [Exercise] {
        lock.lock(); defer { lock.unlock() }
        if let e = _exercises { return e }
        let loaded = Self.load()
        _exercises = loaded
        return loaded
    }

    private static func load() -> [Exercise] {
        guard let url = Bundle.main.url(forResource: "Exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([Exercise].self, from: data) else {
            return []
        }
        return items
    }

    var muscleGroups: [String] {
        Array(Set(exercises.flatMap { $0.m })).sorted()
    }

    func byName(_ name: String) -> Exercise? {
        exercises.first { $0.n == name }
    }

    /// Search by name; optionally filter to a muscle group. Exact word
    /// matches and shorter names rank first (same idea as the food search).
    func search(_ query: String, muscle: String? = nil, limit: Int = 80) -> [Exercise] {
        let tokens = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        var pool = exercises
        if let muscle {
            pool = pool.filter { $0.m.contains(muscle) }
        }
        guard !tokens.isEmpty else {
            return Array(pool.sorted { $0.n < $1.n }.prefix(limit))
        }

        var scored: [(Exercise, Int)] = []
        for item in pool {
            let name = item.n.lowercased()
            guard tokens.allSatisfy({ name.contains($0) }) else { continue }
            var score = 0
            let words = name.split(whereSeparator: { !$0.isLetter }).map(String.init)
            for token in tokens where words.contains(token) || words.contains(token + "s") {
                score -= 10_000
            }
            score += name.count
            scored.append((item, score))
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map { $0.0 }
    }
}

// MARK: - Templates

/// Proven starting programs, seeded as editable presets. Exercise names
/// match the bundled database so instructions and history link up.
enum WorkoutTemplates {

    struct TemplateExercise {
        let name: String
        let sets: Int
        let reps: Int
    }

    struct Template: Identifiable {
        let name: String
        let summary: String
        let category: WorkoutCategory
        let minutes: Int
        let exercises: [TemplateExercise]
        var id: String { name }
    }

    struct Program: Identifiable {
        let name: String
        let summary: String
        let workouts: [Template]
        var id: String { name }
    }

    static let programs: [Program] = [
        Program(name: "StrongLifts 5×5",
                summary: "Two alternating full-body barbell days, 3×/week. Add 5 lb when you complete all sets.",
                workouts: [
                    Template(name: "5×5 Workout A",
                             summary: "Squat · Bench · Row",
                             category: .strength, minutes: 60,
                             exercises: [
                                TemplateExercise(name: "Barbell Squat", sets: 5, reps: 5),
                                TemplateExercise(name: "Barbell Bench Press - Medium Grip", sets: 5, reps: 5),
                                TemplateExercise(name: "Bent Over Barbell Row", sets: 5, reps: 5)
                             ]),
                    Template(name: "5×5 Workout B",
                             summary: "Squat · Press · Deadlift",
                             category: .strength, minutes: 60,
                             exercises: [
                                TemplateExercise(name: "Barbell Squat", sets: 5, reps: 5),
                                TemplateExercise(name: "Standing Military Press", sets: 5, reps: 5),
                                TemplateExercise(name: "Barbell Deadlift", sets: 1, reps: 5)
                             ])
                ]),
        Program(name: "Push / Pull / Legs",
                summary: "The classic 3-day split — run it 3–6 days a week.",
                workouts: [
                    Template(name: "Push Day",
                             summary: "Chest, shoulders, triceps",
                             category: .strength, minutes: 60,
                             exercises: [
                                TemplateExercise(name: "Barbell Bench Press - Medium Grip", sets: 4, reps: 8),
                                TemplateExercise(name: "Barbell Shoulder Press", sets: 3, reps: 10),
                                TemplateExercise(name: "Dips - Triceps Version", sets: 3, reps: 10),
                                TemplateExercise(name: "Triceps Pushdown", sets: 3, reps: 12)
                             ]),
                    Template(name: "Pull Day",
                             summary: "Back and biceps",
                             category: .strength, minutes: 60,
                             exercises: [
                                TemplateExercise(name: "Barbell Deadlift", sets: 3, reps: 5),
                                TemplateExercise(name: "Pullups", sets: 3, reps: 8),
                                TemplateExercise(name: "Bent Over Barbell Row", sets: 3, reps: 10),
                                TemplateExercise(name: "Barbell Curl", sets: 3, reps: 12)
                             ]),
                    Template(name: "Leg Day",
                             summary: "Quads, hamstrings, calves",
                             category: .strength, minutes: 60,
                             exercises: [
                                TemplateExercise(name: "Barbell Squat", sets: 4, reps: 8),
                                TemplateExercise(name: "Romanian Deadlift", sets: 3, reps: 10),
                                TemplateExercise(name: "Leg Press", sets: 3, reps: 12),
                                TemplateExercise(name: "Standing Calf Raises", sets: 3, reps: 15)
                             ])
                ]),
        Program(name: "Couch to 5K",
                summary: "Run/walk intervals 3×/week — start with week 1 and stretch the run segments as it gets easy.",
                workouts: [
                    Template(name: "C25K Run/Walk",
                             summary: "5 min warm-up walk, then alternate 60 s jogging / 90 s walking for 20 min",
                             category: .cardio, minutes: 30,
                             exercises: [
                                TemplateExercise(name: "Walking, Treadmill", sets: 1, reps: 1),
                                TemplateExercise(name: "Jogging, Treadmill", sets: 8, reps: 1)
                             ])
                ])
    ]

    /// Copies a template into the plan as an editable preset.
    @discardableResult
    static func apply(_ template: Template, to plan: Plan) -> WorkoutPreset {
        let preset = WorkoutPreset(name: template.name,
                                   defaultMinutes: template.minutes,
                                   category: template.category,
                                   notes: template.summary)
        for (index, ex) in template.exercises.enumerated() {
            preset.exercises.append(PresetExercise(name: ex.name, orderIndex: index,
                                                   sets: ex.sets, reps: ex.reps))
        }
        plan.presets.append(preset)
        return preset
    }
}
