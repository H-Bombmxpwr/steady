import XCTest
@testable import _5

/// Covers the arithmetic that has no UI to check it against: the iCalendar
/// reader, the TrainingPeaks interpretation, sweat rates, heat index, fueling,
/// training load, and cycle phases. All pure functions, no I/O.
final class ICSParserTests: XCTestCase {

    /// Deliberately awkward: a folded DESCRIPTION, escaped commas, a zoned
    /// start, a UTC start, an all-day event, and a rest day.
    static let feed = """
    BEGIN:VCALENDAR
    VERSION:2.0
    PRODID:-//TrainingPeaks//Calendar//EN
    BEGIN:VEVENT
    UID:tp-1001@trainingpeaks.com
    DTSTART;TZID=America/Denver:20260810T060000
    DTEND;TZID=America/Denver:20260810T080000
    SUMMARY:Bike - Sweet Spot 2x20
    DESCRIPTION:Planned Duration: 2:00\\nPlanned TSS: 130\\nPlanned Distance: 3
     5.5 mi\\nWarm up 15 min\\, then 2x20 at sweet spot.
    END:VEVENT
    BEGIN:VEVENT
    UID:tp-1002@trainingpeaks.com
    DTSTART;VALUE=DATE:20260811
    SUMMARY:Rest Day
    DESCRIPTION:Take the day off.
    END:VEVENT
    BEGIN:VEVENT
    UID:tp-1003@trainingpeaks.com
    DTSTART:20260812T113000Z
    DTEND:20260812T121500Z
    SUMMARY:Run - Recovery Shakeout
    DESCRIPTION:Easy 45 min.
    END:VEVENT
    BEGIN:VEVENT
    UID:tp-1004@trainingpeaks.com
    DTSTART;VALUE=DATE:20260813
    SUMMARY:Strength - Lower Body
    DESCRIPTION:Duration: 0:50\\nSquats and deadlifts.
    END:VEVENT
    END:VCALENDAR
    """

    func testParsesEveryEvent() {
        XCTAssertEqual(ICSParser.parse(Self.feed).count, 4)
    }

    func testUnfoldsAndUnescapesDescriptions() throws {
        let event = try XCTUnwrap(ICSParser.parse(Self.feed).first)
        let description = try XCTUnwrap(event.description)
        // "3\n 5.5 mi" folded across two lines must rejoin as "35.5 mi".
        XCTAssertTrue(description.contains("35.5 mi"))
        XCTAssertTrue(description.contains("min, then"), "escaped comma should unescape")
        XCTAssertTrue(description.contains("\n"), "\\n should become a newline")
    }

    func testReadsZonedAndUTCTimes() {
        let events = ICSParser.parse(Self.feed)
        XCTAssertEqual(events[0].minutes, 120, "zoned DTSTART/DTEND span")
        XCTAssertEqual(events[2].minutes, 45, "UTC DTSTART/DTEND span")
    }

    func testFlagsAllDayEvents() {
        let events = ICSParser.parse(Self.feed)
        XCTAssertTrue(events[1].isAllDay)
        XCTAssertFalse(events[0].isAllDay)
    }

    func testSurvivesGarbage() {
        XCTAssertTrue(ICSParser.parse("").isEmpty)
        XCTAssertTrue(ICSParser.parse("BEGIN:VCALENDAR\nEND:VCALENDAR").isEmpty)
        // A VEVENT with no DTSTART is unusable and must not crash or appear.
        XCTAssertTrue(ICSParser.parse("BEGIN:VEVENT\nSUMMARY:x\nEND:VEVENT").isEmpty)
    }
}

final class TrainingPeaksSyncTests: XCTestCase {

    private var interpreted: [TrainingPeaksSync.ParsedWorkout] {
        ICSParser.parse(ICSParserTests.feed).compactMap(TrainingPeaksSync.interpret)
    }

    func testDropsRestDays() {
        XCTAssertEqual(interpreted.count, 3, "the rest day should not become a session")
    }

