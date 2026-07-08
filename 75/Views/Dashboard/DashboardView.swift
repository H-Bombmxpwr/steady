import SwiftUI
import SwiftData
import Charts

struct MainTabView: View {
    var plan: Plan
    var profile: UserProfile

    var body: some View {
        TabView {
            DashboardView(plan: plan, profile: profile)
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
            CalendarScreen(plan: plan, profile: profile)
                .tabItem { Label("Calendar", systemImage: "calendar") }
            PhotosGalleryView(plan: plan)
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
            WorkoutsView(plan: plan)
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
            SettingsView(plan: plan, profile: profile)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    var profile: UserProfile
    @State private var today = Calendar.current.startOfDay(for: Date())

    private var dayNumber: Int { max(0, plan.startDate.days(to: today)) + 1 }
    private var todayLog: DayLog { ensureDay(plan: plan, date: today) }
    private var targets: DailyTargets { CalorieEngine.targets(profile: profile, plan: plan) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    WeightCard(plan: plan)

                    TodayCard(day: todayLog, targets: targets, plan: plan)

                    HStack(spacing: 14) {
                        StreakCard(stats: CalorieEngine.streakStats(plan: plan, targets: targets))
                        ProjectionCard(plan: plan, dayNumber: dayNumber)
                    }

                    InsightCard(insight: CalorieEngine.weeklyInsight(plan: plan, targets: targets))

                    NavigationLink(value: today) {
                        Label("Open Today", systemImage: "square.and.pencil")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationDestination(for: Date.self) { d in
                DayDetailView(plan: plan, profile: profile, date: d)
            }
            .navigationTitle("Day \(dayNumber)")
        }
    }
}

// MARK: - Weight + trend chart

private struct WeightCard: View {
    let plan: Plan

    var body: some View {
        Card(title: "Weight") {
            let trend = CalorieEngine.weightTrend(plan: plan)
            let headline = trend.last?.trend ?? plan.startingWeight

            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f", headline))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text("lb trend").foregroundStyle(Theme.textDim)
                Spacer()
                let delta = headline - plan.startingWeight
                Text(String(format: "%@%.1f lb", delta > 0 ? "+" : "", delta))
                    .font(.headline)
                    .foregroundStyle(delta <= 0 ? Theme.accent : Theme.danger)
            }

            if trend.count >= 2 {
                Chart {
                    ForEach(trend) { point in
                        if let raw = point.raw {
                            PointMark(x: .value("Date", point.date), y: .value("Weight", raw))
                                .foregroundStyle(.white.opacity(0.25))
                                .symbolSize(20)
                        }
                        LineMark(x: .value("Date", point.date), y: .value("Trend", point.trend))
                            .foregroundStyle(Theme.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    RuleMark(y: .value("Goal", plan.goalWeight))
                        .foregroundStyle(Theme.warn.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .bottom, alignment: .leading) {
                            Text("goal \(String(format: "%.0f", plan.goalWeight))")
                                .font(.caption2)
                                .foregroundStyle(Theme.warn)
                        }
                }
                .chartYScale(domain: yDomain(trend: trend))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel().foregroundStyle(Theme.textDim)
                        AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    }
                }
                .chartYAxis {
                    AxisMarks {
                        AxisValueLabel().foregroundStyle(Theme.textDim)
                        AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    }
                }
                .frame(height: 160)
            } else {
                Text("Log your weight a few days in a row and the trend line appears here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private func yDomain(trend: [TrendPoint]) -> ClosedRange<Double> {
        let values = trend.flatMap { [$0.raw, $0.trend].compactMap { $0 } } + [plan.goalWeight]
        let lo = (values.min() ?? 0) - 2
        let hi = (values.max() ?? 300) + 2
        return lo...hi
    }
}

// MARK: - Today rings

private struct TodayCard: View {
    let day: DayLog
    let targets: DailyTargets
    let plan: Plan

    var body: some View {
        Card(title: "Today") {
            HStack {
                Spacer()
                StatRing(value: Double(day.totalCalories) / Double(max(1, targets.calories)),
                         label: "Calories",
                         detail: caloriesDetail,
                         overIsBad: true)
                Spacer()
                StatRing(value: Double(day.totalProtein) / Double(max(1, targets.proteinGrams)),
                         label: "Protein",
                         detail: "\(day.totalProtein)/\(targets.proteinGrams)g")
                Spacer()
                StatRing(value: Double(day.waterOunces) / Double(max(1, targets.waterOunces)),
                         label: "Water",
                         detail: "\(day.waterOunces)/\(targets.waterOunces)oz")
                Spacer()
            }

            Divider().overlay(.white.opacity(0.08))

            workoutRow
            row(icon: "camera.fill", text: "Progress photo", done: !day.photos.isEmpty)

            if !plan.supplements.isEmpty {
                supplementsRow
            }
            if day.standardDrinks > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "wineglass").foregroundStyle(Theme.warn)
                    Text("\(day.standardDrinks.formatted()) standard drink\(day.standardDrinks == 1 ? "" : "s") (~\(day.alcoholCalories) cal counted)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.warn)
                    Spacer()
                }
            }
        }
    }

    private var caloriesDetail: String {
        let remaining = targets.calories - day.totalCalories
        return remaining >= 0 ? "\(remaining) left" : "\(-remaining) over"
    }

    private var workoutRow: some View {
        let scheduled = plan.scheduledWorkouts(on: day.date)
        let done = !day.workouts.isEmpty
        let text: String
        if !scheduled.isEmpty {
            text = done ? "Workout done — \(day.workoutMinutes) min"
                        : "Planned: \(scheduled.map(\.name).joined(separator: ", "))"
        } else {
            text = done ? "Bonus workout — \(day.workoutMinutes) min" : "Rest day"
        }
        return row(icon: "figure.run", text: text,
                   done: done || scheduled.isEmpty)
    }

    private var supplementsRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "pills.fill").foregroundStyle(Theme.textDim)
            ForEach(plan.supplements) { s in
                let taken = day.takenSupplements.contains(s.name)
                Text(s.name)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(taken ? Theme.accent.opacity(0.25) : Theme.surface2))
                    .foregroundStyle(taken ? Theme.accent : Theme.textDim)
            }
            Spacer()
        }
    }

    private func row(icon: String, text: String, done: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : icon)
                .foregroundStyle(done ? Theme.accent : Theme.textDim)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(done ? .white : Theme.textDim)
            Spacer()
        }
    }
}

