import XCTest
@testable import _5

/// The weekly schedule stores a workout's *name*, not a reference to it — so
/// that a one-off nobody built as a workout can still go on the week. The cost
/// is that deleting or renaming a workout can strand its weekday slots, and a
/// stranded slot is indistinguishable from a real one to every screen
/// downstream: it keeps adding calories and keeps turning up on its weekday.
/// These pin the cleanup.
final class WorkoutScheduleTests: XCTestCase {

    private func plan() -> Plan {
        Plan(startDate: Date(), startingWeight: 170, goalWeight: 170,
             paceLbsPerWeek: 0, proteinTargetGrams: 170)
    }

    private func friday() -> Date {
        let cal = Calendar.current
        var d = cal.startOfDay(for: Date())
        while cal.component(.weekday, from: d) != 6 { d = cal.date(byAdding: .day, value: 1, to: d)! }
        return d
    }

    // MARK: Finding a workout's slots

    func testFindsEverySlotAWorkoutPutOnTheWeek() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: "Pickleball", minutes: 60))
        p.schedule.append(WorkoutScheduleEntry(weekday: 7, name: "Pickleball", minutes: 90))
        p.schedule.append(WorkoutScheduleEntry(weekday: 2, name: "Upper Body"))

        XCTAssertEqual(p.scheduleEntries(named: "Pickleball").count, 2)
        XCTAssertEqual(Set(p.scheduleEntries(named: "Pickleball").map(\.weekday)), [6, 7])
    }

    func testNameMatchIgnoresCaseAndStraySpace() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: "Pickleball"))

        XCTAssertEqual(p.scheduleEntries(named: "  pickleball ").count, 1)
    }

    /// An empty name must not sweep up every custom entry that was saved
    /// without one.
    func testAnEmptyNameMatchesNothing() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: ""))

        XCTAssertTrue(p.scheduleEntries(named: "").isEmpty)
        XCTAssertTrue(p.scheduleEntries(named: "   ").isEmpty)
    }

    // MARK: Removal

    /// The bug, exactly: the slots came off the store but stayed on the plan's
    /// own array, so the week went on reporting the session.
    func testRemovedSlotsStopShowingUpOnTheirWeekday() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: "Pickleball", minutes: 60))
        p.schedule.append(WorkoutScheduleEntry(weekday: 7, name: "Pickleball", minutes: 90))
        let fri = friday()
        XCTAssertFalse(p.scheduledWorkouts(on: fri).isEmpty)

        p.removeScheduleEntries(p.scheduleEntries(named: "Pickleball"))

        XCTAssertTrue(p.schedule.isEmpty)
        XCTAssertTrue(p.scheduledWorkouts(on: fri).isEmpty)
        XCTAssertTrue(p.allSessions(on: fri).isEmpty)
        XCTAssertFalse(p.isWorkoutScheduled(on: fri))
    }

    func testRemovalLeavesTheOtherDaysAlone() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: "Pickleball"))
        p.schedule.append(WorkoutScheduleEntry(weekday: 2, name: "Upper Body"))

        p.removeScheduleEntries(p.scheduleEntries(named: "Pickleball"))

        XCTAssertEqual(p.schedule.map(\.name), ["Upper Body"])
    }

    func testRemovingNothingIsHarmless() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 2, name: "Upper Body"))

        p.removeScheduleEntries([])
        p.removeScheduleEntries(p.scheduleEntries(named: "Pickleball"))

        XCTAssertEqual(p.schedule.count, 1)
    }

    // MARK: Renaming

    func testRenamingAWorkoutCarriesToItsSlots() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: "Pickleball"))
        p.schedule.append(WorkoutScheduleEntry(weekday: 7, name: "Pickleball"))
        p.schedule.append(WorkoutScheduleEntry(weekday: 2, name: "Upper Body"))

        p.renameScheduleEntries(from: "Pickleball", to: "Padel")

        XCTAssertTrue(p.scheduleEntries(named: "Pickleball").isEmpty)
        XCTAssertEqual(p.scheduleEntries(named: "Padel").count, 2)
        XCTAssertEqual(p.scheduleEntries(named: "Upper Body").count, 1)
    }

    /// A half-typed field clearing the name off the week would be worse than
    /// the stale name it replaced.
    func testRenamingToNothingIsIgnored() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: "Pickleball"))

        p.renameScheduleEntries(from: "Pickleball", to: "   ")

        XCTAssertEqual(p.schedule.map(\.name), ["Pickleball"])
    }

    func testRenamingToTheSameNameIsANoOp() {
        let p = plan()
        p.schedule.append(WorkoutScheduleEntry(weekday: 6, name: "Pickleball"))

        p.renameScheduleEntries(from: "Pickleball", to: "Pickleball")

        XCTAssertEqual(p.schedule.map(\.name), ["Pickleball"])
    }
}
