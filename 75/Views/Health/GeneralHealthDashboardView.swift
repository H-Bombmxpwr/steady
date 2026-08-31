import SwiftUI
import SwiftData

/// The general-health dashboard.
///
/// Neither of the other two fits someone who isn't chasing a number. There's
/// no deficit to defend and no session to fuel, so this one opens on the day
/// itself — what you ate, how well you ate it, whether you moved — and keeps
/// the scale as a quiet trend further down.
struct GeneralHealthDashboardView: View {
    @Environment(\.modelContext) private var context

    var plan: Plan
    var profile: UserProfile

    @State private var today = Calendar.current.startOfDay(for: Date())
    @State private var showSettings = false

    @AppStorage(Fasting.enabledKey) private var fastingEnabled = false

    private var dayNumber: Int { max(0, plan.startDate.days(to: today)) + 1 }
    private var todayLog: DayLog { ensureDay(plan: plan, date: today) }
    private var targets: DailyTargets { CalorieEngine.targets(profile: profile, plan: plan) }
    private var todayTargets: DailyTargets {
        CalorieEngine.targets(profile: profile, plan: plan, on: today)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    TodayCard(day: todayLog, targets: todayTargets, plan: plan)

                    GeneralHealthCard(plan: plan, day: todayLog)

                    MovementCard(plan: plan, day: todayLog)

                    if profile.cycleTracking {
                        CycleCard(plan: plan)
                    }

                    if fastingEnabled {
                        FastingCard(plan: plan)
                    }

                    WeightTrendCard(plan: plan)

                    StreakCard(stats: CalorieEngine.streakStats(plan: plan, targets: targets))

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
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(plan: plan, profile: profile)
            }
            .task {
                if await HealthKitService.shared.importExternalWorkouts(into: plan) > 0 {
                    try? context.save()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "heart.text.square.fill")
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
                    Text("Day \(dayNumber) · \(today.formatted(.dateTime.weekday(.wide).month().day()))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            Text(encouragement)
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

    /// One line under the header. Nothing here congratulates a number going
    /// down — that isn't what this mode is for.
    private var encouragement: String {
        let stats = CalorieEngine.streakStats(plan: plan, targets: targets)
        var lines: [String] = []
        if stats.current >= 3 {
            lines.append("\(stats.current) days of paying attention in a row. That's the whole thing.")
        }
        if stats.consistency >= 0.7, stats.daysTracked >= 14 {
            lines.append("You've logged \(Int(stats.consistency * 100))% of days. Consistency beats intensity here.")
        }
        lines.append("Maintenance isn't standing still — it's the hardest number to hold on purpose.")
        lines.append("Eat enough, move a bit, drink water. The unglamorous stuff is the stuff.")
        lines.append("No scale to beat today. Just a day to log honestly.")

        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return lines[dayOfYear % lines.count]
    }
}

// MARK: - Movement

/// Movement without a training plan attached: did you move today, and how
/// much have you moved this week. Deliberately not scored against a target —
/// there's no plan to fall behind on.
struct MovementCard: View {
    let plan: Plan
    let day: DayLog

    private var week: [DayLog] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekAgo = cal.date(byAdding: .day, value: -6, to: today)!
        return plan.days.filter { $0.date >= weekAgo && $0.date <= today }
    }

    var body: some View {
        Card(title: "Movement", icon: "figure.walk", tint: Theme.workoutTint) {
            let minutes = week.reduce(0) { $0 + $1.workoutMinutes }
            let days = week.filter { !$0.workouts.isEmpty }.count

            HStack(spacing: 18) {
                stat("\(day.workoutMinutes)", "min today")
                stat("\(minutes)", "min, 7 days")
                stat("\(days)/7", "days active")
            }

            // 150 min/week of moderate activity is the WHO's adult floor —
            // shown as context, not as a goal you can fail.
            Text(minutes >= 150
                 ? "Past 150 minutes this week — the usual weekly guideline for adults."
                 : "\(max(0, 150 - minutes)) minutes short of the 150-a-week guideline. Walking counts.")
                .font(.caption)
                .foregroundStyle(Theme.textDim)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title3, design: .rounded).bold())
            Text(label).font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - General health add-on

/// The nutrition-quality numbers that neither a deficit nor a training plan
/// will surface on their own. The heart of general-health mode, and an opt-in
/// add-on card on the other two dashboards.
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