    func testPlannedDurationBeatsCalendarSpan() throws {
        let ride = try XCTUnwrap(interpreted.first)
        XCTAssertEqual(ride.minutes, 120)
        XCTAssertEqual(ride.tss, 130)
        XCTAssertEqual(ride.distanceMiles, 35.5)
    }

    func testCategoryInference() throws {
        XCTAssertEqual(try XCTUnwrap(interpreted.first).category, .cardio)
        XCTAssertEqual(TrainingPeaksSync.category(for: "swim - 2000m"), .cardio)
        XCTAssertEqual(TrainingPeaksSync.category(for: "gym - upper body"), .strength)
        XCTAssertEqual(TrainingPeaksSync.category(for: "yoga flow"), .mobility)
        XCTAssertEqual(TrainingPeaksSync.category(for: "soccer match"), .sports)
        XCTAssertEqual(TrainingPeaksSync.category(for: "coach notes"), .other)
    }

    /// 100 TSS is an hour at threshold by definition, so TSS per hour recovers
    /// roughly the intensity factor.
    func testIntensityFromTSSPerHour() {
        XCTAssertEqual(TrainingPeaksSync.intensity(text: "", tss: 40, minutes: 60), .easy)
        XCTAssertEqual(TrainingPeaksSync.intensity(text: "", tss: 130, minutes: 120), .moderate)
        XCTAssertEqual(TrainingPeaksSync.intensity(text: "", tss: 100, minutes: 60), .hard)
    }

    func testSweatRateIsRescaledForSessionType() throws {
        // Measured on a hard ride, then applied to a stretching session.
        let ride = SweatTest(preWeightLbs: 150, postWeightLbs: 147.5, fluidOunces: 20,
                             minutes: 60, category: .cardio, intensity: .moderate, tempF: 70)
        let profile = try XCTUnwrap(SweatEngine.profile(tests: [ride], saltLoss: .typical))

        let mobility = FuelingEngine.plan(category: .mobility, intensity: .easy,
                                          minutes: 25, bodyweightLbs: 165, sweat: profile)
        let hardRide = FuelingEngine.plan(category: .cardio, intensity: .hard,
                                          minutes: 90, bodyweightLbs: 165, sweat: profile)
        XCTAssertLessThan(mobility.fluidOzPerHour, hardRide.fluidOzPerHour,
                          "a stretching session must not inherit a cyclist's hydration plan")
        XCTAssertEqual(mobility.sodiumMgPerHour, 0,
                       "short low-demand work needs no sodium guidance")
    }

    func testIntensityFallsBackToCoachVocabulary() {
        XCTAssertEqual(TrainingPeaksSync.intensity(text: "recovery spin", tss: nil, minutes: 60), .easy)
        XCTAssertEqual(TrainingPeaksSync.intensity(text: "vo2 intervals", tss: nil, minutes: 60), .hard)
        XCTAssertEqual(TrainingPeaksSync.intensity(text: "steady ride", tss: nil, minutes: 60), .moderate)
    }

    func testDurationFormats() {
        XCTAssertEqual(TrainingPeaksSync.duration(in: "Duration: 1:30"), 90)
        XCTAssertEqual(TrainingPeaksSync.duration(in: "Planned Duration: 01:30:00"), 90)
        XCTAssertEqual(TrainingPeaksSync.duration(in: "Long run 1h 45m"), 105)
        XCTAssertEqual(TrainingPeaksSync.duration(in: "Ride for 90 min"), 90)
        XCTAssertNil(TrainingPeaksSync.duration(in: "no duration here"))
    }

    func testAllDayEventsGetASensibleStartTime() throws {
        let lift = try XCTUnwrap(interpreted.first { $0.name.contains("Strength") })
        XCTAssertEqual(lift.hour, 7)
        XCTAssertEqual(lift.minute, 0)
        XCTAssertEqual(lift.minutes, 50)
    }

