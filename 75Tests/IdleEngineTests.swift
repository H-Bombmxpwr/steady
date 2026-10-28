import XCTest
@testable import _5

/// The idle economy. The simulations are the important ones: they play a
/// believable user against the real generator, multiplier, cap, and price
/// tables, and hold the promises the design makes —
///
/// * you can't finish the studio before your trend reaches the goal weight,
/// * you finish soon after it does, whether that's 15 lb away or 100, and
/// * if the weight stops moving, the studio stops growing.
final class IdleEngineTests: XCTestCase {

    struct SimResult {
        var endDay: Int?
        var rates: [Double] = []
        /// The rate on the day each gear tier unlocks.
        var tierRates: [Double] = []
        var log: [String] = []
    }

    /// `progressOn(day)` is the fraction of the way to goal the trend has
    /// reached — weight, standing in for whatever pace the person loses at.
    /// The user logs six of eight sound-check items, eats reasonably, opens
    /// the app twice a day, spends half of what's there on promo and the rest
    /// on gear, cheapest unlocked first.
    static func simulate(days: Int, health: Double = 0.6, logging: Double = 0.85,
                         progressOn: (Int) -> Double) -> SimResult {
        var result = SimResult()
        var notes = 60.0
        var levels: [String: Int] = [:]
        var owned = Set<String>()
        var peak = 0.0
        let forSale = StudioCatalog.forSale
        let bandIDs = Set(forSale.filter { $0.slot == .band }.map(\.id))
        let chores: [Chore] = [.weighIn, .firstFood, .threeMeals, .protein, .water, .moved]

        for d in 0..<days {
            peak = max(peak, progressOn(d))
            let p = peak
            var m = IdleEngine.Multipliers()
            m.progress = IdleEngine.progressMultiplier(p)
            m.health = IdleEngine.healthMultiplier(health)
            m.hype = IdleEngine.hypeMultiplier(choresDone: Int(Double(chores.count) * logging))
            m.collection = IdleEngine.collectionMultiplier(
                gear: owned.subtracting(bandIDs).count, bandmates: owned.intersection(bandIDs).count)
            let rate = IdleEngine.baseRate(levels: levels) * m.total
            result.rates.append(rate)

            notes += rate * 3600 * 22
            notes += chores.reduce(0) { $0 + IdleEngine.payout(for: $1, rate: rate) } * logging

            var promoBudget = notes * 0.5
            let cap = Generator.levelCap(progress: p)
            while true {
                let options = IdleEngine.generators.filter {
                    $0.unlockAt <= p + 1e-9 && (levels[$0.id] ?? 0) < cap
                        && $0.cost(level: levels[$0.id] ?? 0) <= promoBudget
                }
                guard let best = options.min(by: {
                    $0.cost(level: levels[$0.id] ?? 0) / $0.baseRate <
                    $1.cost(level: levels[$1.id] ?? 0) / $1.baseRate
                }) else { break }
                let cost = best.cost(level: levels[best.id] ?? 0)
                guard cost <= promoBudget else { break }
                promoBudget -= cost
                notes -= cost
                levels[best.id, default: 0] += 1
            }
            for gear in forSale.filter({ !owned.contains($0.id) && StudioCatalog.unlockAt($0) <= p + 1e-9 })
                .sorted(by: { StudioCatalog.price($0) < StudioCatalog.price($1) }) {
                let price = StudioCatalog.price(gear)
                guard price <= notes else { break }
                notes -= price
                owned.insert(gear.id)
            }

            if result.endDay == nil, owned.count == forSale.count, (levels["world"] ?? 0) > 0 {
                result.endDay = d
            }
            let tier = Int((p * 9 + 1e-9).rounded(.down))
            if tier > result.tierRates.count - 1 { result.tierRates.append(rate) }
            if d % 10 == 0 {
                result.log.append("day \(d) p=\(Int(p * 100))% rate=\(IdleEngine.format(rate))/s " +
                                  "notes=\(IdleEngine.format(notes)) gear=\(owned.count)/\(forSale.count)")
            }
        }
        return result
    }

    /// Steady loss: the goal is reached on `goalDay`.
    static func steady(goalDay: Int) -> (Int) -> Double {
        { min(1, Double($0) / Double(goalDay)) }
    }

    // MARK: The promises

