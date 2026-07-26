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
    var goalDate: Date?
    var hasPlan = false

    var caloriesLeft: Int { calorieBudget - caloriesEaten }

    /// Everything comes from the WidgetSnapshot the app precomputed — the
    /// render path never opens SwiftData, which is what kept getting this
    /// process killed at the ~30 MB widget memory cap (opening the store,
    /// especially with a grown WAL, spikes memory). The app rewrites the
    /// cache on every launch/background, and the water button below keeps it
    /// in sync, so today's numbers stay current without a fetch here.
    static func load() -> TodaySnapshot {
        var snapshot = TodaySnapshot()
        guard let cached = WidgetSnapshot.load(), cached.hasPlan else { return snapshot }
        snapshot.hasPlan = true
        snapshot.calorieBudget = cached.calorieBudget
        snapshot.proteinTarget = cached.proteinTarget
        snapshot.waterGoal = cached.waterGoal
        snapshot.waterStep = max(1, cached.waterStep)
        snapshot.streak = cached.streak
        snapshot.goalDate = cached.goalDate

        // Trust today's live totals only if the cache is actually for today;
        // if the app hasn't run since midnight, show targets with zero
        // progress rather than yesterday's numbers.
        if let day = cached.dayDate, Calendar.current.isDateInToday(day) {
            snapshot.caloriesEaten = cached.caloriesEaten
            snapshot.protein = cached.protein
            snapshot.waterOz = cached.waterOz
        }
        return snapshot
    }
}

