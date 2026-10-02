import Foundation
import EventKit

/// Writes the workout schedule into the user's calendar via EventKit —
/// fully local, no server. Each schedule entry becomes one weekly-recurring
/// event; re-syncing replaces previously created events.
enum CalendarSync {

    enum SyncError: LocalizedError {
        case accessDenied
        var errorDescription: String? {
            "Calendar access was denied. Enable it in iOS Settings → Privacy → Calendars."
        }
    }

    @discardableResult
    static func sync(plan: Plan) async throws -> Int {
        let store = EKEventStore()
        let granted = try await store.requestWriteOnlyAccessToEvents()
        guard granted else { throw SyncError.accessDenied }

        // Remove previously synced events first so re-sync doesn't duplicate.
        removeSyncedEvents(plan: plan, store: store)

        guard let calendar = store.defaultCalendarForNewEvents else { throw SyncError.accessDenied }
        let cal = Calendar.current
        var created = 0

        for entry in plan.schedule {
            // First occurrence: the next date matching the entry's weekday/time.
            var comps = DateComponents()
            comps.weekday = entry.weekday
            comps.hour = entry.hour
            comps.minute = entry.minute
            guard let start = cal.nextDate(after: Date(), matching: comps,
                                           matchingPolicy: .nextTimePreservingSmallerComponents) else { continue }

            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = "Workout: \(entry.name)"
            event.notes = "Planned in Steady — \(entry.minutes) min"
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(entry.minutes * 60))
            event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))

            try store.save(event, span: .futureEvents, commit: false)
            entry.calendarEventID = event.eventIdentifier
            created += 1
        }
        try store.commit()
        return created
    }

    static func removeFromCalendar(plan: Plan) async throws {
        let store = EKEventStore()
        let granted = try await store.requestWriteOnlyAccessToEvents()
        guard granted else { throw SyncError.accessDenied }
        removeSyncedEvents(plan: plan, store: store)
        try store.commit()
    }

    /// Pull the events belonging to entries that are about to be deleted.
    ///
    /// `removeSyncedEvents` walks `plan.schedule`, so it can only clean up
    /// entries that are still on it — once an entry is gone, the weekly event
    /// it created is unreachable and repeats in the user's calendar forever.
    ///
    /// Takes identifiers rather than the entries themselves: the caller reads
    /// them off before deleting, because this is async and the objects won't
    /// survive long enough to be asked.
    ///
    /// Best-effort by design — calendar access may never have been granted,
    /// and a denied prompt must not stop the entry itself being deleted.
    static func removeEvents(ids: [String]) async {
        guard !ids.isEmpty else { return }
        let store = EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return }
        for id in ids {
            if let event = store.event(withIdentifier: id) {
                try? store.remove(event, span: .futureEvents, commit: false)
            }
        }
        try? store.commit()
    }

    private static func removeSyncedEvents(plan: Plan, store: EKEventStore) {
        for entry in plan.schedule {
            if let id = entry.calendarEventID, let event = store.event(withIdentifier: id) {
                try? store.remove(event, span: .futureEvents, commit: false)
            }
            entry.calendarEventID = nil
        }
    }
}
