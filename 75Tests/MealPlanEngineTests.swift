import XCTest
@testable import _5

/// The meal plan is arithmetic with no UI to check it against — a number that
/// is quietly 200 calories wrong looks exactly like one that's right. These
/// pin the parts that have to hold: the day adds up, workout fuel lands where
/// it's needed, and the reallocation rules do what the buttons promise.
final class MealPlanEngineTests: XCTestCase {

    // MARK: Fixtures

    private func profile(_ mode: AppMode = .athlete) -> UserProfile {
        UserProfile(birthDate: Calendar.current.date(byAdding: .year, value: -32, to: Date())!,
                    heightInches: 70, sex: .male, activityLevel: .moderate, mode: mode)
    }

    private func plan() -> Plan {
        let p = Plan(startDate: Date(), startingWeight: 170, goalWeight: 170,
                     paceLbsPerWeek: 0, proteinTargetGrams: 170)
        p.ensureMealSchedule()
        return p
    }

    /// Calories must equal 4C + 4P + 9F or the fixture is asking the engine to
    /// reconcile a contradiction, which it will — correctly — do.
    private func targets(protein: Int = 170, carbs: Int = 375, fat: Int = 83) -> DailyTargets {
        DailyTargets(calories: carbs * 4 + protein * 4 + fat * 9,
                     proteinGrams: protein, waterOunces: 96,
                     carbGrams: carbs, fatGrams: fat, trainingLoad: .moderate)
    }

    private func session(at hour: Int, minutes: Int = 90,
                         category: WorkoutCategory = .cardio,
                         intensity: WorkoutIntensity = .moderate) -> TrainingSession {
        TrainingSession(id: "s-\(hour)", name: "Intervals", minutes: minutes,
                        hour: hour, minute: 0, category: category, intensity: intensity)
    }

    private func fuel(for session: TrainingSession, weight: Double = 170) -> FuelingPlan {
        FuelingEngine.plan(for: session, bodyweightLbs: weight)
    }

