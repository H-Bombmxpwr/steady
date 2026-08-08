import SwiftUI
import SwiftData
import Charts

/// The athlete dashboard. Where the weight-loss dashboard opens on a weight
/// trend and a budget, this one opens on the work: today's session, then the
/// fuel built around it. Weight is still here, further down, framed as a data
/// point rather than the scoreboard.
struct AthleteDashboardView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appLock: AppLockManager
    @StateObject private var weather = WeatherService.shared

    var plan: Plan
    var profile: UserProfile

    @State private var today = Calendar.current.startOfDay(for: Date())
    @State private var showSettings = false
    @State private var syncMessage: String?
    @State private var isSyncing = false

    @AppStorage(Fasting.enabledKey) private var fastingEnabled = false

    private var todayLog: DayLog { ensureDay(plan: plan, date: today) }
    private var sessions: [TrainingSession] { plan.sessions(on: today) }

    private var cyclePhase: CyclePhase? {
        guard profile.cycleTracking else { return nil }
        return CycleEngine.status(entries: plan.cycles)?.phase
    }

    private var athleteTargets: AthleteTargets {
        CalorieEngine.athleteTargets(profile: profile, plan: plan, on: today,
                                     weather: weather.effective, cyclePhase: cyclePhase)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    TodaysSessionCard(plan: plan,
                                      sessions: sessions,
                                      weather: weather.effective,
                                      cyclePhase: cyclePhase,
                                      isSyncing: isSyncing,
                                      syncMessage: syncMessage,
                                      onSync: sync)

                    FuelTodayCard(targets: athleteTargets, day: todayLog)

                    HydrationCard(plan: plan,
                                  day: todayLog,
                                  sessions: sessions,
                                  weather: weather.effective,
                                  cyclePhase: cyclePhase)

                    if profile.cycleTracking {
                        CycleCard(plan: plan)
                    }

                    if fastingEnabled {
                        FastingCard(plan: plan)
                    }

                    WeekLoadCard(plan: plan, profile: profile)

                    AthleteWeightCard(plan: plan)

                    if profile.generalHealth {
                        GeneralHealthCard(plan: plan, day: todayLog)
                    }

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
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(plan: plan, profile: profile)
            }
            .task {
                await weather.refreshIfNeeded()
                if await HealthKitService.shared.importExternalWorkouts(into: plan) > 0 {
                    try? context.save()
                }
                await syncIfStale()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "figure.run")
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.gradient))
                    .shadow(color: Theme.accent.opacity(0.4), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(greeting)
                        .font(.system(.title2, design: .rounded).bold())
                    Text(today.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                if let context = weather.effective {
                    WeatherChip(context: context)
                }
            }
            Text(AthleteEngine.summary(athleteTargets))
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
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

    /// Refresh the plan at most once an hour — a coach editing the week is not
    /// a per-second event, and the feed is somebody else's server.
    private func syncIfStale() async {
        guard plan.trainingPeaksConnected else { return }
        if let last = plan.trainingPeaksLastSync,
           Date().timeIntervalSince(last) < 3600 { return }
        await sync()
    }

    private func sync() async {
        guard plan.trainingPeaksConnected, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await TrainingPeaksSync.sync(plan: plan)
            try? context.save()
            syncMessage = result.isEmpty ? nil : result.summary
        } catch {
            syncMessage = error.localizedDescription
        }
    }
}

// MARK: - Weather chip

struct WeatherChip: View {
    let context: WeatherContext

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: context.severity.icon)
            Text("\(Int(context.tempF.rounded()))°")
                .font(.subheadline.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(tint.opacity(0.15)))
    }

    private var tint: Color {
        switch context.severity {
        case .extreme: return Theme.danger
        case .hot: return Theme.warn
        case .cold: return Theme.waterTint
        default: return Theme.textDim
        }
    }
}

// MARK: - Today's session

/// The centrepiece. Whatever the training plan says today is, plus the fuel
/// for it one tap away.
struct TodaysSessionCard: View {
    let plan: Plan
    let sessions: [TrainingSession]
    let weather: WeatherContext?
    let cyclePhase: CyclePhase?
    let isSyncing: Bool
    let syncMessage: String?
    let onSync: () async -> Void

