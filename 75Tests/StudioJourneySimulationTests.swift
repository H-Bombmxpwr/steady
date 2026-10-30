import XCTest
@testable import _5

/// Deterministic journeys through the production store, not a second economy
/// implementation. Dates, weight noise and shopping policy are controlled;
/// rewards, tiers, prices, jar settlement and persistence are the real code.
@MainActor
final class StudioJourneySimulationTests: XCTestCase {
    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    struct Scenario {
        let name: String
        let pounds: Double
        let weeklyLoss: Double
        var visitsPerDay = 1
        var loggingDaysPerWeek = 7
        var plateauDays = 0
        var neverLose = false
        var promoShare = 0.5

        var duration: Int {
            neverLose ? 180 : Int((pounds / weeklyLoss * 7).rounded(.up)) + plateauDays + 35
        }
    }

    struct Result {
        var firstDecoration: Int?
        var firstBandmate: Int?
        var shopComplete: Int?
        var goalReached: Int?
        var maxRewardGap = 0
        var recordsEarned = 0
        var boughtRecords = 0
        var loggingDays = 0
        var finalNotes = 0.0
        var finalRate = 0.0
    }

    private func run(_ scenario: Scenario) throws -> Result {
        let cal = Calendar.current
        let start = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let clock = Clock(start.addingTimeInterval(18 * 3600))
        let targets = DailyTargets(calories: 2000, proteinGrams: 150, waterOunces: 96)
        let startWeight = 170 + scenario.pounds
        let plan = Plan(startDate: start, startingWeight: startWeight, goalWeight: 170,
                        paceLbsPerWeek: scenario.weeklyLoss, proteinTargetGrams: 150)
        var store = BuddyStore(initialState: BuddyState(), clock: { clock.date })
        store.setUp(species: .penguin, name: "Sim", startWeight: startWeight,
                    startDate: start, goalWeight: 170)
        var result = Result()
        var lastRewardDay = 0
        var previousDigs = 0
        let forSale = StudioCatalog.forSale.sorted { StudioCatalog.price($0) < StudioCatalog.price($1) }

        for dayIndex in 0..<scenario.duration {
            let date = cal.date(byAdding: .day, value: dayIndex, to: start)!
            let logsToday = dayIndex % 7 < scenario.loggingDaysPerWeek
            var rewardToday = false
            for visit in 0..<scenario.visitsPerDay {
                let hour = scenario.visitsPerDay == 1 ? 18 : (visit == 0 ? 8 : 20)
                clock.date = date.addingTimeInterval(Double(hour) * 3600)
                // Log once, at the final visit. Earlier visits may collect and shop.
                if logsToday && visit == scenario.visitsPerDay - 1 {
                    let day = DayLog(date: date)
                    let plateauElapsed = min(scenario.plateauDays, max(0, dayIndex - 21))
                    let lossDays = max(0, dayIndex - plateauElapsed)
                    let intended = scenario.neverLose ? startWeight
                        : max(170, startWeight - Double(lossDays) * scenario.weeklyLoss / 7)
                    let noise = dayIndex == 0 || scenario.neverLose ? 0 : 0.6 * sin(Double(dayIndex) * 0.9)
                    day.weight = intended + noise
                    day.waterOunces = 96
                    var facts = NutritionFacts()
                    facts.fiberGrams = 7
                    for meal in [Meal.breakfast, .lunch, .dinner] {
                        day.foods.append(FoodLog(name: "Meal", calories: 650, proteinGrams: 50,
                                                meal: meal, facts: facts))
                    }
                    plan.days.append(day)
                }
                store.sync(plan: plan, targets: targets)
                let jarBefore = store.jar(at: clock.date)
                let balanceBefore = store.notes
                XCTAssertTrue(jarBefore.isFinite)
                XCTAssertGreaterThanOrEqual(jarBefore, 0)
                let collected = store.collect(plan: plan, targets: targets)
                XCTAssertEqual(collected, jarBefore, accuracy: max(1e-6, jarBefore * 1e-12))
                XCTAssertEqual(store.notes, balanceBefore + collected,
                               accuracy: max(1e-6, store.notes * 1e-12))

                if dayIndex == 0 && visit == 0 {
                    XCTAssertTrue(store.buy(IdleEngine.generator("busk")!, plan: plan, targets: targets))
                    let coffee = StudioCatalog.gear("coffee")!
                    XCTAssertTrue(store.buy(coffee, price: StudioCatalog.price(coffee), plan: plan, targets: targets))
                    result.firstDecoration = 0
                    rewardToday = true
                }
                if store.giftAvailable(plan: plan, targets: targets) {
                    _ = store.openGift(rate: store.rate(plan: plan, targets: targets))
                }

                // Bounded strategy: spend a share on the best affordable return,
                // then decorations. This is a purchasing policy, not economy math.
                var promoBudget = store.notes * scenario.promoShare
                while let generator = IdleEngine.generators.filter({
                    store.isUnlocked($0) && store.level($0) < store.levelCap &&
                        $0.cost(level: store.level($0)) <= promoBudget
                }).min(by: {
                    $0.cost(level: store.level($0)) / $0.baseRate <
                        $1.cost(level: store.level($1)) / $1.baseRate
                }) {
                    let cost = generator.cost(level: store.level(generator))
                    XCTAssertTrue(store.buy(generator, plan: plan, targets: targets))
                    promoBudget -= cost
                    rewardToday = true
                }
                for gear in forSale where !store.owns(gear) && store.isUnlocked(gear) {
                    let price = StudioCatalog.price(gear)
                    if price <= store.notes {
                        XCTAssertTrue(store.buy(gear, price: price, plan: plan, targets: targets))
                        if gear.slot == .band && result.firstBandmate == nil { result.firstBandmate = dayIndex }
                        rewardToday = true
                    }
                }
                // An occasional record remains a usable sink after the room is full.
                if dayIndex % 7 == 6 && visit == scenario.visitsPerDay - 1 {
                    let rate = store.rate(plan: plan, targets: targets)
                    if store.notes >= store.recordPrice(rate: rate) * 2 {
                        XCTAssertTrue(store.buyRecord(rate: rate))
                    }
                }
                if result.shopComplete == nil && forSale.allSatisfy({ store.owns($0) }) {
                    result.shopComplete = dayIndex
                }
                if result.goalReached == nil && store.tour(plan: plan).finished { result.goalReached = dayIndex }
                XCTAssertTrue(store.notes.isFinite)
                XCTAssertGreaterThanOrEqual(store.notes, 0)
                XCTAssertTrue(store.rate(plan: plan, targets: targets).isFinite)
            }
            if store.state.digs > previousDigs { rewardToday = true }
            previousDigs = store.state.digs
            if rewardToday {
                result.maxRewardGap = max(result.maxRewardGap, dayIndex - lastRewardDay)
                lastRewardDay = dayIndex
            }
            // Relaunch once a month: the simulation must survive serialization.
            if dayIndex % 30 == 29 {
                let data = try JSONEncoder().encode(store.state)
                store = BuddyStore(initialState: try JSONDecoder().decode(BuddyState.self, from: data),
                                   clock: { clock.date })
            }
        }
        result.maxRewardGap = max(result.maxRewardGap, scenario.duration - 1 - lastRewardDay)
        result.recordsEarned = store.state.digs
        result.boughtRecords = store.state.recordsBought
        result.loggingDays = store.state.loggingDays.count
        result.finalNotes = store.notes
        result.finalRate = store.rate(plan: plan, targets: targets)
        func day(_ value: Int?) -> String { value.map(String.init) ?? "—" }
        print("JOURNEY | \(scenario.name) | \(scenario.duration) | \(day(result.firstDecoration)) | \(day(result.firstBandmate)) | \(day(result.shopComplete)) | \(day(result.goalReached)) | \(result.maxRewardGap) | \(result.recordsEarned) | \(result.boughtRecords)")
        return result
    }

