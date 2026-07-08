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

// MARK: - Widget views

private let accent = Color(red: 0.20, green: 0.83, blue: 0.60)     // emerald
private let accent2 = Color(red: 0.13, green: 0.83, blue: 0.93)    // cyan
private let gradient = LinearGradient(colors: [accent, accent2],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayTimelineEntry

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        case .accessoryInline: inlineView
        case .systemMedium: mediumView
        default: smallView
        }
    }

    private var s: TodaySnapshot { entry.snapshot }

    // Lock screen — circular water gauge
    private var circularView: some View {
        Gauge(value: min(1, Double(s.waterOz) / Double(max(1, s.waterGoal)))) {
            Image(systemName: "drop.fill")
        } currentValueLabel: {
            Text("\(s.waterOz)")
        }
        .gaugeStyle(.accessoryCircular)
    }

    // Lock screen — calories + streak
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

    // Home screen small — calorie ring + streak
    private var smallView: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, Double(s.caloriesEaten) / Double(max(1, s.calorieBudget))))
                    .stroke(s.caloriesLeft < 0 ? AnyShapeStyle(.red) : AnyShapeStyle(gradient),
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
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("\(s.streak)")
                    .font(.system(.footnote, design: .rounded).bold())
                Spacer()
                Image(systemName: "drop.fill")
                    .foregroundStyle(accent2)
                Text("\(s.waterOz)")
                    .font(.system(.footnote, design: .rounded).bold())
            }
        }
        .containerBackground(Color(red: 0.055, green: 0.067, blue: 0.086), for: .widget)
    }

    // Home screen medium — full summary + tap-to-log water
    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").foregroundStyle(.orange)
                    Text("\(s.streak) day streak")
                        .font(.system(.subheadline, design: .rounded).bold())
                }
                bar("Calories",
                    value: Double(s.caloriesEaten) / Double(max(1, s.calorieBudget)),
                    text: s.caloriesLeft >= 0 ? "\(s.caloriesLeft) left" : "\(-s.caloriesLeft) over",
                    bad: s.caloriesLeft < 0)
                bar("Protein",
                    value: Double(s.protein) / Double(max(1, s.proteinTarget)),
                    text: "\(s.protein)/\(s.proteinTarget) g", bad: false)
                bar("Water",
                    value: Double(s.waterOz) / Double(max(1, s.waterGoal)),
                    text: "\(s.waterOz)/\(s.waterGoal) oz", bad: false)
            }
            Button(intent: LogWaterIntent()) {
                VStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.title2)
                    Text("+\(s.waterStep) oz")
                        .font(.system(.caption, design: .rounded).bold())
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.1)))
                .foregroundStyle(accent2)
            }
            .buttonStyle(.plain)
        }
        .containerBackground(Color(red: 0.055, green: 0.067, blue: 0.086), for: .widget)
    }

    private func bar(_ label: String, value: Double, text: String, bad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(text).font(.caption2.bold())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule()
                        .fill(bad ? AnyShapeStyle(.red) : AnyShapeStyle(gradient))
                        .frame(width: max(4, geo.size.width * min(1, value)))
                }
            }
            .frame(height: 5)
        }
    }
}

// MARK: - Widget declarations

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's Goals")
        .description("Calories, protein, water, and your streak — with one-tap water logging.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct FitnessWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}
