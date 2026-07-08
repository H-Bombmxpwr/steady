import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

// MARK: - Snapshot of today's numbers (read from the shared App Group store)

struct TodaySnapshot {
    var caloriesEaten = 0
    var calorieBudget = 2000
    var protein = 0
    var proteinTarget = 120
    var waterOz = 0
    var waterGoal = 96
    var waterStep = 8
    var streak = 0
    var trendWeight: Double = 0
    var goalWeight: Double = 0
    var goalDate: Date?
    var hasPlan = false

    var caloriesLeft: Int { calorieBudget - caloriesEaten }

    static func load() -> TodaySnapshot {
        var snapshot = TodaySnapshot()
        let context = ModelContext(PersistenceController.shared.container)
        guard let plan = try? context.fetch(FetchDescriptor<Plan>()).first,
              let profile = try? context.fetch(FetchDescriptor<UserProfile>()).first else {
            return snapshot
        }
        let targets = CalorieEngine.targets(profile: profile, plan: plan)
        let today = Calendar.current.startOfDay(for: Date())
        let day = plan.days.first { Calendar.current.isDate($0.date, inSameDayAs: today) }

        snapshot.hasPlan = true
        snapshot.calorieBudget = targets.calories
        snapshot.proteinTarget = targets.proteinGrams
        snapshot.waterGoal = targets.waterOunces
        snapshot.waterStep = max(1, plan.waterStepOunces)
        snapshot.caloriesEaten = day?.totalCalories ?? 0
        snapshot.protein = day?.totalProtein ?? 0
        snapshot.waterOz = day?.waterOunces ?? 0
        snapshot.streak = CalorieEngine.streakStats(plan: plan, targets: targets).current
        snapshot.trendWeight = CalorieEngine.trendWeight(plan: plan)
        snapshot.goalWeight = plan.goalWeight
        snapshot.goalDate = plan.projectedGoalDate
        return snapshot
    }
}

