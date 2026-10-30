import XCTest
@testable import _5

final class IdleEngineTests: XCTestCase {
    func testLoggingOpensShopWithoutWeightLoss() {
        XCTAssertEqual(IdleEngine.studioProgress(weight: 0, loggingDays: 7), 1.0 / 9, accuracy: 1e-9)
        XCTAssertEqual(IdleEngine.studioProgress(weight: 0, loggingDays: 63), 1)
        XCTAssertEqual(IdleEngine.studioProgress(weight: 0.5, loggingDays: 7), 0.5)
        XCTAssertEqual(IdleEngine.studioProgress(weight: 0, loggingDays: 1000), 1)
    }

    func testExplicitTiersCoverEverySaleItemExactlyOnce() {
        let ids = StudioCatalog.tierItems.flatMap { $0 }
        XCTAssertEqual(Set(ids), Set(StudioCatalog.forSale.map(\.id)))
        XCTAssertEqual(ids.count, Set(ids).count)
        for tier in 1..<StudioCatalog.tierCount {
            XCTAssertTrue(StudioCatalog.tierItems[tier].contains { $0.hasPrefix("band.") })
        }
        XCTAssertEqual(StudioCatalog.tier(StudioCatalog.gear("band.snail")!), 1)
        XCTAssertEqual(StudioCatalog.price(StudioCatalog.gear("coffee")!), 30)
    }

    func testNoLossOrInvalidGoalCannotCompleteWeightProgress() {
        XCTAssertEqual(IdleEngine.goalProgress(start: 200, goal: 200, best: 200), 0)
        XCTAssertEqual(IdleEngine.goalProgress(start: 200, goal: 210, best: 200), 0)
        XCTAssertEqual(IdleEngine.goalProgress(start: 200, goal: 150, best: 190), 0.2, accuracy: 1e-9)
    }

    func testNutritionBonusDoesNotJudgeCalorieDensityOrPunishMissingData() {
        let targets = DailyTargets(calories: 2000, proteinGrams: 150, waterOunces: 96)
        let day = DayLog(date: Date())
        XCTAssertEqual(IdleEngine.healthMultiplier(IdleEngine.nutritionScore(day, targets: targets)), 1)
        var facts = NutritionFacts()
        facts.fiberGrams = 5
        let nuts = FoodLog(name: "Nuts", calories: 300, proteinGrams: 10, grams: 50, density: "red", facts: facts)
        day.foods.append(nuts)
        let redScore = IdleEngine.nutritionScore(day, targets: targets)
        nuts.density = "green"
        XCTAssertEqual(IdleEngine.nutritionScore(day, targets: targets), redScore)
        XCTAssertGreaterThan(IdleEngine.healthMultiplier(redScore), 1)
        XCTAssertEqual(IdleEngine.healthMultiplier(1), 1.25)
        XCTAssertEqual(BuddyHealth(score: 0), .okay)
    }

