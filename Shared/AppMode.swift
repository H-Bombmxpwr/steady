import Foundation

/// Which app Steady is, for this person. People come to a tracker for very
/// different reasons and the same dashboard can't serve both: someone in a
/// deficit wants a budget and a trend line, someone training for a race wants
/// today's session and what to eat around it. The mode picks the dashboard,
/// the targets, and what the setup flow even asks about.
enum AppMode: String, Codable, CaseIterable, Identifiable {
    /// Deficit, goal weight, calorie budget, trend line. The original app.
    case weightLoss
    /// Maintenance-or-better, training load, carbs periodized to the session,
    /// sweat-rate hydration. Weight is a data point, not the point.
    case athlete

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weightLoss: return "Weight Loss"
        case .athlete: return "Athlete"
        }
    }

    var icon: String {
        switch self {
        case .weightLoss: return "chart.line.downtrend.xyaxis"
        case .athlete: return "figure.run"
        }
    }

    /// The one-liner under the picker at setup.
    var pitch: String {
        switch self {
        case .weightLoss:
            return "A calorie budget, a weight trend, and a streak. Everything points at the goal weight."
        case .athlete:
            return "Today's session up top, fuel built around it. Carbs by workout type, hydration by your own sweat rate."
        }
    }

    var detail: String {
        switch self {
        case .weightLoss:
            return "Best if the goal is losing weight and keeping it off. Sets a daily deficit from your pace and adapts it as the scale moves."
        case .athlete:
            return "Best if you're training for something. Imports planned workouts from TrainingPeaks, eats at maintenance plus training, and fuels each session by type, length, and intensity."
        }
    }

    /// Does this mode run a deliberate calorie deficit by default?
    var deficitByDefault: Bool { self == .weightLoss }
}