    /// Noon on a fixed date, so "what has already passed" is never the clock.
    private var noon: Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    }

    private func build(day: DayLog,
                       plan p: Plan,
                       targets t: DailyTargets,
                       sessions: [TrainingSession] = [],
                       iron: IronCoach.Finding? = nil,
                       now: Date? = nil) -> MealPlanEngine.DayPlan {
        MealPlanEngine.plan(date: day.date, day: day, plan: p, profile: profile(),
                            targets: t, sessions: sessions,
                            fuels: sessions.map { fuel(for: $0) },
                            iron: iron, now: now ?? noon)
    }

    // MARK: - distribute: the primitive everything else rests on

    func testDistributeSplitsByWeight() {
        let result = MealPlanEngine.distribute(total: 100,
                                               weights: [1, 1, 2],
                                               floors: [0, 0, 0],
                                               ceilings: [100, 100, 100])
        XCTAssertEqual(result.allocation[0], 25, accuracy: 0.01)
        XCTAssertEqual(result.allocation[1], 25, accuracy: 0.01)
        XCTAssertEqual(result.allocation[2], 50, accuracy: 0.01)
        XCTAssertEqual(result.overflow, 0, accuracy: 0.01)
    }

    func testDistributeHonorsFloors() {
        let result = MealPlanEngine.distribute(total: 100,
                                               weights: [1, 1],
                                               floors: [60, 0],
                                               ceilings: [100, 100])
        XCTAssertGreaterThanOrEqual(result.allocation[0], 60)
        XCTAssertEqual(result.allocation.reduce(0, +), 100, accuracy: 0.01)
    }

    /// The case the whole ceiling mechanism exists for: what one slot can't
    /// take has to land on the others, not vanish.
    func testDistributeSpillsPastCeilings() {
        let result = MealPlanEngine.distribute(total: 100,
                                               weights: [1, 1],
                                               floors: [0, 0],
                                               ceilings: [20, 100])
        XCTAssertEqual(result.allocation[0], 20, accuracy: 0.01)
        XCTAssertEqual(result.allocation[1], 80, accuracy: 0.01)
        XCTAssertEqual(result.overflow, 0, accuracy: 0.01)
    }

    /// And when nothing has room, it's reported rather than forced in.
    func testDistributeReportsWhatWillNotFit() {
        let result = MealPlanEngine.distribute(total: 100,
                                               weights: [1, 1],
                                               floors: [0, 0],
                                               ceilings: [20, 20])
        XCTAssertEqual(result.allocation.reduce(0, +), 40, accuracy: 0.01)
        XCTAssertEqual(result.overflow, 60, accuracy: 0.01)
    }

    // MARK: - The day adds up

    func testMealsSumToTheDaysTargets() {
        let p = plan()
        let day = DayLog(date: noon)
        let t = targets()
        let result = build(day: day, plan: p, targets: t)

        let carbs = result.plannedMeals.reduce(0) { $0 + $1.carbGrams }
        let protein = result.plannedMeals.reduce(0) { $0 + $1.proteinGrams }
        let fat = result.plannedMeals.reduce(0) { $0 + $1.fatGrams }

        XCTAssertEqual(carbs, t.carbGrams!, accuracy: 3)
        XCTAssertEqual(protein, t.proteinGrams, accuracy: 3)
        XCTAssertEqual(fat, t.fatGrams!, accuracy: 3)
        XCTAssertEqual(result.plannedCalories, t.calories, accuracy: 40)
    }

    /// Weight-loss and general-health targets carry no carb/fat split. The
    /// plan still has to produce all four without inventing calories.
    func testDerivesMacrosWhenTheModeDoesNotPeriodizeThem() {
        let p = plan()
        let day = DayLog(date: noon)
        let t = DailyTargets(calories: 2000, proteinGrams: 150, waterOunces: 96)
        let result = build(day: day, plan: p, targets: t)

        XCTAssertFalse(result.plannedMeals.isEmpty)
        let protein = result.plannedMeals.reduce(0) { $0 + $1.proteinGrams }
        XCTAssertEqual(protein, 150, accuracy: 3)
        XCTAssertEqual(result.plannedCalories, 2000, accuracy: 60)
        XCTAssertTrue(result.plannedMeals.allSatisfy { $0.carbGrams > 0 && $0.fatGrams > 0 })
    }

    /// Carbs taken mid-session belong to the session. If they stayed in the
    /// meal pool the day would be over-fed by exactly that much.
    func testMidSessionCarbsComeOutOfTheMealPool() {
        let p = plan()
        let day = DayLog(date: noon)
        let t = targets()
        let long = session(at: 9, minutes: 180)
        let result = build(day: day, plan: p, targets: t, sessions: [long])

        XCTAssertGreaterThan(result.duringSessionCarbs, 0,
                             "a three-hour endurance session needs carbs during it")
        let mealCarbs = result.plannedMeals.reduce(0) { $0 + $1.carbGrams }
        XCTAssertEqual(mealCarbs + result.duringSessionCarbs, t.carbGrams!, accuracy: 4)
    }

    // MARK: - Workout-adjacent fuel

    func testPreAndPostSessionMealsAreIdentifiedAndFloored() {
        let p = plan()
        let day = DayLog(date: noon)
        // 12:30 lunch sits inside the pre-window for a 2pm session; the 6:30
        // dinner is outside the recovery window, so one gets synthesized.
        let afternoon = session(at: 14, minutes: 120)
        let result = build(day: day, plan: p, targets: targets(), sessions: [afternoon])

        guard let pre = result.meals.first(where: { $0.role == .preWorkout }) else {
            return XCTFail("no pre-session meal was identified")
        }
        guard let recovery = result.meals.first(where: { $0.role == .recovery }) else {
            return XCTFail("no recovery meal was identified")
        }

        let f = fuel(for: afternoon)
        XCTAssertGreaterThanOrEqual(pre.carbGrams, f.preCarbs - 1,
                                    "the pre-load is a floor, not a suggestion")
        XCTAssertGreaterThanOrEqual(recovery.proteinGrams, f.recoveryProtein - 1)
        XCTAssertLessThan(pre.minutesOfDay, 14 * 60)
        XCTAssertGreaterThanOrEqual(recovery.minutesOfDay, 16 * 60)
    }

    /// Fat before a session slows the stomach down. The pre-session meal has
    /// to be lighter in fat than an ordinary meal of similar size.
    func testPreSessionMealIsLowerInFat() {
        let p = plan()
        let day = DayLog(date: noon)
        let result = build(day: day, plan: p, targets: targets(), sessions: [session(at: 14)])

        guard let pre = result.meals.first(where: { $0.role == .preWorkout }),
              let ordinary = result.meals.first(where: { $0.role == .normal && !$0.skipped }) else {
            return XCTFail("expected both a pre-session and an ordinary meal")
        }
        let preFatShare = Double(pre.fatGrams) / Double(max(1, pre.calories))
        let ordinaryFatShare = Double(ordinary.fatGrams) / Double(max(1, ordinary.calories))
        XCTAssertLessThan(preFatShare, ordinaryFatShare)
    }

    /// A 6 a.m. session is before every scheduled meal. Rather than leave the
    /// pre-load homeless, the engine adds a slot for it.
    func testEarlySessionGetsASyntheticPreMeal() {
        let p = plan()
        let day = DayLog(date: noon)
        let dawn = session(at: 5, minutes: 120)
        let result = build(day: day, plan: p, targets: targets(), sessions: [dawn])

        let synthetic = result.meals.filter(\.isSynthetic)
        XCTAssertTrue(synthetic.contains { $0.minutesOfDay < 5 * 60 },
                      "nothing was scheduled before the session, so one had to be added")
    }

    // MARK: - Reallocation

    func testSkippingAMealMovesItsFoodToTheRest() {
        let p = plan()
        let day = DayLog(date: noon)
        // Before any skipping, so the comparison is like for like.
        let dinnerBefore = build(day: day, plan: p, targets: targets())
            .meals.first { $0.meal == .dinner }!

        day.setSkipped(.lunch, true)
        let after = build(day: day, plan: p, targets: targets())
        let dinnerAfter = after.meals.first { $0.meal == .dinner }!
        let lunchAfter = after.meals.first { $0.meal == .lunch }!

        XCTAssertTrue(lunchAfter.skipped)
        XCTAssertEqual(lunchAfter.calories, 0)
        XCTAssertGreaterThan(dinnerAfter.calories, dinnerBefore.calories)
        // And the day still adds up — reallocation, not deletion.
        let protein = after.plannedMeals.reduce(0) { $0 + $1.proteinGrams }
        XCTAssertEqual(protein, 170, accuracy: 4)
    }

    /// Skipping everything but one meal can't be made up. The plan is
    /// expected to cap the survivor and say so rather than print 3,000
    /// calories of dinner.
    func testUnmakeupableShortfallIsSaidOutLoudNotStuffedIntoOneMeal() {
        let p = plan()
        let day = DayLog(date: noon)
        day.setSkipped(.breakfast, true)
        day.setSkipped(.lunch, true)

        let result = build(day: day, plan: p, targets: targets())
        let dinner = result.meals.first { $0.meal == .dinner }!

        XCTAssertLessThan(dinner.calories, targets().calories,
                          "one meal should not silently absorb the entire day")
        XCTAssertFalse(result.advisories.isEmpty,
                       "the shortfall has to be stated, not hidden")
    }

    func testBigMealTakesTheLargestShare() {
        let p = plan()
        let day = DayLog(date: noon)
        day.setBigMeal(.breakfast)

        let result = build(day: day, plan: p, targets: targets())
        let breakfast = result.meals.first { $0.meal == .breakfast }!
        XCTAssertTrue(breakfast.isBig)
        let others = result.plannedMeals.filter { $0.meal != .breakfast }
        XCTAssertTrue(others.allSatisfy { $0.calories <= breakfast.calories },
                      "the meal being planned around should be the biggest one")
    }

    /// Marking a skipped meal as the big one is contradictory; the later
    /// instruction wins and the earlier one is cleared.
    func testBigMealAndSkippedAreMutuallyExclusive() {
        let day = DayLog(date: noon)
        day.setSkipped(.dinner, true)
        day.setBigMeal(.dinner)
        XCTAssertFalse(day.isSkipped(.dinner))

        day.setSkipped(.dinner, true)
        XCTAssertNil(day.bigMeal)
    }

    /// Waking at one o'clock doesn't mean eating one meal. The meals move
    /// into the hours that are left rather than being deleted.
    func testLateStartCompressesTheDayRatherThanDeletingMeals() {
        let p = plan()
        let day = DayLog(date: noon)
        day.setWake(hour: 13, minute: 0)

        let result = build(day: day, plan: p, targets: targets())
        XCTAssertFalse(result.plannedMeals.isEmpty)
        XCTAssertTrue(result.plannedMeals.allSatisfy { $0.minutesOfDay >= 13 * 60 },
                      "nothing should be scheduled before they were awake")
        XCTAssertGreaterThan(result.plannedMeals.count, 1,
                             "a whole day's food should not land on one sitting")
        XCTAssertEqual(result.plannedCalories, targets().calories, accuracy: 60,
                       "the day's food moves into the hours that are left")
    }

    /// Waking after every scheduled meal still has to produce something
    /// edible rather than an empty plan.
    func testWakingAfterEveryMealStillLeavesAPlan() {
        let p = plan()
        let day = DayLog(date: noon)
        day.setWake(hour: 22, minute: 0)

        let result = build(day: day, plan: p, targets: targets())
        XCTAssertFalse(result.plannedMeals.isEmpty)
    }

    /// The quiet half of "reallocate everything": a meal already eaten is a
    /// fact, and what's ahead adjusts around it in both directions.
    func testAlreadyEatenMealsAreLockedAndTheRestReplansAroundThem() {
        let p = plan()
        let day = DayLog(date: noon)
        // A 1,400-calorie breakfast, logged, with lunch and dinner still ahead.
        let big = FoodLog(name: "Diner breakfast", calories: 1400, proteinGrams: 40,
                          meal: .breakfast,
                          facts: NutritionFacts(carbsGrams: 140, fatGrams: 60))
        day.foods.append(big)

        let result = build(day: day, plan: p, targets: targets(), now: noon)
        let breakfast = result.meals.first { $0.meal == .breakfast }!
        XCTAssertTrue(breakfast.isLocked)
        // 1,400 on the label, but its macros only account for 1,260 — exactly
        // the mismatch real logged food produces. The label is what's trusted.
        XCTAssertEqual(breakfast.calories, 1400, accuracy: 5)

        let ahead = result.plannedMeals.filter { !$0.isLocked }
        let aheadCalories = ahead.reduce(0) { $0 + $1.calories }
        XCTAssertEqual(aheadCalories, targets().calories - 1400, accuracy: 60,
                       "what's left of the day is the budget minus what went in")
    }

    // MARK: - Training owns the clock

    /// The case that started this: lunch at 12:30 and a session at 12:30.
    /// One of them has to move, and it isn't the session.
    func testMealIsMovedOutOfTheWayOfASessionAtTheSameTime() {
        let p = plan()
        let day = DayLog(date: noon)
        // The default schedule puts lunch at 12:30.
        let result = build(day: day, plan: p, targets: targets(),
                           sessions: [TrainingSession(id: "clash", name: "Tempo",
                                                      minutes: 90, hour: 12, minute: 30,
                                                      category: .cardio, intensity: .moderate)])
        guard let lunch = result.meals.first(where: { $0.meal == .lunch }) else {
            return XCTFail("lunch should still be on the plan")
        }
        XCTAssertNotNil(lunch.movedFrom, "lunch should have been moved off the session")
        XCTAssertEqual(lunch.movedFrom, 12 * 60 + 30)
        XCTAssertNotEqual(lunch.minutesOfDay, 12 * 60 + 30)
        XCTAssertNotNil(lunch.movedNote)
    }

    /// No meal may sit inside a session, or so close to the start that it
    /// hasn't cleared. The window it needs scales with how big it is.
    func testNoMealLandsInsideOrTooCloseToASession() {
        let p = plan()
        let day = DayLog(date: noon)
        let sessions = [
            TrainingSession(id: "am", name: "Intervals", minutes: 75, hour: 7, minute: 0,
                            category: .cardio, intensity: .hard),
            TrainingSession(id: "pm", name: "Lift", minutes: 60, hour: 18, minute: 0,
                            category: .strength, intensity: .moderate)
        ]
        let result = build(day: day, plan: p, targets: targets(), sessions: sessions)

        for meal in result.plannedMeals {
            for block in result.sessions {
                XCTAssertFalse(meal.minutesOfDay >= block.minutesOfDay
                                   && meal.minutesOfDay < block.endMinutesOfDay,
                               "\(meal.label) is scheduled during \(block.session.name)")
                // Anything before the session must clear it — 45 minutes is
                // the smallest window any meal size asks for.
                if meal.minutesOfDay < block.minutesOfDay {
                    XCTAssertLessThanOrEqual(meal.minutesOfDay, block.minutesOfDay - 45,
                                             "\(meal.label) is too close to \(block.session.name) to have cleared")
                }
            }
        }
    }

    /// A meal that moves to clear a session should then be the session's
    /// pre-session meal, not have a snack invented next to it.
    func testAMovedMealBecomesThePreSessionMealInsteadOfSpawningOne() {
        let p = plan()
        let day = DayLog(date: noon)
        let result = build(day: day, plan: p, targets: targets(),
                           sessions: [TrainingSession(id: "clash", name: "Tempo",
                                                      minutes: 90, hour: 13, minute: 0,
                                                      category: .cardio, intensity: .moderate)])

        guard let pre = result.meals.first(where: { $0.role == .preWorkout }) else {
            return XCTFail("something has to be the pre-session meal")
        }
        XCTAssertEqual(pre.meal, .lunch, "the moved lunch should be doing that job")
        XCTAssertFalse(pre.isSynthetic, "no snack should have been invented beside it")
    }

    /// Meals stay in clock order and don't stack on top of each other after
    /// being shuffled around.
    func testShiftedMealsStayOrderedAndApart() {
        let p = plan()
        let day = DayLog(date: noon)
        let result = build(day: day, plan: p, targets: targets(),
                           sessions: [TrainingSession(id: "mid", name: "Long ride",
                                                      minutes: 180, hour: 11, minute: 0,
                                                      category: .cardio, intensity: .moderate)])
        let times = result.plannedMeals.map(\.minutesOfDay)
        XCTAssertEqual(times, times.sorted(), "meals came out of order")
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b - a, 45, "two meals ended up on top of each other")
        }
    }

    /// An early session shouldn't drag breakfast to five in the morning. The
    /// right shape is a small top-up before and the real meal after, and the
    /// engine has to arrive at that on its own.
    func testAnEarlySessionGetsATopUpNotABreakfastAtFiveAM() {
        let p = plan()
        let day = DayLog(date: noon)
        let dawn = TrainingSession(id: "dawn", name: "Intervals", minutes: 75,
                                   hour: 7, minute: 0, category: .cardio, intensity: .hard)
        let result = build(day: day, plan: p, targets: targets(), sessions: [dawn])

        guard let breakfast = result.meals.first(where: { $0.meal == .breakfast }) else {
            return XCTFail("breakfast should still be on the plan")
        }
        XCTAssertGreaterThan(breakfast.minutesOfDay, 7 * 60,
                             "breakfast belongs after the session, not before dawn")
        XCTAssertEqual(breakfast.role, .recovery)

        guard let pre = result.meals.first(where: { $0.role == .preWorkout }) else {
            return XCTFail("something small should still go in beforehand")
        }
        XCTAssertTrue(pre.isSynthetic)
        XCTAssertLessThan(pre.calories, breakfast.calories,
                          "the pre-session top-up should be the smaller of the two")

        XCTAssertTrue(result.plannedMeals.allSatisfy { $0.minutesOfDay >= 5 * 60 + 30 },
                      "nothing should be scheduled before half five")
    }

    /// When the day's carb target can't cover its own session, the meals that
    /// aren't feeding it still get something — a breakfast of zero carbs is a
    /// symptom, not a plan.
    func testWorkoutFuelDoesNotStripEveryOtherMealOfCarbs() {
        let p = plan()
        let day = DayLog(date: noon)
        // A three-hour ride against a carb target set for something smaller.
        let long = session(at: 11, minutes: 180)
        let result = build(day: day, plan: p, targets: targets(), sessions: [long])

        XCTAssertFalse(result.advisories.isEmpty, "the mismatch has to be stated")
        for meal in result.plannedMeals where meal.role == .normal {
            XCTAssertGreaterThan(meal.carbGrams, 0,
                                 "\(meal.label) was stripped of carbs entirely")
        }
    }

    /// No two meals on a plan may share a `Meal`: food logged to one would
    /// count against both, and the progress bars would disagree with the log.
    func testEveryMealOnThePlanHasItsOwnIdentity() {
        let p = plan()
        let scenarios: [[TrainingSession]] = [
            [],
            [session(at: 7, minutes: 75)],
            [session(at: 11, minutes: 180)],
            [session(at: 6, minutes: 60), session(at: 18, minutes: 60, category: .strength)]
        ]
        for sessions in scenarios {
            let day = DayLog(date: noon)
            let result = build(day: day, plan: p, targets: targets(), sessions: sessions)
            let meals = result.plannedMeals.map(\.meal)
            XCTAssertEqual(Set(meals).count, meals.count,
                           "two meals shared an identity with \(sessions.count) session(s): \(meals)")
        }
    }

    /// A day with no training must leave the schedule exactly as written.
    func testMealsAreNotMovedWhenThereIsNoTraining() {
        let p = plan()
        let day = DayLog(date: noon)
        let result = build(day: day, plan: p, targets: targets())

        XCTAssertTrue(result.meals.allSatisfy { $0.movedFrom == nil },
                      "nothing should move on a rest day")
        let lunch = result.meals.first { $0.meal == .lunch }
        XCTAssertEqual(lunch?.minutesOfDay, 12 * 60 + 30, "lunch should be where the schedule put it")
    }

    /// A called-off session doesn't get to move anything.
    func testASkippedSessionDoesNotShoveMealsAround() {
        let p = plan()
        let day = DayLog(date: noon)
        let clash = TrainingSession(id: "clash", name: "Tempo", minutes: 90,
                                    hour: 12, minute: 30,
                                    category: .cardio, intensity: .moderate)
        let result = MealPlanEngine.plan(date: day.date, day: day, plan: p, profile: profile(),
                                         targets: targets(), sessions: [], fuels: [],
                                         skipped: [MealPlanEngine.SessionBlock(
                                            id: clash.id, session: clash,
                                            fuel: fuel(for: clash), isSkipped: true)],
                                         now: noon)
        let lunch = result.meals.first { $0.meal == .lunch }
        XCTAssertEqual(lunch?.minutesOfDay, 12 * 60 + 30)
        XCTAssertNil(lunch?.movedFrom)
    }

    // MARK: - Calling a session off

    /// The row going grey is the least of it. A session that isn't happening
    /// must stop fuelling the day: no pre-load, no recovery meal, no
    /// mid-session carbs.
    func testSkippedSessionStopsFuellingTheDay() {
        let p = plan()
        let day = DayLog(date: noon)
        let ride = session(at: 14, minutes: 120)

        let before = build(day: day, plan: p, targets: targets(), sessions: [ride])
        XCTAssertTrue(before.meals.contains { $0.role == .preWorkout })
        XCTAssertTrue(before.meals.contains { $0.role == .recovery })
        XCTAssertGreaterThan(before.duringSessionCarbs, 0)

        // Called off: the engine is handed it as a skipped block instead.
        let after = MealPlanEngine.plan(date: day.date, day: day, plan: p, profile: profile(),
                                        targets: targets(), sessions: [], fuels: [],
                                        skipped: [MealPlanEngine.SessionBlock(
                                            id: ride.id, session: ride,
                                            fuel: fuel(for: ride), isSkipped: true)],
                                        now: noon)

        XCTAssertEqual(after.duringSessionCarbs, 0, "nothing is being eaten mid-ride")
        XCTAssertTrue(after.meals.allSatisfy { $0.role == .normal },
                      "no meal should still be timed around a session that isn't happening")
        XCTAssertFalse(after.meals.contains(where: \.isSynthetic),
                       "the recovery snack existed only to feed the session")
        // But it's still on screen, so it can be put back.
        XCTAssertEqual(after.sessions.count, 1)
        XCTAssertTrue(after.sessions[0].isSkipped)
    }

    /// And the day's own targets have to come down — a rest day's food is not
    /// a training day's food. This is the path every other screen reads.
    func testSkippingASessionTakesItOutOfTheDaysTargets() {
        let p = plan()
        let day = DayLog(date: noon)
        p.days.append(day)

        let workout = WorkoutScheduleEntry(weekday: Calendar.current.component(.weekday, from: day.date),
                                           name: "Threshold intervals", minutes: 90,
                                           hour: 17, minute: 0,
                                           category: .cardio, intensity: .hard)
        p.schedule.append(workout)

        let live = p.sessions(on: day.date)
        XCTAssertEqual(live.count, 1)
        let trainingTargets = AthleteEngine.targets(profile: profile(), plan: p,
                                                    maintenanceTDEE: 2600,
                                                    sessions: live)

        day.setWorkoutSkipped(live[0].skipKey, true)

        XCTAssertTrue(p.sessions(on: day.date).isEmpty,
                      "a called-off session must not reach the engines")
        XCTAssertEqual(p.allSessions(on: day.date).count, 1,
                       "but it's still on the books, so it can be put back")

        let restTargets = AthleteEngine.targets(profile: profile(), plan: p,
                                                maintenanceTDEE: 2600,
                                                sessions: p.sessions(on: day.date))
        XCTAssertLessThan(restTargets.calories, trainingTargets.calories)
        XCTAssertLessThan(restTargets.carbGrams, trainingTargets.carbGrams)
        XCTAssertEqual(restTargets.load, .rest)
    }

    /// Work already done can't be called off — the calories were spent.
    func testLoggedWorkoutsCannotBeSkipped() {
        let logged = WorkoutLog(name: "Morning run", minutes: 45, category: .cardio,
                                intensity: .moderate, startHour: 6, startMinute: 30)
        XCTAssertFalse(TrainingSession(logged).canBeSkipped)
        XCTAssertTrue(session(at: 9).canBeSkipped)
    }

    /// Putting it back has to restore the day exactly.
    func testUnskippingRestoresTheSession() {
        let p = plan()
        let day = DayLog(date: noon)
        p.days.append(day)
        let entry = WorkoutScheduleEntry(weekday: Calendar.current.component(.weekday, from: day.date),
                                         name: "Easy spin", minutes: 60, hour: 7, minute: 0)
        p.schedule.append(entry)

        let key = p.sessions(on: day.date)[0].skipKey
        day.setWorkoutSkipped(key, true)
        XCTAssertTrue(p.sessions(on: day.date).isEmpty)

        day.setWorkoutSkipped(key, false)
        XCTAssertEqual(p.sessions(on: day.date).count, 1)
        XCTAssertFalse(day.hasDayShapeChanges)
    }

    // MARK: - Protein

    /// Spread, not stacked: a day that puts 150 g of protein into dinner and
    /// 20 into breakfast wastes most of the dinner.
    ///
    /// Deliberately *not* asserting a hard per-meal cap. 200 g across three
    /// meals is 67 g each, and there is no version of this where the right
    /// answer is to tell someone to eat 165 g instead. What has to hold is
    /// that no meal runs away with it.
    func testProteinIsSpreadAcrossMealsRatherThanStacked() {
        let p = plan()
        let day = DayLog(date: noon)
        let result = build(day: day, plan: p, targets: targets(protein: 200))

        let evenShare = 200.0 / Double(result.plannedMeals.count)
        for meal in result.plannedMeals {
            XCTAssertLessThanOrEqual(Double(meal.proteinGrams), evenShare * 1.5,
                                     "\(meal.label) is carrying far more than its share of the day's protein")
            XCTAssertGreaterThanOrEqual(Double(meal.proteinGrams), evenShare * 0.5,
                                        "\(meal.label) is carrying too little to be worth eating protein at")
        }
        let total = result.plannedMeals.reduce(0) { $0 + $1.proteinGrams }
        XCTAssertEqual(total, 200, accuracy: 3, "and the day still has to add up")
    }

    // MARK: - Iron

    func testLowIronMarksAMealToCarryIt() {
        let p = plan()
        let day = DayLog(date: noon)
        let labs = LabResult(date: Date())
        labs.ferritin = 14
        let finding = IronCoach.evaluate(labs: labs, sex: .female)

        let result = MealPlanEngine.plan(date: day.date, day: day, plan: p,
                                         profile: profile(), targets: targets(),
                                         sessions: [], fuels: [], iron: finding, now: noon)
        XCTAssertEqual(result.meals.filter(\.isIronFocus).count, 1)
    }

    func testHealthyIronDoesNotSteerAnything() {
        let p = plan()
        let day = DayLog(date: noon)
        let labs = LabResult(date: Date())
        labs.ferritin = 90
        let finding = IronCoach.evaluate(labs: labs, sex: .female)

        let result = MealPlanEngine.plan(date: day.date, day: day, plan: p,
                                         profile: profile(), targets: targets(),
                                         sessions: [], fuels: [], iron: finding, now: noon)
        XCTAssertTrue(result.meals.allSatisfy { !$0.isIronFocus })
    }
}

