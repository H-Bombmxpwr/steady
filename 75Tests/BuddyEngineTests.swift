import XCTest
@testable import _5

/// The studio's reward math: what a day pays, how the tour splits the weight
/// to lose into tracks, and when an Encore covers a missed day. Rewards must
/// follow the log exactly — a wrong number here is a buddy saying something
/// untrue.
final class BuddyEngineTests: XCTestCase {

    private let targets = DailyTargets(calories: 2000, proteinGrams: 150, waterOunces: 96)

    // MARK: Tour

    private func tour(start: Double = 235, goal: Double = 185,
                      current: Double, best: Double? = nil) -> Tour {
        Tour(number: 1, start: start, goal: goal, current: current, best: best ?? current)
    }

    /// Ten tracks whatever the distance: 13 lb to lose is ten 1.3-lb tracks,
    /// so a small goal unlocks the same gear as a big one.
    func testTracksAreTenthsOfTheDistance() {
        let t = tour(goal: 222, current: 235)
        XCTAssertEqual(t.trackCount, 10)
        XCTAssertEqual(t.trackEnd(1), 1.3, accuracy: 1e-9)
        XCTAssertEqual(t.trackEnd(10), 13, accuracy: 1e-9)
    }

    func testNothingFinishedAtTheStart() {
        let t = tour(current: 235)
        XCTAssertEqual(t.tracksDone, 0)
        XCTAssertEqual(t.currentTrack, 1)
        XCTAssertEqual(t.poundsBanked, 0)
        XCTAssertEqual(t.nextRecordAt, 234)
        XCTAssertEqual(t.toNextTrack ?? -1, 5, accuracy: 0.001)
    }

    /// The trend bouncing back up doesn't un-finish a track or un-earn a
    /// record — rewards are paid against the best, distance against now.
    func testReboundKeepsWhatWasEarned() {
        let t = tour(current: 231.5, best: 229.6)
        XCTAssertEqual(t.tracksDone, 1)
        XCTAssertEqual(t.poundsBanked, 5)
        XCTAssertEqual(t.currentTrack, 2)
        XCTAssertEqual(t.toNextTrack ?? -1, 6.5, accuracy: 0.001)   // 10 − 3.5 lost now
    }

    func testReachingGoalFinishesTheTour() {
        let t = tour(current: 184.8)
        XCTAssertTrue(t.finished)
        XCTAssertNil(t.currentTrack)
        XCTAssertEqual(t.tracksDone, t.trackCount)
    }

    /// Up past where the tour began — the 235-and-climbing case — is when a
    /// fresh start gets offered, and only then.
    func testFreshStartOnlyOfferedWhenAboveTheStart() {
        XCTAssertTrue(tour(current: 236).freshStartSuggested)
        XCTAssertFalse(tour(current: 235.3).freshStartSuggested)
        XCTAssertFalse(tour(current: 230).freshStartSuggested)
    }

    func testLastTrackPaysTheTrophy() {
        XCTAssertEqual(StudioCatalog.exclusive(forTrack: 10, of: 10)?.id, "trophy")
        XCTAssertEqual(StudioCatalog.exclusive(forTrack: 1, of: 10)?.id, "studio-mic")
        XCTAssertNil(StudioCatalog.exclusive(forTrack: 9, of: 10))   // notes + a record instead
    }

    // MARK: Chores

    func testEmptyDayPaysNothing() {
        let day = DayLog(date: Date())
        XCTAssertTrue(BuddyEngine.choresDone(day: day, targets: targets).isEmpty)
        XCTAssertEqual(BuddyEngine.notes(day: day, targets: targets), 0)
    }

    func testWeighInAloneIsTenNotes() {
        let day = DayLog(date: Date())
        day.weight = 235
        XCTAssertEqual(BuddyEngine.choresDone(day: day, targets: targets), [.weighIn])
        XCTAssertEqual(BuddyEngine.notes(day: day, targets: targets), 10)
    }

    func testTargetRewardRequiresCompletedDayAndAdequateIntake() {
        let today = Calendar.current.startOfDay(for: Date())
        let day = DayLog(date: today)
        for meal in [Meal.breakfast, .lunch, .dinner] {
            day.foods.append(FoodLog(name: "Meal", calories: 650, proteinGrams: 40, meal: meal))
        }
        XCTAssertFalse(BuddyEngine.choresDone(day: day, targets: targets).contains(.underBudget))
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        XCTAssertTrue(BuddyEngine.choresDone(day: day, targets: targets, now: tomorrow).contains(.underBudget))
        for food in day.foods { food.calories = 100 }
        XCTAssertFalse(BuddyEngine.choresDone(day: day, targets: targets, now: tomorrow).contains(.underBudget))
        XCTAssertTrue(BuddyEngine.choresDone(day: day, targets: targets, now: tomorrow).contains(.threeMeals))
    }

    func testOverBudgetStillPaysForLogging() {
        let day = DayLog(date: Date())
        for meal in [Meal.breakfast, .lunch, .dinner] {
            day.foods.append(FoodLog(name: "Big", calories: 900, proteinGrams: 10, meal: meal))
        }
        let done = BuddyEngine.choresDone(day: day, targets: targets)
        XCTAssertTrue(done.contains(.threeMeals))
        XCTAssertFalse(done.contains(.underBudget))
    }

