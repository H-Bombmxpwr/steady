import Foundation
import UserNotifications

/// Local-notification scheduling. All reminders are daily/weekly repeating
/// calendar triggers; everything is configurable from Settings.
enum NotificationManager {

    static let logWaterAction = "LOG_WATER"
    static let hydrationCategory = "HYDRATION"

    // AppStorage-backed keys (read via UserDefaults so the widget-free
    // scheduling code doesn't need SwiftUI).
    enum Keys {
        static let weighInEnabled = "notify.weighIn"
        static let weighInHour = "notify.weighIn.hour"
        static let hydrationEnabled = "notify.hydration"
        static let workoutEnabled = "notify.workout"
        static let streakEnabled = "notify.streak"
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

    /// Clears and re-schedules everything from current settings + plan.
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

        // Hydration nudges (with a quick-log action)
        if d.object(forKey: Keys.hydrationEnabled) as? Bool ?? true {
            for (i, hour) in [11, 15, 19].enumerated() {
                schedule(id: "hydration\(i)",
                         title: "Hydration check",
                         body: "Behind on water? Tap to log \(plan.waterStepOunces) oz.",
                         hour: hour, minute: 0,
                         category: hydrationCategory)
            }
        }

        // Scheduled workouts (per weekday, 30 min before planned time)
        if d.object(forKey: Keys.workoutEnabled) as? Bool ?? true {
            for entry in plan.schedule {
                var hour = entry.hour
                var minute = entry.minute - 30
                if minute < 0 { minute += 60; hour = max(0, hour - 1) }
                schedule(id: "workout-\(entry.weekday)",
                         title: "\(entry.name) in 30 minutes",
                         body: "\(entry.minutes) min planned. Get changed now and it's already half done.",
                         hour: hour, minute: minute,
                         weekday: entry.weekday)
            }
        }

        // Evening streak guard
        if d.object(forKey: Keys.streakEnabled) as? Bool ?? true {
            schedule(id: "streak",
                     title: "Protect the streak",
                     body: "A few goals are still open today — water, protein, or your photo?",
                     hour: 20, minute: 30)
        }

        // Supplements
        for s in plan.supplements where s.remind {
            schedule(id: "supplement-\(s.name)",
                     title: "Take your \(s.name)",
                     body: "Check it off in today's log.",
                     hour: s.hour, minute: s.minute)
        }
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
