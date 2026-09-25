import XCTest
@testable import _5

/// The timing statistics only mean anything if they read the *eaten* time and
/// ignore the days a meal didn't happen — both of which are easy to get wrong
/// in a way no screenshot would show.
final class EatingRhythmTests: XCTestCase {

    private let cal = Calendar.current

    private func day(_ dayOffset: Int) -> DayLog {
        let base = cal.startOfDay(for: Date())
        return DayLog(date: cal.date(byAdding: .day, value: dayOffset, to: base)!)
    }

    /// Log food at a wall-clock time on its own day, the way the app does once
    /// a time has been set or corrected.
    private func add(_ day: DayLog, _ name: String, hour: Int, minute: Int = 0,
                     calories: Int = 500, protein: Int = 30,
                     meal: Meal = .lunch, facts: NutritionFacts = NutritionFacts()) {
        let food = FoodLog(name: name, calories: calories, proteinGrams: protein,
                           meal: meal, facts: facts)
        // Logged "now", eaten at the given hour — the case the whole feature
        // exists for.
        food.setEatenTime(cal.date(bySettingHour: hour, minute: minute, second: 0,
                                   of: day.date)!,
                          onDayOf: day.date)
        day.foods.append(food)
    }

    // MARK: - Per-meal timing

    func testAMealsAverageTimeComesFromWhenItWasEaten() {
        let d1 = day(-2), d2 = day(-1), d3 = day(0)
        add(d1, "Lunch", hour: 12, minute: 30)
        add(d2, "Lunch", hour: 13, minute: 0)
        add(d3, "Lunch", hour: 13, minute: 30)

        guard let lunch = EatingRhythm.timings(days: [d1, d2, d3])
            .first(where: { $0.meal == .lunch }) else {
            return XCTFail("lunch should appear")
        }
        XCTAssertEqual(lunch.averageMinutesOfDay, 13 * 60, "12:30, 1:00, 1:30 averages to 1:00")
        XCTAssertEqual(lunch.daysLogged, 3)
        XCTAssertEqual(lunch.averageCalories, 500)
        XCTAssertEqual(lunch.averageProtein, 30)
        XCTAssertEqual(lunch.swingMinutes, 20, "mean distance from the average")
    }

    /// The days a meal didn't happen must not drag its average down — a proper
    /// breakfast four days a week is a 600-calorie breakfast, not a 340 one.
    func testDaysWithoutTheMealAreNotAveragedIn() {
        let d1 = day(-1), d2 = day(0)
        add(d1, "Eggs", hour: 7, calories: 600, protein: 40, meal: .breakfast)
        add(d2, "Nothing for breakfast, just lunch", hour: 12, calories: 700, meal: .lunch)

        let timings = EatingRhythm.timings(days: [d1, d2])
        guard let breakfast = timings.first(where: { $0.meal == .breakfast }) else {
            return XCTFail("breakfast should appear")
        }
        XCTAssertEqual(breakfast.daysLogged, 1)
        XCTAssertEqual(breakfast.averageCalories, 600)
        XCTAssertEqual(timings.map(\.meal), [.breakfast, .lunch], "rows come back in clock order")
    }

    /// A meal with nothing logged against it anywhere shouldn't invent a row.
    func testMealsNeverEatenAreAbsent() {
        let d = day(0)
        add(d, "Dinner", hour: 19, meal: .dinner)
        XCTAssertEqual(EatingRhythm.timings(days: [d]).map(\.meal), [.dinner])
    }

    // MARK: - Energy across the clock