    func testURLNormalization() {
        XCTAssertEqual(
            TrainingPeaksSync.normalize("webcal://www.trainingpeaks.com/ical/ABC.ics")?.scheme,
            "https")
        XCTAssertNotNil(TrainingPeaksSync.normalize(" https://example.com/a.ics "))
        XCTAssertNil(TrainingPeaksSync.normalize("not a url"))
        XCTAssertNil(TrainingPeaksSync.normalize(""))
        XCTAssertNil(TrainingPeaksSync.normalize("ftp://example.com/a.ics"))
    }
}

final class SweatEngineTests: XCTestCase {

    /// 150 lb → 147.5 lb over an hour while drinking 20 oz.
    /// 2.5 lb lost = 1.134 L, plus 0.591 L drunk = 1.725 L/hr.
    private let test = SweatTest(preWeightLbs: 150, postWeightLbs: 147.5,
                                 fluidOunces: 20, minutes: 60,
                                 category: .cardio, intensity: .moderate, tempF: 70)

    func testSweatRateCountsFluidDrunk() {
        XCTAssertEqual(test.sweatRateLitersPerHour, 1.725, accuracy: 0.01)
        XCTAssertEqual(test.dehydrationPercent, 1.667, accuracy: 0.01)
    }

    func testRejectsImpossibleTests() {
        let absurd = SweatTest(preWeightLbs: 150, postWeightLbs: 130,
                               fluidOunces: 0, minutes: 60)
        let gained = SweatTest(preWeightLbs: 150, postWeightLbs: 151,
                               fluidOunces: 0, minutes: 60)
        XCTAssertTrue(test.isPlausible)
        XCTAssertFalse(absurd.isPlausible, "20 lb in an hour is a data-entry error")
        XCTAssertFalse(gained.isPlausible)
    }

    func testProfileExcludesImplausibleTests() throws {
        let absurd = SweatTest(preWeightLbs: 150, postWeightLbs: 130,
                               fluidOunces: 0, minutes: 60)
        let profile = try XCTUnwrap(SweatEngine.profile(tests: [test, absurd], saltLoss: .salty))
        XCTAssertEqual(profile.testCount, 1)
        XCTAssertEqual(profile.sodiumMgPerHour, 1.725 * 1500, accuracy: 5)
    }

    func testNoTestsMeansNoProfile() {
        XCTAssertNil(SweatEngine.profile(tests: [], saltLoss: .typical))
    }

    /// A rate measured on an easy ride under-calls a threshold session.
    func testScalesBetweenIntensities() throws {
        let easy = SweatTest(preWeightLbs: 150, postWeightLbs: 148.5, fluidOunces: 0,
                             minutes: 60, category: .cardio, intensity: .easy, tempF: 70)
        let forHard = try XCTUnwrap(SweatEngine.profile(tests: [easy], saltLoss: .typical,
                                                        matching: .cardio, intensity: .hard))
        let base = try XCTUnwrap(SweatEngine.profile(tests: [easy], saltLoss: .typical))
        XCTAssertGreaterThan(forHard.litersPerHour, base.litersPerHour)
    }
}

final class WeatherContextTests: XCTestCase {

    func testHeatIndexExceedsAirTemperatureWhenHumid() {
        let hot = WeatherContext(tempF: 95, humidityPercent: 70)
        XCTAssertGreaterThan(hot.heatIndexF, 95)
        XCTAssertEqual(hot.severity, .extreme)
        XCTAssertNotNil(hot.advisory)
    }

    /// The multiplier is anchored on apparent temperature, so a mild day sits
    /// near 1.0 without being exactly 1.0.
    func testMildConditionsSitNearNeutral() {
        let mild = WeatherContext(tempF: 70, humidityPercent: 50)
        XCTAssertEqual(mild.fluidMultiplier, 1.0, accuracy: 0.03)
        XCTAssertEqual(mild.severity, .mild)
        XCTAssertNil(mild.advisory)
    }

    func testColdFloorsRatherThanVanishing() {
        let freezing = WeatherContext(tempF: 20, humidityPercent: 60)
        XCTAssertEqual(freezing.fluidMultiplier, 0.85, accuracy: 0.001)
        XCTAssertEqual(freezing.severity, .cold)
        XCTAssertNotNil(freezing.advisory, "cold blunts thirst — worth saying")
    }
}

