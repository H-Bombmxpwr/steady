import SwiftUI
import SwiftData
import Charts

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    var profile: UserProfile

    @State private var tab = 0

    // Widget deep links (seventyfive://log-food, log-workout, today)
    @State private var showFoodLog = false
    @State private var showWorkoutLog = false
    @State private var showToday = false

    private static let tabs: [(label: String, icon: String)] = [
        ("Dashboard", "house.fill"),
        ("Stats", "chart.xyaxis.line"),
        ("Calendar", "calendar"),
        ("Photos", "photo.on.rectangle"),
        ("Workouts", "figure.strengthtraining.traditional")
    ]

    @ViewBuilder
    private func screen(_ index: Int) -> some View {
        switch index {
        // The mode picks the dashboard; every other tab is shared. An athlete
        // and someone in a deficit want the same stats, calendar, and photos —
        // they just want a different thing to open on.
        case 0:
            if profile.mode == .athlete {
                AthleteDashboardView(plan: plan, profile: profile)
            } else {
                DashboardView(plan: plan, profile: profile)
            }
        case 1: StatsView(plan: plan, profile: profile)
        case 2: CalendarScreen(plan: plan, profile: profile)
        case 3: PhotosGalleryView(plan: plan)
        default: WorkoutsView(plan: plan)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(0..<5) { i in
                screen(i)
                    .tabItem { Label(Self.tabs[i].label, systemImage: Self.tabs[i].icon) }
                    .tag(i)
            }
        }
        .onOpenURL { url in
            switch url.host {
            case "log-food": showFoodLog = true
            case "log-workout": showWorkoutLog = true
            case "today": showToday = true
            default: break
            }
        }
        .sheet(isPresented: $showToday) {
            NavigationStack {
                DayDetailView(plan: plan, profile: profile,
                              date: Calendar.current.startOfDay(for: Date()))
            }
            .themedRoot()
        }
        .sheet(isPresented: $showFoodLog) {
            NavigationStack {
                FoodSearchView(day: ensureDay(plan: plan, date: Date()))
            }
            .themedRoot()
        }
        .sheet(isPresented: $showWorkoutLog) {
            NavigationStack {
                WorkoutFormView(day: ensureDay(plan: plan, date: Date()), plan: plan)
            }
            .themedRoot()
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    var profile: UserProfile
    @State private var today = Calendar.current.startOfDay(for: Date())
    @State private var showSettings = false

    // One-shot celebration when a new milestone lands
    @State private var showConfetti = false
    @AppStorage("milestones.celebrated") private var celebratedRaw = ""

    // Fasting timer card (opt-in, Settings → Fasting)
    @AppStorage(Fasting.enabledKey) private var fastingEnabled = false

    private var dayNumber: Int { max(0, plan.startDate.days(to: today)) + 1 }
    private var todayLog: DayLog { ensureDay(plan: plan, date: today) }
    private var targets: DailyTargets { CalorieEngine.targets(profile: profile, plan: plan) }
    /// Today's budget with training-day fueling folded in (the base budget on
    /// rest days). Only today's card uses this — history cards stay on base.
    private var todayTargets: DailyTargets {
        CalorieEngine.targets(profile: profile, plan: plan, on: today)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Brand header — the Steady trendline mark and a greeting
                    // that actually knows what time it is and how it's going.
                    HStack(spacing: 12) {
                        Image(systemName: "chart.line.downtrend.xyaxis")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.gradient)
                            )
                            .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(greeting)
                                .font(.system(.title2, design: .rounded).bold())
                            Text("Day \(dayNumber) · \(today.formatted(.dateTime.weekday(.wide).month().day()))")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                    }

                    Text(encouragement)
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                        .padding(.bottom, 2)

                    WeightCard(plan: plan)

                    TodayCard(day: todayLog, targets: todayTargets, plan: plan)

                    if !plan.sessions(on: today).isEmpty {
                        FuelCard(plan: plan)
                    }

                    if profile.cycleTracking {
                        CycleCard(plan: plan)
                    }

                    if fastingEnabled {
                        FastingCard(plan: plan)
                    }

                    HStack(spacing: 14) {
                        StreakCard(stats: CalorieEngine.streakStats(plan: plan, targets: targets))
                        ProjectionCard(plan: plan, dayNumber: dayNumber)
                    }

                    MilestonesCard(milestones: Milestone.all(plan: plan, targets: targets))

                    InsightCard(insight: CalorieEngine.weeklyInsight(plan: plan, targets: targets))

                    NavigationLink(value: today) {
                        Label("Open Today", systemImage: "square.and.pencil")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Capsule().fill(Theme.gradient))
                            .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
                    }
                }
                .padding()
            }
            .brandBackground()
            .navigationDestination(for: Date.self) { d in
                DayDetailView(plan: plan, profile: profile, date: d)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: today) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.pencil")
                            Text("Today")
                        }
                        .font(.headline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(plan: plan, profile: profile)   // applies .themedRoot() itself
            }
            .overlay {
                if showConfetti { ConfettiView() }
            }
            .onAppear { celebrateNewMilestones() }
            // Watch/Garmin sessions land in Health on their own schedule —
            // pull them in whenever the dashboard comes up so today's
            // workout credit (and the streak) is never waiting on Stats.
            .task {
                if await HealthKitService.shared.importExternalWorkouts(into: plan) > 0 {
                    try? context.save()
                }
            }
        }
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Up late"
        }
    }

    /// One human line under the header, built from the actual numbers and
    /// rotated daily so it doesn't wear out its welcome.
    private var encouragement: String {
        let stats = CalorieEngine.streakStats(plan: plan, targets: targets)
        let trendDelta = CalorieEngine.trendWeight(plan: plan) - plan.startingWeight

        var lines: [String] = []
        if trendDelta <= -1 {
            lines.append("Down \(abs(trendDelta).formatted(.number.precision(.fractionLength(1)))) lb from day one. That didn't happen by accident.")
            lines.append("The trend is \(abs(trendDelta).formatted(.number.precision(.fractionLength(1)))) lb lighter than when you started. Keep feeding it.")
        }
        if stats.current >= 3 {
            lines.append("\(stats.current) days straight of showing up. Streaks are just proof you're someone who does this.")
        }
        if stats.consistency >= 0.7, stats.daysTracked >= 14 {
            lines.append("You've shown up \(Int(stats.consistency * 100))% of days. That's the whole secret, honestly.")
        }
        lines.append("Log the day you actually had, not the one you planned. The math works either way.")
        lines.append("Nobody's watching. Show up anyway.")
        lines.append("A boring day on plan beats a heroic Monday.")

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return lines[dayOfYear % lines.count]
    }

    /// Fire confetti once per newly earned milestone (ids remembered in
    /// UserDefaults so a badge only ever celebrates once).
    private func celebrateNewMilestones() {
        let earned = Set(Milestone.all(plan: plan, targets: targets)
            .filter(\.earned).map(\.id))
        var celebrated = Set(celebratedRaw.split(separator: ",").map(String.init))
        let fresh = earned.subtracting(celebrated)
        // First launch after the feature ships: mark history as celebrated
        // quietly instead of dumping confetti for months-old wins.
        guard !celebrated.isEmpty || celebratedRaw != "" || fresh.count <= 2 else {
            celebratedRaw = earned.joined(separator: ",")
            return
        }
        guard !fresh.isEmpty else { return }
        celebrated.formUnion(earned)
        celebratedRaw = celebrated.joined(separator: ",")
        showConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { showConfetti = false }
    }
}