// MARK: - Iron thresholds

/// Ferritin is read against sports-medicine guidance, not the clinical anemia
/// cut-off — the question is whether it's costing training, which happens
/// well before a blood count looks wrong.
final class IronCoachTests: XCTestCase {

    private func labs(ferritin: Double? = nil, hemoglobin: Double? = nil,
                      saturation: Double? = nil, date: Date = Date()) -> LabResult {
        let l = LabResult(date: date)
        l.ferritin = ferritin
        l.hemoglobin = hemoglobin
        l.transferrinSaturation = saturation
        return l
    }

    func testNoIronMarkersMeansNoOpinion() {
        let lipidsOnly = LabResult(date: Date())
        lipidsOnly.ldl = 130
        XCTAssertNil(IronCoach.evaluate(labs: lipidsOnly, sex: .female))
        XCTAssertNil(IronCoach.evaluate(labs: nil, sex: .female))
    }

    func testFerritinBands() {
        XCTAssertEqual(IronCoach.evaluate(labs: labs(ferritin: 12), sex: .female)?.status, .depleted)
        XCTAssertEqual(IronCoach.evaluate(labs: labs(ferritin: 25), sex: .female)?.status, .low)
        XCTAssertEqual(IronCoach.evaluate(labs: labs(ferritin: 40), sex: .female)?.status, .watch)
        XCTAssertEqual(IronCoach.evaluate(labs: labs(ferritin: 80), sex: .female)?.status, .stocked)
    }

