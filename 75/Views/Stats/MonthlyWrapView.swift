import SwiftUI
import SwiftData

/// "Wrapped"-style month recap: one poster of the month's numbers, private
/// by default, shareable as an image. Chevrons walk back through history.
struct MonthlyWrapView: View {
    @Environment(\.dismiss) private var dismiss
    var plan: Plan
    var profile: UserProfile

    /// First day of the displayed month.
    @State private var month = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))!
    @State private var shareItem: UIImage?
    @State private var presentShare = false

    private var cal: Calendar { Calendar.current }
    private var canGoForward: Bool {
        cal.date(byAdding: .month, value: 1, to: month)! <= Date()
    }
    private var canGoBack: Bool {
        cal.date(byAdding: .month, value: 1, to: month)! > plan.startDate
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Button {
                            month = cal.date(byAdding: .month, value: -1, to: month)!
                        } label: { Image(systemName: "chevron.left") }
                        .disabled(!canGoBack)
                        Spacer()
                        Text(month.formatted(.dateTime.month(.wide).year()))
                            .font(.headline)
                        Spacer()
                        Button {
                            month = cal.date(byAdding: .month, value: 1, to: month)!
                        } label: { Image(systemName: "chevron.right") }
                        .disabled(!canGoForward)
                    }
                    .font(.title3.bold())
                    .padding(.horizontal, 4)

                    poster

                    Button {
                        let renderer = ImageRenderer(content: poster.frame(width: 360))
                        renderer.scale = 3
                        if let img = renderer.uiImage {
                            shareItem = img
                            presentShare = true
                        }
                    } label: {
                        Label("Share as Image", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
                .padding()
            }
            .brandBackground()
            .navigationTitle("Month in Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $presentShare) {
                if let shareItem {
                    ActivityView(activityItems: [shareItem])
                }
            }
        }
    }

    // MARK: - Poster

    private var poster: some View {
        let s = MonthSummary(plan: plan, profile: profile, month: month)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(.white.opacity(0.22)))
                VStack(alignment: .leading, spacing: 0) {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.system(.title3, design: .rounded).bold())
                    Text("Month in Review")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer()
            }

            if s.daysLogged == 0 {
                Text("Nothing logged this month.")
                    .font(.subheadline)
                    .opacity(0.9)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%+.1f", s.trendDelta))
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                    Text("lb this month")
                        .font(.headline)
                        .opacity(0.85)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: 14) {
                    stat("\(s.daysLogged)", "days showed up")
                    stat("\(s.bestStreak)", "best streak")
                    stat(s.workoutCount > 0 ? "\(s.workoutCount) · \(hm(s.workoutMinutes))" : "0",
                         "workouts")
                    stat("\(s.waterGallons.formatted(.number.precision(.fractionLength(1)))) gal",
                         "water drunk")
                    if s.avgCalories > 0 {
                        stat("\(s.avgCalories)", "avg cal (budget \(s.budget))")
                    }
                    if let top = s.topFood {
                        stat(top.name, "most-logged food (\(top.count)×)")
                    }
                    if s.photos > 0 { stat("\(s.photos)", "progress photos") }
                    if s.drinks > 0 { stat(s.drinks.formatted(), "drinks") }
                }
            }

            Text("Made with Steady")
                .font(.caption2.bold())
                .opacity(0.7)
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.gradient)
        )
        .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 5)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .opacity(0.85)
        }
    }

    private func hm(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

/// Everything the poster shows, computed from one month of logs.
private struct MonthSummary {
    let trendDelta: Double
    let daysLogged: Int
    let bestStreak: Int
    let workoutCount: Int
    let workoutMinutes: Int
    let waterGallons: Double
    let avgCalories: Int
    let budget: Int
    let topFood: (name: String, count: Int)?
    let photos: Int
    let drinks: Double

    init(plan: Plan, profile: UserProfile, month: Date) {
        let cal = Calendar.current
        let start = month
        let end = min(cal.date(byAdding: DateComponents(month: 1, day: -1), to: month)!,
                      cal.startOfDay(for: Date()))
        let days = plan.days
            .filter { $0.date >= start && $0.date <= end }
            .sorted { $0.date < $1.date }
        let byDate = Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) })

        let trend = CalorieEngine.weightTrend(plan: plan)
            .filter { $0.date >= start && $0.date <= end }
        trendDelta = trend.count >= 2
            ? (trend.last?.trend ?? 0) - (trend.first?.trend ?? 0) : 0

        daysLogged = days.filter(\.hasActivity).count

        var best = 0, run = 0
        var d = start
        while d <= end {
            if byDate[d]?.hasActivity == true { run += 1; best = max(best, run) } else { run = 0 }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? end.addingTimeInterval(1)
        }
        bestStreak = best

        let workouts = days.flatMap(\.workouts)
        workoutCount = workouts.count
        workoutMinutes = workouts.reduce(0) { $0 + $1.minutes }
        waterGallons = Double(days.reduce(0) { $0 + $1.waterOunces }) / 128.0

        let logged = days.filter { $0.totalCalories > 0 }
        avgCalories = logged.isEmpty ? 0
            : logged.reduce(0) { $0 + $1.totalCalories } / logged.count
        budget = CalorieEngine.targets(profile: profile, plan: plan).calories

        let counts = Dictionary(grouping: days.flatMap(\.foods), by: \.name)
            .mapValues(\.count)
        // A "favorite" needs at least a repeat — one-offs aren't a pattern.
        topFood = counts.filter { $0.value >= 2 }
            .max { $0.value < $1.value }
            .map { (name: $0.key, count: $0.value) }

        photos = days.reduce(0) { $0 + $1.photos.count }
        drinks = days.reduce(0.0) { $0 + $1.standardDrinks }
    }
}