    func testOldCoffeePlacementMovesToTableAndRestoresRadio() throws {
        let data = Data(#"{"owned":["radio","coffee"],"placed":{"shelf":"coffee"},"recordsBought":2}"#.utf8)
        let state = try JSONDecoder().decode(BuddyState.self, from: data)
        XCTAssertEqual(state.placed["table"], "coffee")
        XCTAssertEqual(state.placed["shelf"], "radio")
        XCTAssertEqual(state.recordsBought, 2) // Old saves still decode.
        XCTAssertEqual(StudioCatalog.migratePlacement(state.placed, owned: state.owned), state.placed)
        let occupied = StudioCatalog.migratePlacement(["shelf": "coffee", "table": "candle"],
                                                       owned: ["radio", "coffee", "candle"])
        XCTAssertEqual(occupied["table"], "candle")
    }

    func testJarUsesHistoricalRatesAcrossMidnightAndRateChanges() {
        let start = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 18))!
        var jar = RoyaltyJar(at: start, rate: 2, overnightRate: 1)
        XCTAssertEqual(jar.amount(at: start.addingTimeInterval(12 * 3600)), 18 * 3600)
        jar.update(at: start.addingTimeInterval(12 * 3600), rate: 10, overnightRate: 5)
        XCTAssertEqual(jar.amount(at: start.addingTimeInterval(13 * 3600)), 28 * 3600)
        XCTAssertEqual(jar.fullAt, start.addingTimeInterval(24 * 3600))
        XCTAssertEqual(jar.amount(at: start.addingTimeInterval(72 * 3600)), 138 * 3600)
        jar.update(at: start.addingTimeInterval(72 * 3600), rate: 100, overnightRate: 100)
        XCTAssertEqual(jar.amount(at: start.addingTimeInterval(80 * 3600)), 138 * 3600)
    }

    func testOnceAndTwiceDailyCollectionsEarnSameAtFixedRates() {
        let start = Calendar.current.startOfDay(for: Date())
        let full = RoyaltyJar(at: start, rate: 10, overnightRate: 10)
        let second = RoyaltyJar(at: start.addingTimeInterval(12 * 3600), rate: 10, overnightRate: 10)
        XCTAssertEqual(full.amount(at: start.addingTimeInterval(24 * 3600)),
                       full.amount(at: start.addingTimeInterval(12 * 3600)) +
                       second.amount(at: start.addingTimeInterval(24 * 3600)))
    }

    func testWidgetUsesSettledJarAndDropsHypeAtMidnight() {
        let start = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 18))!
        var jar = RoyaltyJar(at: start, rate: 2, overnightRate: 1)
        jar.update(at: start.addingTimeInterval(3600), rate: 4, overnightRate: 2)
        let widget = BuddyWidgetStats(name: "Test", asset: "Studio/penguin", notes: 0,
                                      rate: 4, jarSince: start, jarHours: 24, health: "okay",
                                      healthMultiplier: 1, records: 0, track: 1,
                                      trackCount: 10, toNextTrack: 5, progress: 0, royaltyJar: jar)
        let morning = start.addingTimeInterval(12 * 3600)
        XCTAssertEqual(widget.jar(at: morning), (2 + 5 * 4 + 6 * 2) * 3600)
        XCTAssertEqual(widget.currentRate(at: morning), 2)
        XCTAssertEqual(widget.jarFullAt, start.addingTimeInterval(24 * 3600))
    }

    func testFormatting() {
        XCTAssertEqual(IdleEngine.format(999), "999")
        XCTAssertEqual(IdleEngine.format(12_300), "12.3K")
        XCTAssertEqual(IdleEngine.format(4_560_000), "4.56M")
    }
}