/// Fetches today's DayLog by date predicate — O(1) regardless of history.
/// DayLog.date is normalized to startOfDay, but match by range so a
/// timezone change can't orphan the row. Used only by the water button
/// (a user tap, with more memory headroom than a render), never at render.
private func fetchToday(in context: ModelContext) -> DayLog? {
    let start = Calendar.current.startOfDay(for: Date())
    guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { return nil }
    var descriptor = FetchDescriptor<DayLog>(
        predicate: #Predicate { $0.date >= start && $0.date < end })
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
}

// MARK: - Interactive intent: log one water step from the widget

struct LogWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Water"
    static var description = IntentDescription("Adds one bottle/step of water to today's log.")

    func perform() async throws -> some IntentResult {
        let context = ModelContext(PersistenceController.shared.container)
        var cached = WidgetSnapshot.load() ?? WidgetSnapshot()
        let step = max(1, cached.waterStep)

        let day: DayLog
        if let existing = fetchToday(in: context) {
            day = existing
        } else if let plan = try? context.fetch(FetchDescriptor<Plan>()).first {
            // First log of the day: appending materializes the day rows but
            // not their foods/photos, so it stays under the widget memory cap.
            day = DayLog(date: Date())
            plan.days.append(day)
        } else {
            return .result()
        }
        day.waterOunces += step
        try? context.save()

        // Keep the render cache in sync so the widget shows the new total
        // without opening the DB. Refresh all three of today's numbers from
        // the row (cheap — today only) so a first-tap after midnight can't
        // leave yesterday's calories showing under today's date.
        cached.caloriesEaten = day.totalCalories
        cached.protein = day.totalProtein
        cached.waterOz = day.waterOunces
        cached.dayDate = Calendar.current.startOfDay(for: Date())
        cached.save()

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

private func hex(_ value: UInt32) -> Color {
    Color(.sRGB,
          red: Double((value >> 16) & 0xFF) / 255,
          green: Double((value >> 8) & 0xFF) / 255,
          blue: Double(value & 0xFF) / 255,
          opacity: 1)
}

/// Widgets follow the in-app accent palette — the app mirrors its theme
/// choice into the App Group defaults and reloads timelines on change.
/// Hues match ThemePalette in the app's Theme.swift.
private var accents: (Color, Color) {
    switch UserDefaults(suiteName: appGroupID)?.string(forKey: "theme.palette") ?? "emerald" {
    case "ocean":  return (hex(0x38BDF8), hex(0x6366F1))
    case "sunset": return (hex(0xFB923C), hex(0xF43F5E))
    case "violet": return (hex(0xA78BFA), hex(0xEC4899))
    case "rose":   return (hex(0xFB7185), hex(0xFBBF24))
    default:       return (hex(0x34D399), hex(0x22D3EE))   // emerald
    }
}
private var accent: Color { accents.0 }
private var accent2: Color { accents.1 }
private var gradient: LinearGradient {
    LinearGradient(colors: [accent, accent2],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
}
private let widgetBG = Color(red: 0.055, green: 0.067, blue: 0.086)

/// Deep base with an accent-tinted corner wash, so the themed color reads
/// even on a fresh day with nothing logged (when the ring/stat fills are
/// empty and would otherwise leave the widget looking grey).
private var widgetBackground: some View {
    ZStack {
        widgetBG
        LinearGradient(colors: [accent.opacity(0.28), accent2.opacity(0.12), .clear],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

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
        .containerBackground(for: .widget) { widgetBackground }
    }

    // Home screen medium — streak, stat columns, and one row of action buttons
    private var mediumView: some View {
        VStack(spacing: 9) {
            HStack {
                StreakBadge(streak: s.streak)
                Spacer()
            }

            HStack(spacing: 0) {
                statColumn("fork.knife", "Cal",
                           consumed: s.caloriesEaten, total: s.calorieBudget, overIsBad: true)
                statColumn("bolt.fill", "Protein",
                           consumed: s.protein, total: s.proteinTarget)
                statColumn("drop.fill", "Water",
                           consumed: s.waterOz, total: s.waterGoal)
            }

            HStack(spacing: 8) {
                Link(destination: URL(string: "seventyfive://log-food")!) {
                    actionLabel("fork.knife", "Food", accent, wide: true)
                }
                Link(destination: URL(string: "seventyfive://today")!) {
                    actionLabel("square.and.pencil", "Today", .orange, wide: true)
                }
                Button(intent: LogWaterIntent()) {
                    actionLabel("drop.fill", "+\(s.waterStep)oz", accent2, wide: true)
                }
                .buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    /// icon + label with the consumed/total value right underneath.
    private func statColumn(_ icon: String, _ label: String,
                            consumed: Int, total: Int, overIsBad: Bool = false) -> some View {
        let ok = overIsBad ? (consumed <= total && consumed > 0) : consumed >= total
        return VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            Text("\(consumed)/\(total)")
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundStyle(ok ? good : bad)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    // Home screen large — everything + weight
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StreakBadge(streak: s.streak, large: true)
                Spacer()
                if let d = s.goalDate {
                    Text("goal est. \(d.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Link(destination: URL(string: "seventyfive://log-food")!) {
                    actionLabel("fork.knife", "Log food", accent, wide: true)
                }
                Link(destination: URL(string: "seventyfive://today")!) {
                    actionLabel("square.and.pencil", "Today", .orange, wide: true)
                }
                Button(intent: LogWaterIntent()) {
                    actionLabel("drop.fill", "+\(s.waterStep) oz", accent2, wide: true)
                }
                .buttonStyle(.plain)
            }
        }
        .containerBackground(for: .widget) { widgetBackground }
    }

    private func actionLabel(_ icon: String, _ text: String, _ color: Color, wide: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.system(.caption2, design: .rounded).bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, wide ? 8 : 9)
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

/// Lock Screen / Dynamic Island live view of today's remaining budget.
struct FitnessLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FitnessActivityAttributes.self) { context in
            // Lock Screen banner
            HStack(spacing: 14) {
                StreakBadge(streak: context.state.streak)
                Spacer()
                liveStat("fork.knife",
                         context.state.caloriesLeft >= 0
                            ? "\(context.state.caloriesLeft) left"
                            : "\(-context.state.caloriesLeft) over",
                         context.state.caloriesLeft >= 0 ? good : bad)
                liveStat("bolt.fill",
                         "\(context.state.proteinGrams)/\(context.state.proteinTarget)g",
                         context.state.proteinGrams >= context.state.proteinTarget ? good : .secondary)
                liveStat("drop.fill",
                         "\(context.state.waterOz)/\(context.state.waterGoal)oz",
                         context.state.waterOz >= context.state.waterGoal ? good : .secondary)
            }
            .padding(14)
            .activityBackgroundTint(widgetBG)
            .activitySystemActionForegroundColor(accent)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StreakBadge(streak: context.state.streak)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.caloriesLeft >= 0
                         ? "\(context.state.caloriesLeft) cal left"
                         : "\(-context.state.caloriesLeft) cal over")
                        .font(.system(.subheadline, design: .rounded).bold())
                        .foregroundStyle(context.state.caloriesLeft >= 0 ? good : bad)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        RatioRow(icon: "bolt.fill", label: "Protein",
                                 consumed: context.state.proteinGrams,
                                 total: context.state.proteinTarget)
                        RatioRow(icon: "drop.fill", label: "Water",
                                 consumed: context.state.waterOz,
                                 total: context.state.waterGoal)
                    }
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(abs(context.state.caloriesLeft))")
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(context.state.caloriesLeft >= 0 ? good : bad)
            } minimal: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

private func liveStat(_ icon: String, _ text: String, _ color: Color) -> some View {
    VStack(spacing: 3) {
        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
        Text(text)
            .font(.system(.caption, design: .rounded).bold())
            .foregroundStyle(color)
    }
}

@main
struct FitnessWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        FitnessLiveActivity()
    }
}