    func testWeightLossJourneysWithDailyCheckIn() throws {
        for scenario in [
            Scenario(name: "100 lb / 1 per week", pounds: 100, weeklyLoss: 1),
            Scenario(name: "50 lb / 1 per week", pounds: 50, weeklyLoss: 1),
            Scenario(name: "12 lb / 0.5 per week", pounds: 12, weeklyLoss: 0.5),
            Scenario(name: "5 lb / 0.5 per week", pounds: 5, weeklyLoss: 0.5),
        ] {
            let result = try run(scenario)
            XCTAssertEqual(result.firstDecoration, 0, scenario.name)
            XCTAssertLessThanOrEqual(result.firstBandmate ?? .max, 9, scenario.name)
            XCTAssertLessThanOrEqual(result.shopComplete ?? .max, 90, scenario.name)
            XCTAssertNotNil(result.goalReached, scenario.name)
            XCTAssertLessThanOrEqual(result.maxRewardGap, 14, scenario.name)
            XCTAssertGreaterThan(result.boughtRecords, 5, scenario.name)
        }
    }

    func testPlateauAndMaintenanceKeepRewardingLogging() throws {
        for scenario in [
            Scenario(name: "50 lb / 8 week plateau", pounds: 50, weeklyLoss: 1, plateauDays: 56),
            Scenario(name: "100 lb / no loss", pounds: 100, weeklyLoss: 1, neverLose: true),
            Scenario(name: "50 lb / 5 logging days weekly", pounds: 50, weeklyLoss: 1,
                     loggingDaysPerWeek: 5, promoShare: 0.25),
        ] {
            let result = try run(scenario)
            XCTAssertLessThanOrEqual(result.firstBandmate ?? .max, 14, scenario.name)
            XCTAssertLessThanOrEqual(result.shopComplete ?? .max, 120, scenario.name)
            XCTAssertLessThanOrEqual(result.maxRewardGap, 21, scenario.name)
            if scenario.neverLose { XCTAssertNil(result.goalReached) }
            XCTAssertGreaterThan(result.recordsEarned, result.boughtRecords + result.loggingDays / 7 - 1)
        }
    }

    func testOnceDailyPlayerIsNotLockedOutComparedWithTwiceDaily() throws {
        let daily = try run(Scenario(name: "12 lb / once daily", pounds: 12, weeklyLoss: 0.5))
        let twice = try run(Scenario(name: "12 lb / twice daily", pounds: 12, weeklyLoss: 0.5, visitsPerDay: 2))
        XCTAssertLessThanOrEqual(abs((daily.shopComplete ?? 999) - (twice.shopComplete ?? 0)), 7)
        XCTAssertLessThanOrEqual(abs((daily.firstBandmate ?? 999) - (twice.firstBandmate ?? 0)), 2)
    }
}