@MainActor
final class BuddyEconomyTransactionTests: XCTestCase {
    private let targets = DailyTargets(calories: 2000, proteinGrams: 150, waterOunces: 96)
    private var now = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 1, hour: 18))!

    private func fixture() -> (Plan, BuddyStore) {
        let plan = Plan(startDate: now, startingWeight: 200, goalWeight: 150,
                        paceLbsPerWeek: 1, proteinTargetGrams: 150)
        let store = BuddyStore(initialState: BuddyState(), clock: { self.now })
        store.setUp(species: .penguin, name: "Test", startWeight: 200, startDate: now, goalWeight: 150)
        return (plan, store)
    }

    func testGoalEditsDoNotChangeActiveTourOrUnlockShop() {
        let (plan, store) = fixture()
        let day = DayLog(date: now)
        day.weight = 190
        plan.days = [day]
        store.sync(plan: plan, targets: targets)
        XCTAssertEqual(store.state.peakProgress, 0.2, accuracy: 1e-9)
        plan.goalWeight = 190
        store.sync(plan: plan, targets: targets)
        XCTAssertEqual(store.tour(plan: plan).goal, 150)
        XCTAssertEqual(store.state.peakProgress, 0.2, accuracy: 1e-9)
        plan.goalWeight = 150
        store.sync(plan: plan, targets: targets)
        XCTAssertFalse(store.isUnlocked(IdleEngine.generator("world")!))
    }

    func testNewTourResetsWeightProgressButKeepsOwnedItemsAndLogging() {
        let (plan, store) = fixture()
        let day = DayLog(date: now)
        day.weight = 190
        day.caloriesEaten = 2000
        day.waterOunces = 96
        plan.days = [day]
        store.sync(plan: plan, targets: targets)
        let coffee = StudioCatalog.gear("coffee")!
        XCTAssertTrue(store.buy(coffee, price: StudioCatalog.price(coffee), plan: plan, targets: targets))
        let notes = store.notes
        store.startNewTour(plan: plan, targets: targets)
        store.sync(plan: plan, targets: targets)
        XCTAssertEqual(store.tour(plan: plan).start, 190)
        XCTAssertEqual(store.state.peakProgress, 0)
        XCTAssertEqual(store.state.loggingDays.count, 1)
        XCTAssertTrue(store.owns(coffee))
        XCTAssertEqual(store.notes, notes)
    }

    func testGearAndProgressChangesCannotRepricePastIncome() {
        let (plan, store) = fixture()
        XCTAssertTrue(store.buy(IdleEngine.generator("busk")!, plan: plan, targets: targets))
        now = now.addingTimeInterval(3600)
        let before = store.jar(at: now)
        XCTAssertEqual(before, 360, accuracy: 1e-6)
        XCTAssertTrue(store.buy(StudioCatalog.gear("coffee")!, price: 30, plan: plan, targets: targets))
        XCTAssertEqual(store.jar(at: now), before, accuracy: 1e-6)
        let day = DayLog(date: now)
        day.weight = 175
        plan.days = [day]
        store.sync(plan: plan, targets: targets)
        XCTAssertEqual(store.jar(at: now), before, accuracy: 1e-6)
        now = now.addingTimeInterval(3600)
        XCTAssertGreaterThan(store.jar(at: now), before + 360)
    }

    func testWeeklyRecordsAndChoresAreIdempotentAcrossReload() throws {
        let (plan, store) = fixture()
        for offset in 0..<7 {
            let day = DayLog(date: Calendar.current.date(byAdding: .day, value: -offset, to: now)!)
            day.weight = 200
            day.caloriesEaten = 2000
            day.waterOunces = 96
            plan.days.append(day)
        }
        plan.startDate = plan.days.last!.date
        store.sync(plan: plan, targets: targets)
        XCTAssertEqual(store.state.loggingDays.count, 7)
        XCTAssertEqual(store.state.digs, 1)
        let notes = store.notes
        let saved = try JSONEncoder().encode(store.state)
        let reloaded = BuddyStore(initialState: try JSONDecoder().decode(BuddyState.self, from: saved), clock: { self.now })
        XCTAssertTrue(reloaded.sync(plan: plan, targets: targets).isEmpty)
        XCTAssertEqual(reloaded.notes, notes)
        XCTAssertEqual(reloaded.state.digs, 1)
    }

    func testLegacyStateRetainsPurchasesAndMigratesWithoutInstantCompletion() throws {
        let legacy = Data(#"{"notes":12345,"generators":{"busk":10},"owned":["coffee"],"peakProgress":1}"#.utf8)
        let state = try JSONDecoder().decode(BuddyState.self, from: legacy)
        let (plan, _) = fixture()
        let store = BuddyStore(initialState: state, clock: { self.now })
        store.sync(plan: plan, targets: targets)
        XCTAssertEqual(store.state.peakProgress, 0)
        XCTAssertTrue(store.owns(StudioCatalog.gear("coffee")!))
        XCTAssertEqual(store.level(IdleEngine.generator("busk")!), 10)
        XCTAssertEqual(store.notes, 12345)
    }
}