    @State private var detail: FuelingPlan?
    @State private var showAdd = false

    private func fuel(for session: TrainingSession) -> FuelingPlan {
        FuelingEngine.plan(for: session,
                           bodyweightLbs: plan.currentWeight,
                           sweat: plan.sweatProfile(matching: session.category,
                                                    intensity: session.intensity),
                           weather: plan.weatherAwareFueling ? weather : nil,
                           cyclePhase: cyclePhase)
    }

    var body: some View {
        Card(title: "Today's Training", icon: "figure.run", tint: Theme.workoutTint) {
            if sessions.isEmpty {
                restDay
            } else {
                ForEach(sessions) { session in
                    sessionRow(session)
                    if session.id != sessions.last?.id {
                        Divider().overlay(.white.opacity(0.08))
                    }
                }
            }

            if let advisory = weather?.advisory {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: weather?.severity.icon ?? "thermometer")
                        .foregroundStyle(Theme.warn)
                    Text(advisory)
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(Theme.warn)
                .padding(.top, 2)
            }

            footerRow
        }
        .sheet(item: $detail) { fp in
            NavigationStack {
                Form { FuelPlanBreakdown(plan: fp) }
                    .themedForm()
                    .navigationTitle("Fueling")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .themedRoot()
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showAdd) {
            PlannedWorkoutFormView(plan: plan, date: Calendar.current.startOfDay(for: Date()))
        }
    }

