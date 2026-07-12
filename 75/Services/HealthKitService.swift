import Foundation
import HealthKit

/// Two-way Apple Health sync — this is also the Garmin/Watch bridge, since
/// those devices write to Health and we read from it.
///
/// Writes (replacing this app's earlier samples for the day, so edits don't
/// double-count): weight, water, dietary energy, protein, workouts.
/// Reads: weight from other sources (scale/Garmin), daily steps, sleep.
final class HealthKitService {
    static let shared = HealthKitService()
    private let store = HKHealthStore()

    static let enabledKey = "health.sync"
    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private var weightType: HKQuantityType { HKQuantityType(.bodyMass) }
    private var waterType: HKQuantityType { HKQuantityType(.dietaryWater) }
    private var energyType: HKQuantityType { HKQuantityType(.dietaryEnergyConsumed) }
    private var proteinType: HKQuantityType { HKQuantityType(.dietaryProtein) }
    private var stepsType: HKQuantityType { HKQuantityType(.stepCount) }
    private var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let toWrite: Set<HKSampleType> = [weightType, waterType, energyType, proteinType,
                                          HKObjectType.workoutType()]
        let toRead: Set<HKObjectType> = [weightType, stepsType, sleepType,
                                         HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: toWrite, read: toRead)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Write (day totals, replace-then-save)

    /// Push a day's logged totals to Health, replacing whatever this app
    /// wrote for that day earlier.
    func syncDay(_ day: DayLog) async {
        guard isEnabled, HKHealthStore.isHealthDataAvailable() else { return }
        let dayStart = Calendar.current.startOfDay(for: day.date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        // Samples land mid-day so they sort naturally among other sources.
        let sampleDate = min(Date(), Calendar.current.date(byAdding: .hour, value: 12, to: dayStart)!)

        for type in [weightType, waterType, energyType, proteinType] {
            await deleteOwnSamples(of: type, from: dayStart, to: dayEnd)
        }

        var samples: [HKQuantitySample] = []
        if let w = day.weight {
            samples.append(HKQuantitySample(
                type: weightType,
                quantity: HKQuantity(unit: .pound(), doubleValue: w),
                start: sampleDate, end: sampleDate))
        }
        if day.waterOunces > 0 {
            samples.append(HKQuantitySample(
                type: waterType,
                quantity: HKQuantity(unit: .fluidOunceUS(), doubleValue: Double(day.waterOunces)),
                start: sampleDate, end: sampleDate))
        }
        if day.totalCalories > 0 {
            samples.append(HKQuantitySample(
                type: energyType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: Double(day.totalCalories)),
                start: sampleDate, end: sampleDate))
        }
        if day.totalProtein > 0 {
            samples.append(HKQuantitySample(
                type: proteinType,
                quantity: HKQuantity(unit: .gram(), doubleValue: Double(day.totalProtein)),
                start: sampleDate, end: sampleDate))
        }
        if !samples.isEmpty {
            try? await store.save(samples)
        }
    }