// MARK: - Weight + trend chart

private struct WeightCard: View {
    let plan: Plan

    /// Goal line on the weight charts — hiding it re-fits the y-axis to
    /// just your data, which matters when the goal is still far away.
    @AppStorage("chart.showGoal") private var showGoal = true

    var body: some View {
        Card(title: "Weight", icon: "scalemass.fill", tint: Theme.weightTint) {
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
                        // Each day's actual weigh-in: a visible dot, thin
                        // line threading them so the raw path reads too.
                        if let raw = point.raw {
                            LineMark(x: .value("Date", point.date), y: .value("Weight", raw),
                                     series: .value("Series", "daily"))
                                .foregroundStyle(Theme.weightTint.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", point.date), y: .value("Weight", raw))
                                .foregroundStyle(Theme.weightTint)
                                .symbolSize(28)
                        }
                        LineMark(x: .value("Date", point.date), y: .value("Trend", point.trend),
                                 series: .value("Series", "trend"))
                            .foregroundStyle(Theme.gradient)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    if showGoal {
                        RuleMark(y: .value("Goal", plan.goalWeight))
                            .foregroundStyle(Theme.warn.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            // Above the line so it never collides with the
                            // x-axis labels below the plot.
                            .annotation(position: .top, alignment: .leading) {
                                Text("goal \(plan.goalWeight.formatted(.number.precision(.fractionLength(0...1))))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.warn)
                            }
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

                HStack {
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { showGoal.toggle() }
                    } label: {
                        Label(showGoal ? "Hide goal line" : "Show goal line",
                              systemImage: "target")
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Log your weight a few days in a row and the trend line appears here.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private func yDomain(trend: [TrendPoint]) -> ClosedRange<Double> {
        var values = trend.flatMap { [$0.raw, $0.trend].compactMap { $0 } }
        // The goal only stretches the axis while its line is shown.
        if showGoal { values.append(plan.goalWeight) }
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
        Card(title: "Today", icon: "sun.max.fill", tint: Theme.foodTint) {
            HStack {
                Spacer()
                StatRing(value: Double(day.totalCalories) / Double(max(1, targets.calories)),
                         label: "Calories",
                         detail: caloriesDetail,
                         overIsBad: true,
                         tint: Theme.foodTint)
                Spacer()
                StatRing(value: Double(day.totalProtein) / Double(max(1, targets.proteinGrams)),
                         label: "Protein",
                         detail: "\(day.totalProtein)/\(targets.proteinGrams)g",
                         tint: Theme.workoutTint)
                Spacer()
                StatRing(value: Double(day.waterOunces) / Double(max(1, targets.waterOunces)),
                         label: "Water",
                         detail: "\(day.waterOunces)/\(targets.waterOunces)oz",
                         tint: Theme.waterTint)
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
        let scheduled = plan.sessions(on: day.date)
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
        Card(title: "Streak", icon: "flame.fill", tint: Color(hex: 0xF97316)) {
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
        Card(title: "Goal", icon: "target", tint: Theme.accent) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(plan.goalWeight.formatted(.number.precision(.fractionLength(0...1)))) lb")
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
        Card(title: "This Week", icon: "calendar", tint: Theme.sleepTint) {
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
