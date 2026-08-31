import Foundation

/// Which app Steady is, for this person. People come to a tracker for very
/// different reasons and the same dashboard can't serve all of them: someone
/// in a deficit wants a budget and a trend line, someone training for a race
/// wants today's session and what to eat around it, and plenty of people want
/// neither — they just want to eat well, move, and keep an eye on things. The
/// mode picks the dashboard, the targets, and what setup even asks about.
enum AppMode: String, Codable, CaseIterable, Identifiable {
    /// Deficit, goal weight, calorie budget, trend line. The original app.
    case weightLoss
    /// Maintenance-or-better, training load, carbs periodized to the session,
    /// sweat-rate hydration. Weight is a data point, not the point.
    case athlete
    /// No deficit, no training plan. Maintenance calories, nutrition quality,
    /// movement, cycle, and blood work — tracking for its own sake.
    case generalHealth

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weightLoss: return "Weight Loss"
        case .athlete: return "Athlete"
        case .generalHealth: return "General Health"
        }
    }

    var icon: String {
        switch self {
        case .weightLoss: return "chart.line.downtrend.xyaxis"
        case .athlete: return "figure.run"
        case .generalHealth: return "heart.text.square.fill"
        }
    }

    /// The one-liner under the picker at setup.
    var pitch: String {
        switch self {
        case .weightLoss:
            return "A calorie budget, a weight trend, and a streak. Everything points at the goal weight."
        case .athlete:
            return "Today's session up top, fuel built around it. Carbs by workout type, hydration by your own sweat rate."
        case .generalHealth:
            return "Eat at maintenance and keep an eye on the rest — fiber, sodium, movement, cycle, blood work. No deficit, no training plan."
        }
    }

    var detail: String {
        switch self {
        case .weightLoss:
            return "Best if the goal is losing weight and keeping it off. Sets a daily deficit from your pace and adapts it as the scale moves."
        case .athlete:
            return "Best if you're training for something. Imports planned workouts from TrainingPeaks, eats at maintenance plus training, and fuels each session by type, length, and intensity."
        case .generalHealth:
            return "Best if you're not chasing a number in either direction. Targets sit at maintenance, and the day is scored on what you actually did — food quality, water, movement, and whatever else you've switched on."
        }
    }

    /// Does this mode run a deliberate calorie deficit by default?
    var deficitByDefault: Bool { self == .weightLoss }

    /// Is a goal weight part of the point? Only weight loss aims at a number;
    /// the other two treat the scale as one reading among several.
    var tracksGoalWeight: Bool { self == .weightLoss }

    /// General-health mode has the health add-on built in — fiber, sodium,
    /// added sugar, and blood work are the mode, not an extra.
    var includesGeneralHealth: Bool { self == .generalHealth }
}
