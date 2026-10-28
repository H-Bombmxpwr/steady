import WidgetKit
import SwiftUI

// The BeReal idea, pointed at meals: something on the Lock Screen that
// changes the moment it's time to eat — not a notification you swipe away,
// just the buddy standing there with a countdown until you've logged it.
//
// It costs nothing to keep current: the timeline holds an entry for every
// window opening and closing, so it flips at mealtime on its own, and the app
// reloads it the moment something is logged.

struct MealtimeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var state: MealState { snapshot.mealState(at: date) }
}

struct MealtimeProvider: TimelineProvider {
    func placeholder(in context: Context) -> MealtimeEntry {
        var s = WidgetSnapshot()
        s.meals = [MealMoment(meal: "lunch", label: "Lunch", minutes: 12 * 60 + 30)]
        return MealtimeEntry(date: Date(), snapshot: s)
    }

    func getSnapshot(in context: Context, completion: @escaping (MealtimeEntry) -> Void) {
        completion(MealtimeEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? WidgetSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MealtimeEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load() ?? WidgetSnapshot()
        let horizon = now.addingTimeInterval(36 * 3600)
        let dates = [now] + snapshot.mealBoundaries(from: now, to: horizon)
        let entries = dates.map { MealtimeEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(horizon)))
    }
}

struct MealtimeWidgetView: View {
    let entry: MealtimeEntry
    @Environment(\.widgetFamily) private var family

    private var name: String { WidgetSnapshot.buddyName }
    private var buddy: Image { Image(WidgetSnapshot.buddyAsset) }

    var body: some View {
        content
            .widgetURL(URL(string: dueNow ? "seventyfive://log-food" : "seventyfive://today"))
            .containerBackground(for: .widget) {
                LinearGradient(colors: [Color(red: 0.19, green: 0.18, blue: 0.51),
                                        Color(red: 0.12, green: 0.11, blue: 0.29)],
                               startPoint: .top, endPoint: .bottom)
            }
    }

    private var dueNow: Bool {
        if case .due = entry.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // MARK: Lock Screen

    private var rectangular: some View {
        HStack(spacing: 6) {
            buddy.resizable().scaledToFit().frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 0) {
                switch entry.state {
                case let .due(meal, _, end):
                    Text("\(meal.label) time").font(.headline).widgetAccentable()
                    HStack(spacing: 3) {
                        Text(timerInterval: entry.date...end, countsDown: true)
                            .monospacedDigit()
                            .frame(maxWidth: 52, alignment: .leading)
                        Text("to log")
                    }
                    .font(.caption)
                    Text("\(name) is waiting").font(.caption2).foregroundStyle(.secondary)
                case let .logged(meal, next):
                    Text("\(meal.label) logged ✓").font(.headline)
                    if let next {
                        Text("Next: \(next.0.label) \(next.1, style: .time)").font(.caption)
                    }
                    Text("\(name) approves").font(.caption2).foregroundStyle(.secondary)
                case let .upcoming(meal, at):
                    Text("Next: \(meal.label)").font(.headline)
                    Text(at, style: .time).font(.caption)
                    progressLine
                case .wrapped:
                    Text("That's a wrap").font(.headline)
                    progressLine
                    Text("\(name) is off to bed").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var progressLine: some View {
        let p = entry.snapshot.mealProgress(at: entry.date)
        return Text("\(p.logged)/\(p.planned) meals logged").font(.caption2).foregroundStyle(.secondary)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            switch entry.state {
            case let .due(_, _, end):
                VStack(spacing: 0) {
                    Image(systemName: "fork.knife").font(.caption.bold()).widgetAccentable()
                    Text(timerInterval: entry.date...end, countsDown: true)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 44)
                }
            default:
                buddy.resizable().scaledToFit().padding(7)
            }
        }
    }

    private var inline: some View {
        switch entry.state {
        case let .due(meal, _, _):
            return Text("🍽 \(meal.label) time — log it")
        case let .logged(meal, _):
            return Text("✓ \(meal.label) logged")
        case let .upcoming(meal, at):
            return Text("Next: \(meal.label) \(at, style: .time)")
        case .wrapped:
            let p = entry.snapshot.mealProgress(at: entry.date)
            return Text("\(p.logged)/\(p.planned) meals logged today")
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                buddy.resizable().scaledToFit().frame(width: 52, height: 52)
                Spacer()
                if dueNow {
                    Image(systemName: "fork.knife.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            switch entry.state {
            case let .due(meal, _, end):
                Text("\(meal.label) time").font(.headline).foregroundStyle(.white)
                Text(timerInterval: entry.date...end, countsDown: true)
                    .font(.system(.title3, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(.orange)
                Text("Tap to log it").font(.caption2).foregroundStyle(.white.opacity(0.7))
            case let .logged(meal, _):
                Text("\(meal.label) logged").font(.headline).foregroundStyle(.white)
                Text("\(name) approves").font(.caption).foregroundStyle(.white.opacity(0.7))
            case let .upcoming(meal, at):
                Text("Next: \(meal.label)").font(.headline).foregroundStyle(.white)
                Text(at, style: .time).font(.caption).foregroundStyle(.white.opacity(0.7))
            case .wrapped:
                let p = entry.snapshot.mealProgress(at: entry.date)
                Text("That's a wrap").font(.headline).foregroundStyle(.white)
                Text("\(p.logged)/\(p.planned) meals logged").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

struct MealtimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MealtimeWidget", provider: MealtimeProvider()) { entry in
            MealtimeWidgetView(entry: entry)
        }
        .configurationDisplayName("Mealtime")
        .description("Your studio buddy on the Lock Screen — it flips to a countdown when it's time to log a meal.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall])
    }
}