    /// The case that matters clinically: stores can read fine while the blood
    /// count says otherwise, and the blood count wins.
    func testLowHemoglobinOverridesAReassuringFerritin() {
        let finding = IronCoach.evaluate(labs: labs(ferritin: 90, hemoglobin: 10.5), sex: .female)
        XCTAssertEqual(finding?.status, .depleted)
    }

    func testLowSaturationPullsABorderlineReadingDown() {
        let finding = IronCoach.evaluate(labs: labs(ferritin: 45, saturation: 14), sex: .male)
        XCTAssertEqual(finding?.status, .low)
    }

    /// Non-negotiable: this must never point someone at an iron supplement.
    func testNeverRecommendsSupplementing() {
        let finding = IronCoach.evaluate(labs: labs(ferritin: 10), sex: .female)!
        let text = (finding.actions + [finding.explanation, finding.mealNote]).joined(separator: " ").lowercased()
        XCTAssertTrue(text.contains("doctor"))
        XCTAssertFalse(text.contains("take an iron supplement"))
        XCTAssertFalse(text.contains("start supplementing"))
    }

    func testStaleResultsAreFlagged() {
        let old = Calendar.current.date(byAdding: .month, value: -18, to: Date())!
        let finding = IronCoach.evaluate(labs: labs(ferritin: 15, date: old), sex: .female)
        XCTAssertNotNil(finding?.staleness)
        XCTAssertNil(IronCoach.evaluate(labs: labs(ferritin: 15), sex: .female)?.staleness)
    }

