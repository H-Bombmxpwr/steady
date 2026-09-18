import Foundation
import SwiftData

@Model
final class Plan {
    var createdAt: Date
    var startDate: Date
    var startingWeight: Double        // lb
    var goalWeight: Double            // lb
    var paceLbsPerWeek: Double        // target loss rate
    var waterGoalOunces: Int
    var waterStepOunces: Int
    var proteinTargetGrams: Int
    var calorieBudgetOverride: Int?   // nil = use computed budget
    /// Strict = the streak needs the day's goals met (75% of checks);
    /// relaxed (default) = showing up and logging anything keeps it alive.
    var strictStreak: Bool = false
    /// Adaptive budget: once there's enough logged history, the TDEE is
    /// learned from actual intake vs the weight trend instead of relying on
    /// the Mifflin-St Jeor formula alone (Settings → Daily Targets).
    var adaptiveBudget: Bool = true
    /// Training-day fueling: on days with a scheduled workout, add the
    /// session's estimated burn to that day's calorie budget and surface
    /// carb/fluid fueling guidance (Settings → Daily Targets).
    var fuelTrainingDays: Bool = true

    // MARK: Athlete mode (all additive, all defaulted for clean migration)

    /// The private iCalendar feed from TrainingPeaks → Settings → Calendar
    /// Sync. Empty until connected.
    var trainingPeaksFeedURL: String?
    var trainingPeaksLastSync: Date?
    /// Fold local heat and humidity into the hydration and sodium guidance.
    var weatherAwareFueling: Bool = true
    /// Athlete mode: eat at maintenance plus training rather than in a
    /// deficit. Turning this off lets an athlete run a deliberate (small)
    /// deficit for a body-composition block using `paceLbsPerWeek`.
    var eatAtMaintenance: Bool = true

    // MARK: Food preferences

    /// Where this person actually shops. Suggestions that name a store are
    /// only useful if it's a store they can get to — "grab the rotisserie
    /// chicken at Costco" is worthless advice to someone who shops at Aldi.
    var preferredStores: [String] = []
    /// Foods to never suggest. Dislikes, allergies, "I'm not eating that" —
    /// the app doesn't need to know which, only that it's off the table.
    var dislikedFoods: [String] = []
    /// Athlete protein at 1 g per pound of bodyweight rather than the
    /// load-based g/kg bands. On by default in athlete mode.
    var proteinPerPoundTarget: Bool = true

    /// How long before a session you want to have finished a normal-sized
    /// meal, in minutes. Snacks and big meals scale from it.
    ///
    /// Personal, not universal: two hours is the common recommendation, but
    /// plenty of people train fine on an hour and some need three. It's the
    /// number that decides where every pre-session meal lands, so it's the
    /// one worth letting people set. The *post*-session window deliberately
    /// isn't settable — see `MealPlanEngine.recoveryWindow`.
    var preSessionLeadMinutes: Int = 120

    @Relationship(deleteRule: .cascade) var days: [DayLog]
    @Relationship(deleteRule: .cascade) var presets: [WorkoutPreset]
    @Relationship(deleteRule: .cascade) var schedule: [WorkoutScheduleEntry]
    @Relationship(deleteRule: .cascade) var supplements: [Supplement]
    @Relationship(deleteRule: .cascade) var measurements: [MeasurementLog]
    @Relationship(deleteRule: .cascade) var labs: [LabResult] = []
    @Relationship(deleteRule: .cascade) var plannedWorkouts: [PlannedWorkout] = []
    @Relationship(deleteRule: .cascade) var sweatTests: [SweatTest] = []
    @Relationship(deleteRule: .cascade) var cycles: [CycleEntry] = []
    @Relationship(deleteRule: .cascade) var mealSlots: [MealSlot] = []

    init(startDate: Date,
         startingWeight: Double,
         goalWeight: Double,
         paceLbsPerWeek: Double,
         waterGoalOunces: Int = 96,
         waterStepOunces: Int = 8,
         proteinTargetGrams: Int) {
        self.createdAt = Date()
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.startingWeight = startingWeight
        self.goalWeight = goalWeight
        self.paceLbsPerWeek = paceLbsPerWeek
        self.waterGoalOunces = waterGoalOunces
        self.waterStepOunces = max(1, waterStepOunces)
        self.proteinTargetGrams = proteinTargetGrams
        self.calorieBudgetOverride = nil
        self.days = []
        self.presets = []
        self.schedule = []
        self.supplements = []
        self.measurements = []
    }