    func testCannotFinishBeforeTheGoal() {
        for goalDay in [60, 180, 365] {
            let r = Self.simulate(days: goalDay + 120, progressOn: Self.steady(goalDay: goalDay))
            let end = try? XCTUnwrap(r.endDay, "never finished with goal on day \(goalDay)")
            XCTAssertGreaterThanOrEqual(end ?? 0, goalDay, "finished early with goal on day \(goalDay)")
        }
    }

    /// 15 lb in two months, 50 in six, 100 in a year: each maxes out the
    /// room within a couple of weeks of arriving.
    func testFinishesSoonAfterTheGoalAtAnyPace() {
        for goalDay in [60, 180, 365] {
            let r = Self.simulate(days: goalDay + 120, progressOn: Self.steady(goalDay: goalDay))
            XCTAssertLessThanOrEqual(r.endDay ?? .max, goalDay + 14, "goal on day \(goalDay)")
        }
    }

    /// The trend stalls at 30% for months. The studio should flatten, not keep
    /// compounding on time alone.
    func testStagnatesWhenWeightStalls() {
        let r = Self.simulate(days: 300) { min(0.3, Double($0) / 180) }
        let atStall = r.rates[90], monthsLater = r.rates[299]
        XCTAssertLessThan(monthsLater / atStall, 1.5,
                          "rate kept growing from \(atStall) to \(monthsLater) with no weight lost")
    }

    /// Never losing weight never gets past the first tier.
    func testNoLossNoEnd() {
        let r = Self.simulate(days: 365) { _ in 0 }
        XCTAssertNil(r.endDay)
    }

    // MARK: Pieces

    func testProgressMultiplierIsTwentyAtGoalAndDoublesOnArrival() {
        XCTAssertEqual(IdleEngine.progressMultiplier(0), 1)
        XCTAssertEqual(IdleEngine.progressMultiplier(0.5), sqrt(20), accuracy: 1e-9)
        XCTAssertEqual(IdleEngine.progressMultiplier(1), 40, accuracy: 1e-9)
    }

    func testHealthMultiplierRange() {
        XCTAssertEqual(IdleEngine.healthMultiplier(0), 0.5)
        XCTAssertEqual(IdleEngine.healthMultiplier(1), 1.5)
        XCTAssertEqual(BuddyHealth(score: 0.2), .sick)
        XCTAssertEqual(BuddyHealth(score: 0.8), .thriving)
    }

    func testJunkScoresLowAndWholeFoodHigh() {
        let fries = FoodLog(name: "Fries", calories: 500, proteinGrams: 5, grams: 150, density: "red")
        var facts = NutritionFacts()
        facts.fiberGrams = 6
        let salad = FoodLog(name: "Salad", calories: 150, proteinGrams: 6, grams: 300, density: "green", facts: facts)
        XCTAssertLessThan(IdleEngine.foodScore(fries), 0.3)
        XCTAssertGreaterThan(IdleEngine.foodScore(salad), 0.9)
    }

    /// A side salad can't launder a large pizza: quality is calorie-weighted.
    func testDayQualityIsCalorieWeighted() {
        let day = DayLog(date: Date())
        day.foods.append(FoodLog(name: "Pizza", calories: 1200, proteinGrams: 40, density: "red"))
        day.foods.append(FoodLog(name: "Side salad", calories: 60, proteinGrams: 2, density: "green"))
        XCTAssertLessThan(IdleEngine.dayQuality(day) ?? 1, 0.25)
    }

    func testGeneratorLevelCapFollowsProgress() {
        XCTAssertEqual(Generator.levelCap(progress: 0), 10)
        XCTAssertEqual(Generator.levelCap(progress: 1), 100)
    }

    func testLastTierAndWorldTourOnlyAtGoal() {
        XCTAssertEqual(IdleEngine.generator("world")?.unlockAt, 1)
        let top = StudioCatalog.forSale.max { StudioCatalog.unlockAt($0) < StudioCatalog.unlockAt($1) }
        XCTAssertEqual(top.map(StudioCatalog.unlockAt), 1)
    }

    func testFormatting() {
        XCTAssertEqual(IdleEngine.format(999), "999")
        XCTAssertEqual(IdleEngine.format(12_300), "12.3K")
        XCTAssertEqual(IdleEngine.format(4_560_000), "4.56M")
    }
}