    /// Women of menstruating age need more than double the male RDA, and
    /// endurance training raises it again on top of that.
    func testIronTargetsReflectSexAndTraining() {
        let woman = IronCoach.dailyIronTargetMg(sex: .female, age: 30, isAthlete: false)
        let man = IronCoach.dailyIronTargetMg(sex: .male, age: 30, isAthlete: false)
        let athlete = IronCoach.dailyIronTargetMg(sex: .female, age: 30, isAthlete: true)
        XCTAssertGreaterThan(woman, man)
        XCTAssertGreaterThan(athlete, woman)
    }
}

// MARK: - Protein convention

final class AthleteProteinTests: XCTestCase {

    private func profile() -> UserProfile {
        UserProfile(birthDate: Calendar.current.date(byAdding: .year, value: -30, to: Date())!,
                    heightInches: 70, sex: .male, activityLevel: .moderate, mode: .athlete)
    }

    private func plan(perPound: Bool) -> Plan {
        let p = Plan(startDate: Date(), startingWeight: 180, goalWeight: 180,
                     paceLbsPerWeek: 0, proteinTargetGrams: 180)
        p.proteinPerPoundTarget = perPound
        return p
    }

    func testProteinFloorIsOneGramPerPound() {
        let t = AthleteEngine.targets(profile: profile(), plan: plan(perPound: true),
                                      maintenanceTDEE: 2600, sessions: [])
        XCTAssertEqual(t.proteinGrams, 180, accuracy: 1)
    }

    /// Switched off, it falls back to the load-based g/kg bands — which for a
    /// rest day is meaningfully less.
    func testFallsBackToTheLoadBandsWhenSwitchedOff() {
        let t = AthleteEngine.targets(profile: profile(), plan: plan(perPound: false),
                                      maintenanceTDEE: 2600, sessions: [])
        XCTAssertLessThan(t.proteinGrams, 180)
        XCTAssertEqual(Double(t.proteinGrams), 180 * 0.45359237 * 1.6, accuracy: 2)
    }

    /// It's a floor, not a cap: a day whose load already asks for more keeps
    /// asking for more.
    func testHardDaysAreNotCappedByIt() {
        let big = TrainingSession(id: "big", name: "Long ride", minutes: 300,
                                  hour: 7, minute: 0, category: .cardio, intensity: .hard)
        let t = AthleteEngine.targets(profile: profile(), plan: plan(perPound: true),
                                      maintenanceTDEE: 2600, sessions: [big])
        XCTAssertGreaterThanOrEqual(t.proteinGrams, 180)
    }
}