    // MARK: Mood

    func testComingBackAfterAGapIsAWelcomeNotAGuiltTrip() {
        let mood = BuddyEngine.mood(done: [], hour: 9, newLowToday: false,
                                    daysAway: 4, loggedToday: false)
        XCTAssertEqual(mood, .welcomeBack)
    }

    func testNewLowOutranksEverything() {
        let mood = BuddyEngine.mood(done: [], hour: 23, newLowToday: true,
                                    daysAway: 5, loggedToday: false)
        XCTAssertEqual(mood, .newLow)
    }

    func testMorningWithoutWeighInIsWaiting() {
        XCTAssertEqual(BuddyEngine.mood(done: [], hour: 8, newLowToday: false,
                                        daysAway: 0, loggedToday: false), .waiting)
    }

    // MARK: Encores

    func testEncoreCoversYesterdayWhenItBrokeAStreak() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -5, to: today)!
        let plan = Plan(startDate: start, startingWeight: 235, goalWeight: 185,
                        paceLbsPerWeek: 1, proteinTargetGrams: 150)
        // Logged every day except yesterday.
        for back in [5, 4, 3, 2] {
            let d = DayLog(date: cal.date(byAdding: .day, value: -back, to: today)!)
            d.weight = 235
            plan.days.append(d)
        }
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        XCTAssertEqual(BuddyEngine.daysToCover(plan: plan, targets: targets, encores: 1), [yesterday])
        XCTAssertEqual(BuddyEngine.daysToCover(plan: plan, targets: targets, encores: 0), [])

        plan.protectedDays = [yesterday]
        XCTAssertEqual(BuddyEngine.daysToCover(plan: plan, targets: targets, encores: 1), [])
        // The covered day bridges the streak without counting as a day met.
        XCTAssertEqual(CalorieEngine.streakStats(plan: plan, targets: targets).current, 4)
    }

    func testNoEncoreSpentWhenThereWasNoStreakToSave() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let plan = Plan(startDate: cal.date(byAdding: .day, value: -10, to: today)!,
                        startingWeight: 235, goalWeight: 185,
                        paceLbsPerWeek: 1, proteinTargetGrams: 150)
        XCTAssertEqual(BuddyEngine.daysToCover(plan: plan, targets: targets, encores: 2), [])
    }

    // MARK: Mealtime

    private func snapshot(logged: [String] = []) -> WidgetSnapshot {
        var s = WidgetSnapshot()
        s.meals = [MealMoment(meal: "breakfast", label: "Breakfast", minutes: 7 * 60),
                   MealMoment(meal: "lunch", label: "Lunch", minutes: 12 * 60 + 30),
                   MealMoment(meal: "dinner", label: "Dinner", minutes: 18 * 60 + 30)]
        s.mealsLogged = logged
        s.dayDate = Calendar.current.startOfDay(for: Date())
        return s
    }

    private func today(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    func testLunchIsDueInsideItsWindow() {
        guard case let .due(meal, start, end) = snapshot().mealState(at: today(12, 45)) else {
            return XCTFail("expected lunch due")
        }
        XCTAssertEqual(meal.label, "Lunch")
        XCTAssertEqual(start, today(12, 30))
        XCTAssertEqual(end, today(14, 0))   // 90-minute window
    }

    func testLoggingLunchClearsThePrompt() {
        guard case let .logged(meal, next) = snapshot(logged: ["lunch"]).mealState(at: today(12, 45)) else {
            return XCTFail("expected lunch logged")
        }
        XCTAssertEqual(meal.label, "Lunch")
        XCTAssertEqual(next?.0.label, "Dinner")
    }

    func testBetweenMealsShowsTheNextOne() {
        XCTAssertEqual(snapshot().mealState(at: today(15)),
                       .upcoming(MealMoment(meal: "dinner", label: "Dinner", minutes: 18 * 60 + 30),
                                 at: today(18, 30)))
    }

    func testAfterDinnerItsAWrap() {
        XCTAssertEqual(snapshot().mealState(at: today(21, 30)), .wrapped)
    }

    /// A window never runs into the next meal, however close they are.
    func testWindowStopsAtTheNextMeal() {
        var s = snapshot()
        s.meals = [MealMoment(meal: "breakfast", label: "Breakfast", minutes: 7 * 60),
                   MealMoment(meal: "morning_snack", label: "Snack", minutes: 8 * 60)]
        guard case let .due(_, _, end) = s.mealState(at: today(7, 10)) else { return XCTFail() }
        XCTAssertEqual(end, today(8))
    }

    /// The widget timeline needs an entry at every flip, or it shows lunch
    /// as "next" all through lunch.
    func testBoundariesCoverEveryWindowEdge() {
        let b = snapshot().mealBoundaries(from: today(6), to: today(23))
        for t in [today(7), today(8, 30), today(12, 30), today(14), today(18, 30), today(20)] {
            XCTAssertTrue(b.contains(t), "missing \(t)")
        }
    }

}