// MARK: - Interactive intent: log one water step from the widget

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Adds one bottle/step of water to today's log.")

    func perform() async throws -> some IntentResult {
        let context = ModelContext(PersistenceController.shared.container)
        if let plan = try? context.fetch(FetchDescriptor<Plan>()).first {
            let day = ensureDay(plan: plan, date: Date())
            day.waterOunces += max(1, plan.waterStepOunces)
            try? context.save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Timeline

struct TodayTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTimelineEntry {
        TodayTimelineEntry(date: Date(), snapshot: TodaySnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTimelineEntry) -> Void) {
        completion(TodayTimelineEntry(date: Date(), snapshot: TodaySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTimelineEntry>) -> Void) {
        let entry = TodayTimelineEntry(date: Date(), snapshot: TodaySnapshot.load())
        let refresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Shared bits

private let accent = Color(red: 0.20, green: 0.83, blue: 0.60)     // emerald
private let accent2 = Color(red: 0.13, green: 0.83, blue: 0.93)    // cyan
private let widgetBG = Color(red: 0.055, green: 0.067, blue: 0.086)
private let gradient = LinearGradient(colors: [accent, accent2],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
private let good = Color(red: 0.29, green: 0.87, blue: 0.50)
private let bad = Color(red: 0.98, green: 0.44, blue: 0.52)

private struct StreakBadge: View {
    let streak: Int
    var large = false

    var body: some View {
        HStack(spacing: large ? 6 : 4) {
            Image(systemName: "flame.fill")
                .font(large ? .title : .subheadline)
                .foregroundStyle(streak > 0
                                 ? AnyShapeStyle(LinearGradient(colors: [.orange, .yellow],
                                                                startPoint: .bottom, endPoint: .top))
                                 : AnyShapeStyle(.secondary))
            Text("\(streak)")
                .font(large ? .system(size: 34, weight: .bold, design: .rounded)
                            : .system(.headline, design: .rounded).bold())
            if large {
                Text("day streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// consumed/total in red or green — no bars.
private struct RatioRow: View {
    let icon: String
    let label: String
    let consumed: Int
    let total: Int
    var overIsBad = false

    private var ok: Bool { overIsBad ? (consumed <= total && consumed > 0) : consumed >= total }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(consumed)/\(total)")
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundStyle(ok ? good : bad)
        }
    }
}

// MARK: - Widget views

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayTimelineEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        case .systemMedium: mediumView
        case .systemLarge: largeView
        default: smallView
        }
    }

    private var s: TodaySnapshot { entry.snapshot }

    // Lock screen — circular streak flame
    private var circularView: some View {
        Gauge(value: min(1, Double(s.waterOz) / Double(max(1, s.waterGoal)))) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(s.streak)")
        }
        .gaugeStyle(.accessoryCircular)
    }

    // Lock screen — streak + calories + water
    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("\(s.streak) day streak")
            }
            .font(.headline)
            Text(s.caloriesLeft >= 0 ? "\(s.caloriesLeft) cal left" : "\(-s.caloriesLeft) cal over")
            Text("\(s.waterOz)/\(s.waterGoal) oz water")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var inlineView: some View {
        Text(s.caloriesLeft >= 0 ? "🔥\(s.streak)  ·  \(s.caloriesLeft) cal left"
                                 : "🔥\(s.streak)  ·  \(-s.caloriesLeft) cal over")
    }

    // Home screen small — streak headline + calorie ring
    private var smallView: some View {
        VStack(spacing: 8) {
            StreakBadge(streak: s.streak)
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, Double(s.caloriesEaten) / Double(max(1, s.calorieBudget))))
                    .stroke(s.caloriesLeft < 0 ? AnyShapeStyle(bad) : AnyShapeStyle(gradient),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(abs(s.caloriesLeft))")
                        .font(.system(.title3, design: .rounded).bold())
                    Text(s.caloriesLeft >= 0 ? "left" : "over")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .containerBackground(widgetBG, for: .widget)
    }

    // Home screen medium — streak + ratios + action buttons
    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                StreakBadge(streak: s.streak)
                RatioRow(icon: "fork.knife", label: "Cal",
                         consumed: s.caloriesEaten, total: s.calorieBudget, overIsBad: true)
                RatioRow(icon: "bolt.fill", label: "Protein",
                         consumed: s.protein, total: s.proteinTarget)
                RatioRow(icon: "drop.fill", label: "Water",
                         consumed: s.waterOz, total: s.waterGoal)
            }
            VStack(spacing: 8) {
                Button(intent: LogWaterIntent()) {
                    actionLabel("drop.fill", "+\(s.waterStep)oz", accent2)
                }
                .buttonStyle(.plain)
                Link(destination: URL(string: "seventyfive://log-food")!) {
                    actionLabel("fork.knife", "Food", accent)
                }
                Link(destination: URL(string: "seventyfive://log-workout")!) {
                    actionLabel("dumbbell.fill", "Workout", .orange)
                }
            }
            .frame(width: 88)
        }
        .containerBackground(widgetBG, for: .widget)
    }

    // Home screen large — everything + weight
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StreakBadge(streak: s.streak, large: true)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.1f lb", s.trendWeight))
                        .font(.system(.title3, design: .rounded).bold())
                    if let d = s.goalDate {
                        Text("goal \(String(format: "%.0f", s.goalWeight)) · est. \(d.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("trend weight")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 10) {
                RatioRow(icon: "fork.knife", label: "Calories",
                         consumed: s.caloriesEaten, total: s.calorieBudget, overIsBad: true)
                RatioRow(icon: "bolt.fill", label: "Protein",
                         consumed: s.protein, total: s.proteinTarget)
                RatioRow(icon: "drop.fill", label: "Water",
                         consumed: s.waterOz, total: s.waterGoal)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06)))

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(intent: LogWaterIntent()) {
                    actionLabel("drop.fill", "+\(s.waterStep) oz", accent2, wide: true)
                }
                .buttonStyle(.plain)
                Link(destination: URL(string: "seventyfive://log-food")!) {
                    actionLabel("fork.knife", "Log food", accent, wide: true)
                }
                Link(destination: URL(string: "seventyfive://log-workout")!) {
                    actionLabel("dumbbell.fill", "Workout", .orange, wide: true)
                }
            }
        }
        .containerBackground(widgetBG, for: .widget)
    }

    private func actionLabel(_ icon: String, _ text: String, _ color: Color, wide: Bool = false) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(wide ? .body : .subheadline)
            Text(text)
                .font(.system(.caption2, design: .rounded).bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.1)))
        .foregroundStyle(color)
    }
}

// MARK: - Widget declarations

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Goals")
        .description("Streak, calories, protein, and water — with one-tap logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct FitnessWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}