    func testCaloriesLandInTheBucketTheyWereEatenIn() {
        let d = day(0)
        add(d, "Breakfast", hour: 7, calories: 400, protein: 25, meal: .breakfast,
            facts: NutritionFacts(carbsGrams: 40, fatGrams: 10))
        add(d, "Late dinner", hour: 21, calories: 800, protein: 50, meal: .dinner,
            facts: NutritionFacts(carbsGrams: 60, fatGrams: 30))

        let buckets = EatingRhythm.byTimeOfDay(days: [d], bucketHours: 2)
        XCTAssertEqual(buckets.count, 12, "two-hour buckets cover the whole clock")

        guard let morning = buckets.first(where: { $0.startMinutes == 6 * 60 }),
              let night = buckets.first(where: { $0.startMinutes == 20 * 60 }) else {
            return XCTFail("missing buckets")
        }
        XCTAssertEqual(morning.carbCalories, 160, accuracy: 0.01)
        XCTAssertEqual(morning.proteinCalories, 100, accuracy: 0.01)
        XCTAssertEqual(morning.fatCalories, 90, accuracy: 0.01)
        XCTAssertEqual(night.carbCalories, 240, accuracy: 0.01)
        XCTAssertEqual(buckets.filter { $0.totalCalories > 0 }.count, 2,
                       "nothing lands in the hours nothing was eaten")
    }

    /// A quick-add with no macro panel is still energy — it can't silently
    /// vanish from the chart.
    func testFoodWithNoMacroPanelStillShowsAsEnergy() {
        let d = day(0)
        add(d, "Mystery pastry", hour: 15, calories: 300, protein: 0,
            meal: .afternoonSnack)

        guard let bucket = EatingRhythm.byTimeOfDay(days: [d])
            .first(where: { $0.startMinutes == 14 * 60 }) else {
            return XCTFail("missing bucket")
        }
        XCTAssertEqual(bucket.unattributedCalories, 300, accuracy: 0.01)
        XCTAssertEqual(bucket.totalCalories, 300, accuracy: 0.01)
    }

    /// Averaged per logging day, so a longer range doesn't look like a bigger
    /// appetite. A day with nothing logged isn't a day of fasting — it's a day
    /// nobody logged — so it's left out of the divisor.
    func testBucketsAverageOverLoggingDaysOnly() {
        let d1 = day(-1), d2 = day(0), empty = day(-2)
        add(d1, "Lunch", hour: 12, calories: 600, protein: 40)
        add(d2, "Lunch", hour: 12, calories: 400, protein: 20)

        guard let bucket = EatingRhythm.byTimeOfDay(days: [empty, d1, d2])
            .first(where: { $0.startMinutes == 12 * 60 }) else {
            return XCTFail("missing bucket")
        }
        XCTAssertEqual(bucket.loggedCalories, 500, accuracy: 0.01,
                       "two logging days, 1,000 calories between them")
    }

    // MARK: - Window and late share

    func testWindowAveragesFirstAndLastFood() {
        let d1 = day(-1), d2 = day(0)
        add(d1, "Coffee and toast", hour: 8, meal: .breakfast)
        add(d1, "Dinner", hour: 19, meal: .dinner)
        add(d2, "Breakfast", hour: 6, meal: .breakfast)
        add(d2, "Dinner", hour: 21, meal: .dinner)

        guard let window = EatingRhythm.window(days: [d1, d2]) else {
            return XCTFail("window should exist")
        }
        XCTAssertEqual(window.averageFirstMinutes, 7 * 60)
        XCTAssertEqual(window.averageLastMinutes, 20 * 60)
        XCTAssertEqual(window.hours, 13, accuracy: 0.01)
        XCTAssertEqual(window.daysCounted, 2)
    }

    func testShareAfterAnHourCountsOnlyWhatCameAfterIt() {
        let d = day(0)
        add(d, "Lunch", hour: 12, calories: 600)
        add(d, "Late snack", hour: 22, calories: 400, meal: .dessert)

        XCTAssertEqual(EatingRhythm.shareAfter(hour: 20, days: [d]) ?? 0, 0.4, accuracy: 0.001)
        XCTAssertNil(EatingRhythm.shareAfter(hour: 20, days: [day(-5)]),
                     "nothing logged, nothing to report")
    }
}