final class FuelingEngineTests: XCTestCase {

    private let base = FuelingEngine.plan(category: .cardio, intensity: .moderate,
                                          minutes: 120, bodyweightLbs: 165)

    func testEnduranceCarbsScaleWithDuration() {
        XCTAssertEqual(base.carbsPerHour, 55)
        XCTAssertEqual(base.duringCarbs, 110)
        XCTAssertEqual(
            FuelingEngine.plan(category: .cardio, intensity: .moderate,
                               minutes: 45, bodyweightLbs: 165).carbsPerHour, 0,
            "under an hour runs on stored glycogen")
    }

    func testStrengthGetsNoMidSessionCarbsButStillRecovers() {
        let lift = FuelingEngine.plan(category: .strength, intensity: .hard,
                                      minutes: 60, bodyweightLbs: 165)
        XCTAssertEqual(lift.carbsPerHour, 0)
        XCTAssertGreaterThan(lift.recoveryProtein, 0)
        XCTAssertGreaterThan(lift.preCarbs, 0)
    }

    func testMeasuredSweatOverridesTheGenericTable() throws {
        let sweatTest = SweatTest(preWeightLbs: 150, postWeightLbs: 147.5,
                                  fluidOunces: 20, minutes: 60, tempF: 70)
        let profile = try XCTUnwrap(SweatEngine.profile(tests: [sweatTest], saltLoss: .salty))
        let measured = FuelingEngine.plan(category: .cardio, intensity: .moderate,
                                          minutes: 120, bodyweightLbs: 165, sweat: profile)
        XCTAssertTrue(measured.fluidIsMeasured)
        XCTAssertFalse(base.fluidIsMeasured)
        XCTAssertEqual(measured.fluidOzPerHour, FuelingEngine.maxFluidOzPerHour,
                       "a very high sweat rate is capped at what's absorbable")
        XCTAssertTrue(measured.advisories.contains { $0.contains("capped") })
    }

    /// Heat changes what you drink, never what you eat.
    func testHeatRaisesFluidAndSodiumButNotCarbs() {
        let hot = WeatherContext(tempF: 95, humidityPercent: 70)
        let plan = FuelingEngine.plan(category: .cardio, intensity: .moderate,
                                      minutes: 120, bodyweightLbs: 165, weather: hot)
        XCTAssertGreaterThan(plan.fluidOzPerHour, base.fluidOzPerHour)
        XCTAssertGreaterThan(plan.sodiumMgPerHour, base.sodiumMgPerHour)
        XCTAssertEqual(plan.carbsPerHour, base.carbsPerHour)
    }

    func testPromptsForASweatTestWhenGuessing() {
        XCTAssertTrue(base.advisories.contains { $0.contains("sweat test") })
    }

    func testLutealPhaseNudgesFluidUp() {
        let luteal = FuelingEngine.plan(category: .cardio, intensity: .moderate,
                                        minutes: 120, bodyweightLbs: 165,
                                        cyclePhase: .luteal)
        XCTAssertGreaterThan(luteal.fluidOzPerHour, base.fluidOzPerHour)
    }
}

final class AthleteEngineTests: XCTestCase {

    private func session(_ minutes: Int, _ intensity: WorkoutIntensity,
                         tss: Double? = nil) -> TrainingSession {
        TrainingSession(PlannedWorkout(date: Date(), name: "S", minutes: minutes,
                                       category: .cardio, intensity: intensity, tss: tss))
    }

    func testLoadFromDurationAndIntensity() {
        XCTAssertEqual(AthleteEngine.load(for: []), .rest)
        XCTAssertEqual(AthleteEngine.load(for: [session(60, .easy)]), .light)
        XCTAssertEqual(AthleteEngine.load(for: [session(240, .moderate)]), .extreme)
    }

    func testPublishedTSSOutranksDuration() {
        XCTAssertEqual(AthleteEngine.load(for: [session(60, .easy, tss: 300)]), .extreme,
                       "a short but brutal session is not a light day")
    }