    private var restDay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rest day")
                .font(.system(.title3, design: .rounded).bold())
            Text(plan.trainingPeaksConnected
                 ? "Nothing on the plan. Recovery is training too — eat enough protein and sleep."
                 : "Nothing planned. Add a session, or connect TrainingPeaks in Settings to pull your week in automatically.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
        }
    }

    private func sessionRow(_ session: TrainingSession) -> some View {
        let fp = fuel(for: session)
        return Button { detail = fp } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: session.category.icon)
                        .font(.caption)
                        .foregroundStyle(Theme.workoutTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(session.subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if fp.needsInWorkoutFuel {
                            Text("\(fp.carbsPerHour) g/hr")
                                .font(.system(.body, design: .rounded).weight(.bold))
                            Text("carbs during")
                                .font(.caption2).foregroundStyle(Theme.textDim)
                        } else {
                            Text("\(fp.recoveryProtein) g")
                                .font(.system(.body, design: .rounded).weight(.bold))
                            Text("protein after")
                                .font(.caption2).foregroundStyle(Theme.textDim)
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }

                HStack(spacing: 10) {
                    pill("drop.fill", "\(fp.fluidOzPerHour) oz/hr", Theme.waterTint)
                    if fp.sodiumMgPerHour > 0 {
                        pill("bolt.horizontal.fill", "\(fp.sodiumMgPerHour) mg Na/hr", Theme.supplementTint)
                    }
                    pill("flame.fill", "~\(fp.burnCalories) cal", Theme.foodTint)
                }

                if session.origin == .trainingPeaks {
                    Label("From TrainingPeaks", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pill(_ icon: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text).font(.caption2.weight(.medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.14)))
    }

    private var footerRow: some View {
        HStack(spacing: 12) {
            Button { showAdd = true } label: {
                Label("Add session", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)

            if plan.trainingPeaksConnected {
                Button { Task { await onSync() } } label: {
                    HStack(spacing: 4) {
                        if isSyncing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(isSyncing ? "Syncing…" : "Sync")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .disabled(isSyncing)
            }
            Spacer()
            if let syncMessage {
                Text(syncMessage)
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Fuel today

/// The day's macros, periodized against the training load rather than a fixed
/// split. Carbs lead because they're the number that actually moves.
struct FuelTodayCard: View {
    let targets: AthleteTargets
    let day: DayLog

    private var facts: NutritionFacts { day.totalFacts }

    var body: some View {
        Card(title: "Fuel Today", icon: "fork.knife", tint: Theme.foodTint) {
            HStack(alignment: .firstTextBaseline) {
                Text(targets.load.label)
                    .font(.system(.title3, design: .rounded).bold())
                Spacer()
                Text("\(day.totalCalories) / \(targets.calories) cal")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(day.totalCalories > targets.calories
                                     ? Theme.warn : Theme.textDim)
            }

            macroBar("Carbs", Int(facts.carbsGrams.rounded()), targets.carbGrams, Theme.foodTint)
            macroBar("Protein", day.totalProtein, targets.proteinGrams, Theme.workoutTint)
            macroBar("Fat", Int(facts.fatGrams.rounded()), targets.fatGrams, Theme.warn)

            Text(targets.load.detail)
                .font(.caption)
                .foregroundStyle(Theme.textDim)

            if targets.trainingBurn > 0 {
                Text("Includes ~\(targets.trainingBurn) cal for today's training — that's fuel, not a bonus.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private func macroBar(_ label: String, _ eaten: Int, _ target: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(Theme.textDim)
                Spacer()
                Text("\(eaten) / \(target) g")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textDim)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule()
                        .fill(LinearGradient(colors: [tint, tint.opacity(0.6)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width
                               * min(1, Double(eaten) / Double(max(1, target))))
                }
            }
            .frame(height: 7)
        }
    }
}

// MARK: - Hydration

/// Hydration in athlete mode is a sweat-rate problem, not a "drink 8 glasses"
/// problem. This card says where the number came from and how to sharpen it.
struct HydrationCard: View {
    let plan: Plan
    let day: DayLog
    let sessions: [TrainingSession]
    let weather: WeatherContext?
    let cyclePhase: CyclePhase?

    private var profile: SweatProfile? { plan.sweatProfile() }

    private var sessionFluid: Int {
        sessions.reduce(0) {
            $0 + FuelingEngine.plan(for: $1,
                                    bodyweightLbs: plan.currentWeight,
                                    sweat: plan.sweatProfile(matching: $1.category,
                                                             intensity: $1.intensity),
                                    weather: plan.weatherAwareFueling ? weather : nil,
                                    cyclePhase: cyclePhase).totalFluidOz
        }
    }

    private var target: Int { plan.waterGoalOunces + sessionFluid }

    var body: some View {
        Card(title: "Hydration", icon: "drop.fill", tint: Theme.waterTint) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(day.waterOunces)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("of \(target) oz").foregroundStyle(Theme.textDim)
                Spacer()
                if sessionFluid > 0 {
                    Text("+\(sessionFluid) oz for training")
                        .font(.caption)
                        .foregroundStyle(Theme.waterTint)
                }
            }

            GradientBar(value: Double(day.waterOunces) / Double(max(1, target)))

            NavigationLink {
                SweatTestView(plan: plan)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: profile == nil ? "exclamationmark.circle" : "checkmark.seal.fill")
                        .foregroundStyle(profile == nil ? Theme.warn : Theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        if let profile {
                            Text("Your sweat rate: \(profile.ouncesPerHour, specifier: "%.0f") oz/hr")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("From \(profile.testCount) test\(profile.testCount == 1 ? "" : "s")"
                                 + (profile.baselineTempF.map { " at ~\(Int($0.rounded()))°F" } ?? ""))
                                .font(.caption2)
                                .foregroundStyle(Theme.textDim)
                        } else {
                            Text("Run a sweat test")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Sweat rates vary several-fold. Twenty minutes and a scale replaces the guess.")
                                .font(.caption2)
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Week load

/// The training week at a glance — a bar per day, so a block's shape is
/// visible and tomorrow is never a surprise.
struct WeekLoadCard: View {
    let plan: Plan
    let profile: UserProfile

    private var days: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        Card(title: "Week Ahead", icon: "calendar", tint: Theme.sleepTint) {
            let loads = days.map { (date: $0, sessions: plan.sessions(on: $0)) }
            let maxMinutes = max(60, loads.map { $0.sessions.reduce(0) { $0 + $1.minutes } }.max() ?? 60)

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(loads.enumerated()), id: \.offset) { _, entry in
                    let minutes = entry.sessions.reduce(0) { $0 + $1.minutes }
                    let load = AthleteEngine.load(for: entry.sessions)
                    VStack(spacing: 5) {
                        Text(minutes > 0 ? "\(minutes)" : "–")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textDim)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(minutes > 0
                                  ? AnyShapeStyle(Theme.gradient)
                                  : AnyShapeStyle(Theme.surface2))
                            .frame(height: max(6, 62 * Double(minutes) / Double(maxMinutes)))
                        Text(entry.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                    }
                    .accessibilityLabel("\(entry.date.formatted(.dateTime.weekday(.wide))): \(load.label), \(minutes) minutes")
                }
            }
            .frame(height: 96)

            NavigationLink {
                WeekFuelView(plan: plan)
            } label: {
                HStack {
                    Text("This week's fuel, day by day")
                        .font(.caption)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .foregroundStyle(Theme.textDim)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Weight, athlete framing

/// Weight still matters to an athlete — it's just not the score. Smaller, no
/// goal line, framed as a trend to watch for under-fuelling.
struct AthleteWeightCard: View {
    let plan: Plan

    var body: some View {
        Card(title: "Weight", icon: "scalemass.fill", tint: Theme.weightTint) {
            let trend = CalorieEngine.weightTrend(plan: plan)
            let headline = trend.last?.trend ?? plan.startingWeight

            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%.1f", headline))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("lb trend").foregroundStyle(Theme.textDim)
                Spacer()
                if let delta = sevenDayDelta(trend) {
                    Text(String(format: "%@%.1f lb / 7d", delta > 0 ? "+" : "", delta))
                        .font(.subheadline)
                        .foregroundStyle(abs(delta) > 2 ? Theme.warn : Theme.textDim)
                }
            }

            if trend.count >= 2 {
                Chart(trend) { point in
                    LineMark(x: .value("Date", point.date), y: .value("Trend", point.trend))
                        .foregroundStyle(Theme.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                // Frame the data, not zero. An athlete's weight barely moves,
                // and a 0–150 axis renders that as a flat line with no
                // information in it.
                .chartYScale(domain: yDomain(trend))
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisValueLabel().foregroundStyle(Theme.textDim)
                        AxisGridLine().foregroundStyle(.white.opacity(0.06))
                    }
                }
                .frame(height: 90)
            }

            if let delta = sevenDayDelta(trend), delta < -2 {
                Text("Dropping fast for a training block. Sustained loss during hard training usually means under-fuelling before it means progress.")
                    .font(.caption)
                    .foregroundStyle(Theme.warn)
            }
        }
    }

    /// A minimum 4 lb window, so day-to-day noise doesn't fill the chart and
    /// read as a crisis.
    private func yDomain(_ trend: [TrendPoint]) -> ClosedRange<Double> {
        let values = trend.map(\.trend)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 200
        let mid = (lo + hi) / 2
        let halfSpan = max(2.0, (hi - lo) / 2 + 0.5)
        return (mid - halfSpan)...(mid + halfSpan)
    }

    private func sevenDayDelta(_ trend: [TrendPoint]) -> Double? {
        guard let last = trend.last,
              let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: last.date),
              let earlier = trend.last(where: { $0.date <= weekAgo })
        else { return nil }
        return last.trend - earlier.trend
    }
}

// MARK: - General health add-on

/// The optional general-health layer: the nutrition-quality numbers that
/// neither a deficit nor a training plan will surface on their own.
struct GeneralHealthCard: View {
    let plan: Plan
    let day: DayLog

    var body: some View {
        Card(title: "General Health", icon: "heart.text.square.fill", tint: Theme.supplementTint) {
            let facts = day.totalFacts
            HStack(spacing: 14) {
                metric("Fiber", "\(Int(facts.fiberGrams.rounded()))g", target: "30g",
                       good: facts.fiberGrams >= 25)
                metric("Sodium", "\(Int(facts.sodiumMg.rounded()))mg", target: "2300mg",
                       good: facts.sodiumMg <= 2300)
                metric("Added sugar", "\(Int(facts.addedSugarGrams.rounded()))g", target: "<36g",
                       good: facts.addedSugarGrams <= 36)
            }
            if let labs = plan.latestLabs {
                Text("Last panel \(labs.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textDim)
            }
        }
    }

    private func metric(_ label: String, _ value: String, target: String, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundStyle(good ? Theme.accent : Theme.warn)
            Text(label).font(.caption2).foregroundStyle(Theme.textDim)
            Text(target).font(.caption2).foregroundStyle(Theme.textDim.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
