import SwiftUI

struct CalendarScreen: View {
    var plan: Plan
    var profile: UserProfile
    @State private var selectedDate = Date().startOfDay()

    private var targets: DailyTargets { CalorieEngine.targets(profile: profile, plan: plan) }

    private func fraction(for day: DayLog) -> Double {
        CalorieEngine.completionFraction(day: day, targets: targets,
                                         workoutScheduled: plan.isWorkoutScheduled(on: day.date))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: plan.startDate...Date().startOfDay(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)

                    let day = ensureDay(plan: plan, date: selectedDate)
                    let f = fraction(for: day)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(formattedDayNumber(for: selectedDate)) — \(Int(f * 100))% of goals")
                            .font(.headline)
                        GradientBar(value: f)
                    }
                    .padding(.horizontal)

                    NavigationLink("Open Day", value: selectedDate)
                        .buttonStyle(.bordered)
                        .padding(.horizontal)

                    Divider().padding(.horizontal)

                    // Logged days, most recent first
                    LazyVStack(spacing: 10) {
                        ForEach(plan.days.sorted(by: { $0.date > $1.date })) { d in
                            let f = fraction(for: d)
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(d.date, style: .date)
                                    Text(formattedDayNumber(for: d.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let w = d.weight {
                                    Text(String(format: "%.1f lb", w))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: f >= 1.0 ? "checkmark.seal.fill" : "seal")
                                    .foregroundStyle(f >= 1.0 ? Theme.accent : .secondary)
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedDate = d.date }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationDestination(for: Date.self) { DayDetailView(plan: plan, profile: profile, date: $0) }
            .navigationTitle("Calendar")
        }
    }

    func formattedDayNumber(for date: Date) -> String {
        "Day \(max(0, plan.startDate.days(to: date)) + 1)"
    }
}
