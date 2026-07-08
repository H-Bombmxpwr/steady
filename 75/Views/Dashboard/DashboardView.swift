import SwiftUI
import SwiftData

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
            PresetsView(plan: plan)
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
                VStack(alignment: .leading, spacing: 16) {
                    WeightBox(plan: plan, dayNumber: dayNumber, today: today)

                    TodayBox(day: todayLog, targets: targets)

                    if let projected = plan.projectedGoalDate {
                        ProjectionBox(plan: plan, projected: projected)
                    }

                    NavigationLink(value: today) {
                        Label("Open Today", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationDestination(for: Date.self) { d in
                DayDetailView(plan: plan, profile: profile, date: d)
            }
            .navigationTitle("Dashboard")
        }
    }
}

// MARK: - Subviews

private struct WeightBox: View {
    let plan: Plan
    let dayNumber: Int
    let today: Date

    var body: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: "%.1f lb", plan.currentWeight))
                        .font(.title.bold())
                    let delta = plan.weightChange
                    let deltaColor: Color = (delta == 0) ? .primary : (delta < 0 ? .green : .red)
                    Text(String(format: "%@%.1f lb since start", delta > 0 ? "+" : "", delta))
                        .foregroundStyle(deltaColor)
                        .font(.subheadline.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(today, style: .date).font(.headline)
                    Text("Day \(dayNumber)").foregroundStyle(.secondary)
                    let toGo = plan.currentWeight - plan.goalWeight
                    if toGo > 0 {
                        Text(String(format: "%.1f lb to goal", toGo))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct TodayBox: View {
    let day: DayLog
    let targets: DailyTargets

    var body: some View {
        GroupBox("Today") {
            VStack(spacing: 12) {
                progressRow(
                    title: "Calories",
                    value: "\(day.caloriesEaten) / \(targets.calories) cal",
                    fraction: Double(day.caloriesEaten) / Double(max(1, targets.calories)),
                    overIsBad: true
                )
                progressRow(
                    title: "Protein",
                    value: "\(day.proteinGrams) / \(targets.proteinGrams) g",
                    fraction: Double(day.proteinGrams) / Double(max(1, targets.proteinGrams)),
                    overIsBad: false
                )
                progressRow(
                    title: "Water",
                    value: "\(day.waterOunces) / \(targets.waterOunces) oz",
                    fraction: Double(day.waterOunces) / Double(max(1, targets.waterOunces)),
                    overIsBad: false
                )
                HStack {
                    ChecklistRow(title: workoutLabel, checked: !day.workouts.isEmpty)
                }
                ChecklistRow(title: "Progress photo", checked: !day.photos.isEmpty)
                if day.alcoholDrinks > 0 {
                    HStack {
                        Image(systemName: "wineglass")
                        Text("\(day.alcoholDrinks) drink\(day.alcoholDrinks == 1 ? "" : "s") logged")
                        Spacer()
                    }
                    .foregroundStyle(.orange)
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var workoutLabel: String {
        day.workouts.isEmpty
            ? "Workout"
            : "Workout — \(day.workoutMinutes) min"
    }

    private func progressRow(title: String, value: String, fraction: Double, overIsBad: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value).foregroundStyle(.secondary)
            }
            ProgressView(value: min(1.0, fraction))
                .tint(overIsBad && fraction > 1.0 ? .red : .accentColor)
        }
    }
}

private struct ProjectionBox: View {
    let plan: Plan
    let projected: Date

    var body: some View {
        GroupBox("Projection") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Goal: \(String(format: "%.1f lb", plan.goalWeight))")
                    Text(String(format: "%.1f lb / week", plan.paceLbsPerWeek))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(projected.formatted(date: .abbreviated, time: .omitted)).bold()
                    Text("estimated").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Shared small views

struct ChecklistRow: View {
    let title: String
    let checked: Bool
    var body: some View {
        HStack {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
            Text(title)
            Spacer()
        }
        .foregroundStyle(checked ? .green : .secondary)
        .padding(.vertical, 4)
    }
}