    /// Log a workout to Health at the moment it's recorded in the app.
    func saveWorkout(_ log: WorkoutLog, on date: Date) async {
        guard isEnabled, HKHealthStore.isHealthDataAvailable() else { return }
        let activity: HKWorkoutActivityType
        switch log.category {
        case .cardio: activity = .running
        case .strength: activity = .traditionalStrengthTraining
        case .mobility: activity = .flexibility
        case .sports: activity = .crossTraining
        case .other: activity = .other
        }
        let start = min(Date(), Calendar.current.date(
            byAdding: .hour, value: 12, to: Calendar.current.startOfDay(for: date))!)
        let end = start.addingTimeInterval(TimeInterval(log.minutes * 60))

        let config = HKWorkoutConfiguration()
        config.activityType = activity
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            try await builder.finishWorkout()
        } catch { /* Health write is best-effort */ }
    }

    private func deleteOwnSamples(of type: HKSampleType, from: Date, to: Date) async {
        let datePredicate = HKQuery.predicateForSamples(withStart: from, end: to)
        let sourcePredicate = HKQuery.predicateForObjects(from: HKSource.default())
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, sourcePredicate])
        let samples: [HKSample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: results ?? [])
            }
            store.execute(q)
        }
        if !samples.isEmpty {
            try? await store.delete(samples)
        }
    }

    // MARK: - Read

    /// Daily step counts for the last `days` days, keyed by start-of-day.
    func dailySteps(days: Int) async -> [Date: Int] {
        guard isEnabled, HKHealthStore.isHealthDataAvailable() else { return [:] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end))!
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: stepsType,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum,
                anchorDate: cal.startOfDay(for: end),
                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, collection, _ in
                var out: [Date: Int] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let sum = stat.sumQuantity() {
                        out[stat.startDate] = Int(sum.doubleValue(for: .count()))
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Hours asleep per night (asleep stages only), keyed by the wake-up day.
    func nightlySleepHours(days: Int) async -> [Date: Double] {
        guard isEnabled, HKHealthStore.isHealthDataAvailable() else { return [:] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end))!
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: sleepType,
                                  predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        var out: [Date: Double] = [:]
        for s in samples {
            guard HKCategoryValueSleepAnalysis.allAsleepValues
                .contains(HKCategoryValueSleepAnalysis(rawValue: s.value) ?? .inBed) else { continue }
            let day = cal.startOfDay(for: s.endDate)
            out[day, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        return out
    }

    /// Weight samples written by other apps/devices (scale, Garmin, Watch),
    /// keyed by day — used to auto-fill days the user didn't weigh in-app.
    func externalWeights(days: Int) async -> [Date: Double] {
        guard isEnabled, HKHealthStore.isHealthDataAvailable() else { return [:] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end))!
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let notMine = NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(from: HKSource.default()))
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, notMine])
        let samples: [HKQuantitySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: weightType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, _ in
                cont.resume(returning: (results as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
        var out: [Date: Double] = [:]
        for s in samples {
            out[cal.startOfDay(for: s.startDate)] = s.quantity.doubleValue(for: .pound())
        }
        return out
    }

    /// Pull external weights into the plan (fills days with no in-app weigh-in).
    func importExternalWeights(into plan: Plan) async -> Int {
        let weights = await externalWeights(days: 90)
        var imported = 0
        for (date, lbs) in weights {
            guard date >= plan.startDate else { continue }
            let day = ensureDay(plan: plan, date: date)
            if day.weight == nil {
                day.weight = (lbs * 10).rounded() / 10
                imported += 1
            }
        }
        return imported
    }

    // MARK: - Workout import (Apple Watch / Garmin via Health)

    /// Workouts recorded by other apps and devices — Apple Watch, Garmin
    /// Connect, Strava all land in Health and flow in here.
    private func externalWorkouts(days: Int) async -> [HKWorkout] {
        guard isEnabled, HKHealthStore.isHealthDataAvailable() else { return [] }
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: end))!
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let notMine = NSCompoundPredicate(notPredicateWithSubpredicate:
            HKQuery.predicateForObjects(from: HKSource.default()))
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [datePredicate, notMine])
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, _ in
                cont.resume(returning: (results as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    /// Import external workouts as WorkoutLogs so watch runs and Garmin
    /// rides count toward workout minutes and the streak without retyping.
    /// Each Health workout imports once (UUID remembered on the log).
    func importExternalWorkouts(into plan: Plan) async -> Int {
        let workouts = await externalWorkouts(days: 90)
        guard !workouts.isEmpty else { return 0 }
        var known = Set(plan.days.flatMap { $0.workouts.compactMap(\.healthKitID) })
        var imported = 0
        for w in workouts {
            let id = w.uuid.uuidString
            guard !known.contains(id), w.startDate >= plan.startDate else { continue }
            let minutes = Int((w.duration / 60).rounded())
            guard minutes >= 1 else { continue }

            let log = WorkoutLog(name: Self.workoutName(w),
                                 minutes: minutes,
                                 outdoor: (w.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) == false,
                                 category: Self.category(for: w.workoutActivityType))
            log.healthKitID = id
            log.createdAt = w.startDate
            ensureDay(plan: plan, date: w.startDate).workouts.append(log)
            known.insert(id)
            imported += 1
        }
        if imported > 0 { try? plan.modelContext?.save() }
        return imported
    }

    /// "Running · Garmin Connect" — activity plus where it came from.
    private static func workoutName(_ w: HKWorkout) -> String {
        let source = w.sourceRevision.source.name
        let activity = activityLabel(w.workoutActivityType)
        return source.isEmpty ? activity : "\(activity) · \(source)"
    }

    private static func category(for type: HKWorkoutActivityType) -> WorkoutCategory {
        switch type {
        case .running, .walking, .cycling, .hiking, .swimming, .elliptical,
             .rowing, .stairClimbing, .stairs, .highIntensityIntervalTraining,
             .jumpRope, .crossCountrySkiing, .mixedCardio:
            return .cardio
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining:
            return .strength
        case .yoga, .flexibility, .pilates, .cooldown, .taiChi, .mindAndBody:
            return .mobility
        case .basketball, .soccer, .tennis, .golf, .baseball, .softball,
             .volleyball, .pickleball, .racquetball, .badminton, .hockey,
             .lacrosse, .rugby, .americanFootball, .tableTennis, .squash,
             .martialArts, .boxing, .kickboxing, .climbing, .surfingSports,
             .paddleSports, .snowboarding, .downhillSkiing, .skatingSports:
            return .sports
        default:
            return .other
        }
    }

    private static func activityLabel(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .walking: return "Walking"
        case .cycling: return "Cycling"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing, .stairs: return "Stairs"
        case .highIntensityIntervalTraining: return "HIIT"
        case .jumpRope: return "Jump Rope"
        case .mixedCardio: return "Cardio"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .coreTraining: return "Core"
        case .yoga: return "Yoga"
        case .flexibility, .cooldown: return "Stretching"
        case .pilates: return "Pilates"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        case .golf: return "Golf"
        case .pickleball: return "Pickleball"
        case .martialArts: return "Martial Arts"
        case .boxing: return "Boxing"
        case .climbing: return "Climbing"
        case .snowboarding: return "Snowboarding"
        case .downhillSkiing: return "Skiing"
        default: return "Workout"
        }
    }
}
