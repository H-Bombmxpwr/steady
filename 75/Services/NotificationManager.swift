import Foundation
import UserNotifications

/// Local-notification scheduling. Reminder times are user-configurable;
/// the streak guard is a smart one-off scheduled when today is actually
/// at risk (plus a next-day fallback).
enum NotificationManager {

    static let logWaterAction = "LOG_WATER"
    static let hydrationCategory = "HYDRATION"

    enum Keys {
        static let weighInEnabled = "notify.weighIn"
        static let weighInHour = "notify.weighIn.hour"
        static let hydrationEnabled = "notify.hydration"
        static let hydrationTimes = "notify.hydration.times"     // "11:00,15:00,19:00"
        static let workoutEnabled = "notify.workout"
        static let workoutLeadMinutes = "notify.workout.lead"    // minutes before
        static let streakEnabled = "notify.streak"
        static let streakHour = "notify.streak.hour"
        static let streakMinute = "notify.streak.minute"
    }

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        registerCategories()
        return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func registerCategories() {
        let logWater = UNNotificationAction(identifier: logWaterAction,
                                            title: "Log a bottle",
                                            options: [])
        let hydration = UNNotificationCategory(identifier: hydrationCategory,
                                               actions: [logWater],
                                               intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([hydration])
    }

    static func hydrationTimes() -> [(hour: Int, minute: Int)] {
        let raw = UserDefaults.standard.string(forKey: Keys.hydrationTimes) ?? "11:00,15:00,19:00"
        return raw.split(separator: ",").compactMap { part in
            let bits = part.split(separator: ":")
            guard bits.count == 2, let h = Int(bits[0]), let m = Int(bits[1]) else { return nil }
            return (h, m)
        }
    }

    /// Clears and re-schedules the repeating reminders from settings + plan.
    static func rescheduleAll(plan: Plan) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let d = UserDefaults.standard

        // Morning weigh-in
        if d.object(forKey: Keys.weighInEnabled) as? Bool ?? true {
            let hour = d.object(forKey: Keys.weighInHour) as? Int ?? 8
            schedule(id: "weighin",
                     title: "Morning weigh-in",
                     body: "Step on the scale before breakfast — trend weight works best with daily data.",
                     hour: hour, minute: 0)
        }

        // Hydration nudges (configurable times, with a quick-log action)
        if d.object(forKey: Keys.hydrationEnabled) as? Bool ?? true {
            for (i, t) in hydrationTimes().enumerated() {
                schedule(id: "hydration\(i)",
                         title: "Hydration check",
                         body: "Behind on water? Tap to log \(plan.waterStepOunces) oz.",
                         hour: t.hour, minute: t.minute,
                         category: hydrationCategory)
            }
        }

        // Scheduled workouts (per weekday, configurable lead time)
        if d.object(forKey: Keys.workoutEnabled) as? Bool ?? true {
            let lead = d.object(forKey: Keys.workoutLeadMinutes) as? Int ?? 30
            for entry in plan.schedule {
                var total = entry.hour * 60 + entry.minute - lead
                if total < 0 { total += 24 * 60 }
                schedule(id: "workout-\(entry.weekday)-\(entry.hour)-\(entry.minute)",
                         title: "\(entry.name) in \(lead) minutes",
                         body: "\(entry.minutes) min planned. Get changed now and it's already half done.",
                         hour: total / 60, minute: total % 60,
                         weekday: entry.weekday)
            }
        }

        // Supplements — daily or weekly
        for s in plan.supplements where s.remind {
            schedule(id: "supplement-\(s.name)",
                     title: "Take your \(s.name)",
                     body: "Check it off in today's log.",
                     hour: s.hour, minute: s.minute,
                     weekday: s.frequency == .weekly ? s.weekday : nil)
        }
    }

    /// Smart streak guard: called when the app goes to background. If today's
    /// goals are unmet and a streak is on the line, schedule a one-off alert
    /// at the configured evening time; always keep a fallback for tomorrow.
    static func updateStreakGuard(todayMet: Bool, streak: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["streak-today", "streak-tomorrow"])
        let d = UserDefaults.standard
        guard d.object(forKey: Keys.streakEnabled) as? Bool ?? true else { return }
        let hour = d.object(forKey: Keys.streakHour) as? Int ?? 20
        let minute = d.object(forKey: Keys.streakMinute) as? Int ?? 30
        let cal = Calendar.current

        let title = streak > 0 ? "🔥 \(streak)-day streak on the line" : "Finish the day strong"
        let body = "A few goals are still open — water, protein, or your photo?"

        if !todayMet {
            var comps = cal.dateComponents([.year, .month, .day], from: Date())
            comps.hour = hour; comps.minute = minute
            if let fire = cal.date(from: comps), fire > Date() {
                oneOff(id: "streak-today", title: title, body: body, at: fire)
            }
        }
        // Fallback for tomorrow in case the app isn't opened at all.
        var comps = cal.dateComponents([.year, .month, .day],
                                       from: cal.date(byAdding: .day, value: 1, to: Date())!)
        comps.hour = hour; comps.minute = minute
        if let fire = cal.date(from: comps) {
            oneOff(id: "streak-tomorrow", title: "Protect the streak", body: body, at: fire)
        }
    }

    private static func oneOff(id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    private static func schedule(id: String, title: String, body: String,
                                 hour: Int, minute: Int,
                                 weekday: Int? = nil,
                                 category: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        comps.weekday = weekday

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
