import SwiftUI
import Charts

/// Progressive-overload history for one exercise, pulled from every logged
/// set across the plan. Shows top-set weight over time (or rep volume for
/// bodyweight movements).
struct ExerciseHistorySection: View {
    var plan: Plan
    let exerciseName: String

    private struct Point: Identifiable {
        let date: Date
        let topWeight: Double
        let totalReps: Int
        var id: Date { date }
    }

    private var history: [Point] {
        plan.days
            .sorted { $0.date < $1.date }
            .compactMap { day in
                let sets = day.workouts.flatMap { $0.sets }.filter { $0.exerciseName == exerciseName }
                guard !sets.isEmpty else { return nil }
                return Point(date: day.date,
                             topWeight: sets.compactMap { $0.weightLbs }.max() ?? 0,
                             totalReps: sets.reduce(0) { $0 + $1.reps })
            }
    }

    var body: some View {
        let points = history
        if !points.isEmpty {
            Section("Progress") {
                let hasWeight = points.contains { $0.topWeight > 0 }
                if hasWeight, points.count >= 2 {
                    Chart(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Top set", p.topWeight))
                            .foregroundStyle(Theme.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        PointMark(x: .value("Date", p.date), y: .value("Top set", p.topWeight))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(height: 140)
                    .padding(.vertical, 4)
                }
                ForEach(points.suffix(3).reversed()) { p in
                    HStack {
                        Text(p.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text(p.topWeight > 0
                             ? "top \(p.topWeight.formatted()) lb · \(p.totalReps) reps"
                             : "\(p.totalReps) reps")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
        }
    }
}