    /// 100 TSS is one hour at threshold — a normal hard hour, not a big day.
    func testAnOrdinaryHardHourIsAModerateDay() {
        XCTAssertEqual(AthleteEngine.load(for: [session(90, .hard, tss: 95)]), .moderate)
        XCTAssertEqual(AthleteEngine.load(for: [session(240, .moderate, tss: 210)]), .heavy)
    }

    /// Carbs must leave room for the protein target and the fat floor, or the
    /// day's calories get pushed above maintenance-plus-training by the macros.
    func testCarbTargetLeavesRoomForFat() {
        let kg = 64.4
        for load in TrainingLoad.allCases {
            let carbCalories = load.carbsPerKg * kg * 4
            let proteinCalories = load.proteinPerKg * kg * 4
            let fatFloorCalories = kg * 0.7 * 9
            // A heavy day at maintenance (~1800) plus ~1000 of training.
            XCTAssertLessThan(carbCalories + proteinCalories + fatFloorCalories, 4200,
                              "\(load.label) macros overshoot a realistic day")
        }
    }

    func testCarbsAndProteinClimbWithLoad() {
        XCTAssertLessThan(TrainingLoad.rest.carbsPerKg, TrainingLoad.moderate.carbsPerKg)
        XCTAssertLessThan(TrainingLoad.moderate.carbsPerKg, TrainingLoad.extreme.carbsPerKg)
        XCTAssertLessThanOrEqual(TrainingLoad.rest.proteinPerKg, TrainingLoad.heavy.proteinPerKg)
    }
}

final class CycleEngineTests: XCTestCase {

    private func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date())!
    }

    /// Starts 84, 56, 28 and 2 days ago — gaps of 28, 28 and 26 days.
    private var history: [CycleEntry] {
        [CycleEntry(startDate: daysAgo(84), endDate: daysAgo(79)),
         CycleEntry(startDate: daysAgo(56), endDate: daysAgo(51)),
         CycleEntry(startDate: daysAgo(28), endDate: daysAgo(23)),
         CycleEntry(startDate: daysAgo(2))]
    }

    func testLearnsCycleLengthFromHistory() throws {
        let status = try XCTUnwrap(CycleEngine.status(entries: history))
        XCTAssertEqual(status.cycleLength, 27, "mean of 28, 28 and 26")
        XCTAssertEqual(status.dayOfCycle, 3)
        XCTAssertEqual(status.phase, .menstrual)
        XCTAssertFalse(status.isEstimate)
    }

    func testPredictsTheNextStart() throws {
        let status = try XCTUnwrap(CycleEngine.status(entries: history))
        let days = try XCTUnwrap(status.daysUntilNext)
        XCTAssertTrue((24...26).contains(days), "got \(days)")
    }

    func testPhaseBoundariesOnADefaultCycle() throws {
        func phase(dayOfCycle: Int) throws -> CyclePhase {
            try XCTUnwrap(CycleEngine.status(
                entries: [CycleEntry(startDate: daysAgo(dayOfCycle - 1))])?.phase)
        }
        XCTAssertEqual(try phase(dayOfCycle: 2), .menstrual)
        XCTAssertEqual(try phase(dayOfCycle: 10), .follicular)
        XCTAssertEqual(try phase(dayOfCycle: 14), .ovulatory)
        XCTAssertEqual(try phase(dayOfCycle: 21), .luteal)
    }

    func testNoLogsMeansNoPhase() {
        XCTAssertNil(CycleEngine.status(entries: []),
                     "guessing a phase with no data would be theatre")
    }

    func testIgnoresImplausibleGaps() {
        // A year-long gap is a missed log, not a cycle.
        let sparse = [CycleEntry(startDate: daysAgo(400)),
                      CycleEntry(startDate: daysAgo(30)),
                      CycleEntry(startDate: daysAgo(2))]
        XCTAssertEqual(CycleEngine.averageCycleLength(sparse).length, 28)
    }
}