    /// Most recent logged weight, falling back to the starting weight.
    var currentWeight: Double {
        let logged = days
            .filter { $0.weight != nil }
            .sorted { $0.date < $1.date }
            .last?.weight
        return logged ?? startingWeight
    }

    var weightChange: Double { currentWeight - startingWeight }

    /// Estimated date the goal weight is reached at the chosen pace.
    var projectedGoalDate: Date? {
        guard paceLbsPerWeek > 0, currentWeight > goalWeight else { return nil }
        let weeks = (currentWeight - goalWeight) / paceLbsPerWeek
        return Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: Date())
    }

    /// Is any training planned for this date — from a dated plan or from the
    /// recurring weekly schedule? Drives whether a workout counts against the
    /// day's goals, so it has to see an imported plan too.
    func isWorkoutScheduled(on date: Date) -> Bool {
        !sessions(on: date).isEmpty
    }

    func scheduledWorkouts(on date: Date) -> [WorkoutScheduleEntry] {
        let weekday = Calendar.current.component(.weekday, from: date)
        return schedule.filter { $0.weekday == weekday }
    }

    // MARK: - Sessions

    func plannedWorkouts(on date: Date) -> [PlannedWorkout] {
        let day = Calendar.current.startOfDay(for: date)
        return plannedWorkouts
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    /// Everything planned for a date, from whichever source has it.
    ///
    /// A dated plan wins outright over the recurring weekday slot: once
    /// TrainingPeaks says Tuesday is a rest day, the standing "Tuesday: Gym,
    /// 45 min" entry must not keep adding phantom calories to the budget.
    /// Only when no dated session exists does the weekly schedule stand in.
    /// Filtered by what's actually still happening. Everything downstream —
    /// the calorie budget, the carb target, the fueling, the widgets — reads
    /// this, so calling a session off here makes the whole day follow without
    /// a single other call site changing.
    func sessions(on date: Date) -> [TrainingSession] {
        let all = allSessions(on: date)
        guard let day = dayLog(on: date), !day.skippedWorkoutsRaw.isEmpty else { return all }
        return all.filter { !day.isWorkoutSkipped($0.skipKey) }
    }

    /// Everything on the books for a date, called off or not. Only the day
    /// plan wants this — it still draws a skipped session, greyed out, so
    /// there's something to tap to put it back.
    func allSessions(on date: Date) -> [TrainingSession] {
        let dated = plannedWorkouts(on: date)
        if !dated.isEmpty { return dated.map(TrainingSession.init) }
        return scheduledWorkouts(on: date).map(TrainingSession.init)
    }

    func dayLog(on date: Date) -> DayLog? {
        days.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// True once any dated plan exists at all — the signal that this person
    /// drives their week from a training plan rather than a weekly habit grid.
    var usesDatedPlan: Bool { !plannedWorkouts.isEmpty }

    var trainingPeaksConnected: Bool {
        !(trainingPeaksFeedURL ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Meal schedule

    /// The day's shape, in clock order. Seeded on first read so a plan made
    /// before meal planning existed gets the standard three-meals-plus-snacks
    /// schedule rather than an empty day.
    var orderedMealSlots: [MealSlot] {
        mealSlots.sorted { ($0.minutesOfDay, $0.orderIndex) < ($1.minutesOfDay, $1.orderIndex) }
    }

    /// Slots that are actually part of the day.
    var activeMealSlots: [MealSlot] { orderedMealSlots.filter(\.enabled) }

    /// Install the default schedule if this plan has none. Idempotent, so it's
    /// safe to call on every launch and from any screen that needs a schedule.
    @discardableResult
    func ensureMealSchedule() -> [MealSlot] {
        if !mealSlots.isEmpty { return orderedMealSlots }
        let defaults = MealSlot.defaultSchedule()
        mealSlots.append(contentsOf: defaults)
        try? modelContext?.save()
        return orderedMealSlots
    }

    func mealSlot(for meal: Meal) -> MealSlot? {
        mealSlots.first { $0.meal == meal }
    }

    /// The learned sweat profile, or nil until a plausible test exists.
    func sweatProfile(matching category: WorkoutCategory? = nil,
                      intensity: WorkoutIntensity? = nil) -> SweatProfile? {
        let salt = SaltLoss(rawValue: UserDefaults.standard.string(forKey: SaltLoss.storageKey) ?? "")
            ?? .typical
        return SweatEngine.profile(tests: sweatTests, saltLoss: salt,
                                   matching: category, intensity: intensity)
    }
}

enum WorkoutCategory: String, Codable, CaseIterable, Identifiable {
    case cardio, strength, mobility, sports, other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cardio: return "Cardio"
        case .strength: return "Strength"
        case .mobility: return "Mobility"
        case .sports: return "Sports"
        case .other: return "Other"
        }
    }
    var icon: String {
        switch self {
        case .cardio: return "figure.run"
        case .strength: return "dumbbell.fill"
        case .mobility: return "figure.cooldown"
        case .sports: return "sportscourt.fill"
        case .other: return "figure.mixed.cardio"
        }
    }

    /// Metabolic equivalent for a moderate effort of this type — the energy
    /// cost, and therefore the heat produced, relative to sitting still.
    /// Drives both the calorie burn estimate and how a measured sweat rate is
    /// rescaled between session types.
    var metEstimate: Double {
        switch self {
        case .cardio:   return 8.5
        case .sports:   return 7.5
        case .strength: return 5.0
        case .mobility: return 2.8
        case .other:    return 6.0
        }
    }
}

@Model
final class WorkoutPreset {
    var name: String
    var defaultMinutes: Int
    var outdoor: Bool
    var categoryRaw: String = WorkoutCategory.other.rawValue
    var notes: String?
    /// When this workout was built — shown to tell same-named workouts
    /// apart in the library and picker. Additive default for old rows.
    var createdAt: Date = Date()
    @Relationship(deleteRule: .cascade) var exercises: [PresetExercise] = []

    init(name: String, defaultMinutes: Int = 45, outdoor: Bool = false,
         category: WorkoutCategory = .other, notes: String? = nil) {
        self.name = name
        self.defaultMinutes = defaultMinutes
        self.outdoor = outdoor
        self.categoryRaw = category.rawValue
        self.notes = notes
        self.createdAt = Date()
        self.exercises = []
    }

    var category: WorkoutCategory {
        get { WorkoutCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var orderedExercises: [PresetExercise] {
        exercises.sorted { $0.orderIndex < $1.orderIndex }
    }
}

/// One exercise inside a workout preset, with target sets × reps (× weight).
/// Names match the bundled exercise database so history links up.
@Model
final class PresetExercise {
    var name: String
    var orderIndex: Int = 0
    var sets: Int = 3
    var reps: Int = 10
    var weightLbs: Double?            // nil = bodyweight / cardio / not set yet

    init(name: String, orderIndex: Int = 0, sets: Int = 3, reps: Int = 10, weightLbs: Double? = nil) {
        self.name = name
        self.orderIndex = orderIndex
        self.sets = sets
        self.reps = reps
        self.weightLbs = weightLbs
    }

    var targetText: String {
        var text = "\(sets)×\(reps)"
        if let w = weightLbs, w > 0 { text += " @ \(w.formatted()) lb" }
        return text
    }
}

/// A dated set of body measurements (all inches, all optional).
@Model
final class MeasurementLog {
    var date: Date
    var waist: Double?
    var hips: Double?
    var chest: Double?
    var arm: Double?
    var thigh: Double?

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    var isEmpty: Bool {
        waist == nil && hips == nil && chest == nil && arm == nil && thigh == nil
    }
}

/// A dated lab panel (mg/dL except A1C, which is %). All optional — log
/// whatever the report had. Numbers only; nothing identifying is stored
/// beyond the date, and values are used off-device only when lab-aware
/// coaching is switched on.
@Model
final class LabResult {
    var date: Date
    var ldl: Double?
    var hdl: Double?
    var triglycerides: Double?
    var fastingGlucose: Double?
    var a1c: Double?

    // Iron status. Additive and defaulted, so panels logged before these
    // existed stay valid — they just don't say anything about iron.

    /// Ferritin, ng/mL. The body's iron stores, and the marker that moves
    /// first: it falls long before hemoglobin does, which is why an athlete
    /// can feel flattened with a "normal" blood count.
    var ferritin: Double?
    /// Hemoglobin, g/dL — the oxygen-carrying end of it.
    var hemoglobin: Double?
    /// Transferrin saturation, %. Optional third marker; when it's present it
    /// separates true iron deficiency from ferritin raised by inflammation.
    var transferrinSaturation: Double?

    init(date: Date) {
        self.date = Calendar.current.startOfDay(for: date)
    }

    var isEmpty: Bool {
        ldl == nil && hdl == nil && triglycerides == nil
            && fastingGlucose == nil && a1c == nil
            && ferritin == nil && hemoglobin == nil && transferrinSaturation == nil
    }

    /// Does this panel say anything about iron at all?
    var hasIronMarkers: Bool {
        ferritin != nil || hemoglobin != nil || transferrinSaturation != nil
    }
}

extension Plan {
    /// Most recent non-empty lab panel.
    var latestLabs: LabResult? {
        labs.filter { !$0.isEmpty }.sorted { $0.date < $1.date }.last
    }

    /// Most recent panel that actually measured iron. Separate from
    /// `latestLabs` because a lipid panel logged last week shouldn't hide the
    /// ferritin number from three months ago — iron moves slowly, and the
    /// older reading is still the best one available.
    var latestIronLabs: LabResult? {
        labs.filter(\.hasIronMarkers).sorted { $0.date < $1.date }.last
    }
}

/// How hard a session is — drives fueling (carbs/fluid) and the burn
/// estimate. Kept coarse on purpose; most people can place a session in one
/// of three buckets without a power meter.
enum WorkoutIntensity: String, Codable, CaseIterable, Identifiable {
    case easy, moderate, hard

    var id: String { rawValue }
    var label: String {
        switch self {
        case .easy: return "Easy"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        }
    }
    /// Conversational anchor shown under the picker.
    var cue: String {
        switch self {
        case .easy: return "Zone 2, can hold a conversation"
        case .moderate: return "Steady, breathing up, short sentences"
        case .hard: return "Threshold or intervals, hard to talk"
        }
    }
    /// Multiplier applied to the MET burn estimate.
    var burnFactor: Double {
        switch self {
        case .easy: return 0.85
        case .moderate: return 1.0
        case .hard: return 1.2
        }
    }
}

/// One planned workout slot per weekday (weekday: 1 = Sunday … 7 = Saturday).
@Model
final class WorkoutScheduleEntry {
    var weekday: Int
    var name: String
    var minutes: Int
    var hour: Int                     // planned start time (for reminders/calendar)
    var minute: Int
    var calendarEventID: String?      // EventKit identifier once synced
    // Additive (defaulted) so existing schedules migrate cleanly. Together
    // they drive the fueling engine — endurance vs strength, and how hard.
    var categoryRaw: String = WorkoutCategory.cardio.rawValue
    var intensityRaw: String = WorkoutIntensity.moderate.rawValue

    init(weekday: Int, name: String, minutes: Int = 45, hour: Int = 7, minute: Int = 0,
         category: WorkoutCategory = .cardio, intensity: WorkoutIntensity = .moderate) {
        self.weekday = weekday
        self.name = name
        self.minutes = minutes
        self.hour = hour
        self.minute = minute
        self.calendarEventID = nil
        self.categoryRaw = category.rawValue
        self.intensityRaw = intensity.rawValue
    }

    var category: WorkoutCategory {
        get { WorkoutCategory(rawValue: categoryRaw) ?? .cardio }
        set { categoryRaw = newValue.rawValue }
    }
    var intensity: WorkoutIntensity {
        get { WorkoutIntensity(rawValue: intensityRaw) ?? .moderate }
        set { intensityRaw = newValue.rawValue }
    }

    var weekdayName: String {
        Calendar.current.weekdaySymbols[max(0, min(6, weekday - 1))]
    }

    var timeString: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

@Model
final class Supplement {
    var name: String
    var hour: Int                     // reminder time
    var minute: Int
    var remind: Bool
    var frequencyRaw: String = Frequency.daily.rawValue   // "daily" | "weekly"
    var weekday: Int = 2              // 1–7, used when weekly
    var createdAt: Date

    init(name: String, hour: Int = 8, minute: Int = 0, remind: Bool = true,
         frequency: Frequency = .daily, weekday: Int = 2) {
        self.name = name
        self.hour = hour
        self.minute = minute
        self.remind = remind
        self.frequencyRaw = frequency.rawValue
        self.weekday = weekday
        self.createdAt = Date()
    }

    enum Frequency: String, Codable, CaseIterable, Identifiable {
        case daily, weekly
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var frequency: Frequency {
        get { Frequency(rawValue: frequencyRaw) ?? .daily }
        set { frequencyRaw = newValue.rawValue }
    }

    /// Is this supplement due on the given date?
    func isDue(on date: Date) -> Bool {
        frequency == .daily || Calendar.current.component(.weekday, from: date) == weekday
    }

    var timeString: String {
        let comps = DateComponents(hour: hour, minute: minute)
        let date = Calendar.current.date(from: comps) ?? Date()
        let time = date.formatted(date: .omitted, time: .shortened)
        if frequency == .weekly {
            let day = Calendar.current.shortWeekdaySymbols[max(0, min(6, weekday - 1))]
            return "\(day) \(time)"
        }
        return time
    }
}
