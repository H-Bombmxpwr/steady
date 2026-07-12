import SwiftUI
import SwiftData
import Charts

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    var profile: UserProfile

    /// Floating glass tab bar with swipe-between-tabs; off = classic iOS bar.
    @AppStorage("ui.glassBar") private var glassBar = true
    @State private var tab = 0
    /// While the pill is being dragged, the bar owns `tab` — the paged
    /// TabView's async stale write-backs are ignored (they bounced the
    /// pill off tabs 1 and 3).
    @State private var barDragging = false

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
        case 0: DashboardView(plan: plan, profile: profile)
        case 1: StatsView(plan: plan, profile: profile)
        case 2: CalendarScreen(plan: plan, profile: profile)
        case 3: PhotosGalleryView(plan: plan)
        default: WorkoutsView(plan: plan)
        }
    }

    var body: some View {
        Group {
            if glassBar {
                TabView(selection: Binding(
                    get: { tab },
                    set: { if !barDragging { tab = $0 } }
                )) {
                    ForEach(0..<5) { i in
                        screen(i).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .background(Theme.background.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    GlassTabBar(tabs: Self.tabs, selection: $tab, dragging: $barDragging)
                }
            } else {
                TabView(selection: $tab) {
                    ForEach(0..<5) { i in
                        screen(i)
                            .tabItem { Label(Self.tabs[i].label, systemImage: Self.tabs[i].icon) }
                            .tag(i)
                    }
                }
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

// MARK: - Floating glass tab bar

/// Translucent floating capsule bar (the "liquid glass" look). One gradient
/// pill marks the active tab; tap a tab, swipe the pages, or grab the pill
/// and slide it across the bar — pages follow live.
private struct GlassTabBar: View {
    let tabs: [(label: String, icon: String)]
    @Binding var selection: Int
    @Binding var dragging: Bool

    /// Fractional pill position while a finger is sliding along the bar.
    @State private var dragIndex: CGFloat?

    private static let spring = Animation.spring(response: 0.34, dampingFraction: 0.82)
    private let inset: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            // Clamp: zero-width layout passes otherwise produce negative
            // frames ("Invalid frame dimension" console spam).
            let tabWidth = max(1, (geo.size.width - inset * 2) / CGFloat(tabs.count))
            let pillHeight = max(1, geo.size.height - inset * 2)
            let position = dragIndex ?? CGFloat(selection)
            // While dragging, the highlight follows the pill, not the page.
            let highlighted = dragIndex.map { Int($0.rounded()) } ?? selection

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.gradient)
                    .frame(width: tabWidth, height: pillHeight)
                    .offset(x: inset + position * tabWidth)
                    .scaleEffect(dragIndex == nil ? 1 : 1.07)
                    .shadow(color: Theme.accent.opacity(dragIndex == nil ? 0.35 : 0.5),
                            radius: dragIndex == nil ? 8 : 12, y: 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.8),
                               value: dragIndex == nil)

                HStack(spacing: 0) {
                    ForEach(tabs.indices, id: \.self) { i in
                        Button {
                            withAnimation(Self.spring) { selection = i }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tabs[i].icon)
                                    .font(.system(size: 17, weight: .semibold))
                                Text(tabs[i].label)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(highlighted == i ? .white : Color.secondary)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, inset)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        dragging = true
                        let f = (value.location.x - inset) / tabWidth - 0.5
                        let clamped = min(max(f, 0), CGFloat(tabs.count - 1))
                        // The pill tracks the finger directly — no implicit
                        // animation to lag behind it.
                        var follow = Transaction()
                        follow.disablesAnimations = true
                        withTransaction(follow) { dragIndex = clamped }

                        // The page follows the pill live. Safe now: while
                        // `dragging` is true the TabView's stale async
                        // write-backs are ignored upstream.
                        let nearest = Int(clamped.rounded())
                        if nearest != selection {
                            withTransaction(follow) { selection = nearest }
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { value in
                        let f = (value.location.x - inset) / tabWidth - 0.5
                        let nearest = Int(min(max(f, 0), CGFloat(tabs.count - 1)).rounded())
                        selection = nearest
                        // Pill just seats into the slot it's already on.
                        withAnimation(Self.spring) { dragIndex = nil }
                        // Keep ignoring pager write-backs until any in-flight
                        // transition finishes, so the landing tab sticks.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            dragging = false
                        }
                    }
            )
        }
        .frame(height: 56)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Theme.hairline))
                .shadow(color: .black.opacity(0.25), radius: 14, y: 5)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 2)
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

    private var dayNumber: Int { max(0, plan.startDate.days(to: today)) + 1 }
    private var todayLog: DayLog { ensureDay(plan: plan, date: today) }
    private var targets: DailyTargets { CalorieEngine.targets(profile: profile, plan: plan) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Brand header — the "75" monogram is the app's wordmark.
                    HStack(spacing: 12) {
                        Text("75")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Theme.gradient)
                            )
                            .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Day \(dayNumber)")
                                .font(.system(.title2, design: .rounded).bold())
                            Text(today.formatted(.dateTime.weekday(.wide).month().day()))
                                .font(.subheadline)
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)

                    WeightCard(plan: plan)

                    TodayCard(day: todayLog, targets: targets, plan: plan)

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
        }
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