// MARK: - Streak

private struct StreakCard: View {
    let stats: StreakStats

    var body: some View {
        Card(title: "Streak") {
            HStack(spacing: 10) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(stats.current > 0 ? AnyShapeStyle(Theme.flame) : AnyShapeStyle(Theme.textDim))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(stats.current)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("day\(stats.current == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.textDim)
                }
            }
            Text("\(Int(stats.consistency * 100))% consistency")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
        }
    }
}

// MARK: - Projection

private struct ProjectionCard: View {
    let plan: Plan
    let dayNumber: Int

    var body: some View {
        Card(title: "Goal") {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f lb", plan.goalWeight))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                if let projected = plan.projectedGoalDate {
                    Text("est. \(projected.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                } else {
                    Text("reached 🎉")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
            Text(String(format: "%.1f lb/week", plan.paceLbsPerWeek))
                .font(.caption)
                .foregroundStyle(Theme.textDim)
        }
    }
}

// MARK: - Weekly insight

private struct InsightCard: View {
    let insight: WeeklyInsight

    var body: some View {
        Card(title: "This Week") {
            HStack(spacing: 16) {
                stat("\(insight.daysMet)/\(insight.daysApplicable)", "days on target")
                if insight.avgCalories > 0 {
                    stat("\(insight.avgCalories)", "avg cal (budget \(insight.calorieBudget))")
                }
                if let delta = insight.trendDelta7d {
                    stat(String(format: "%@%.1f", delta > 0 ? "+" : "", delta), "trend lb, 7d")
                }
            }
            Text(insight.suggestion)
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(Theme.textDim)
        }
    }
}
