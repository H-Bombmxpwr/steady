import SwiftUI

/// Day-by-day history: a custom month grid (the system picker can't mark
/// days) where every logged day carries a small accent dot — today is the
/// outlined ring, the selected day is the filled pill. No endless list;
/// pick a day, see its score, open it.
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
                VStack(alignment: .leading, spacing: 14) {
                    MonthGrid(plan: plan, selected: $selectedDate)
                        .padding(.horizontal)

                    let day = ensureDay(plan: plan, date: selectedDate)
                    let f = fraction(for: day)
                    Card {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedDate.formatted(.dateTime.weekday(.wide).month().day()))
                                    .font(.headline)
                                Text("\(formattedDayNumber(for: selectedDate)) · \(Int(f * 100))% of goals")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            if let w = day.weight {
                                Text("\(w.formatted(.number.precision(.fractionLength(0...1)))) lb")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        GradientBar(value: f)
                        NavigationLink(value: selectedDate) {
                            Label("Open Day", systemImage: "square.and.pencil")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 14) {
                        legendItem(label: "today") {
                            Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                        }
                        legendItem(label: "logged") {
                            Circle().fill(Theme.accent)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .brandBackground()
            .navigationDestination(for: Date.self) { DayDetailView(plan: plan, profile: profile, date: $0) }
            .navigationTitle("Calendar")
        }
    }

    private func legendItem<S: View>(label: String, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 5) {
            swatch().frame(width: 8, height: 8)
            Text(label).font(.caption2).foregroundStyle(Theme.textDim)
        }
    }

    func formattedDayNumber(for date: Date) -> String {
        "Day \(max(0, plan.startDate.days(to: date)) + 1)"
    }
}

// MARK: - Month grid

/// One month of tappable day cells. Logged days show a small accent dot
/// under the number; today wears an outlined ring; the selected day is a
/// filled gradient circle. Days outside the plan (before start / future)
/// are dimmed and untappable.
private struct MonthGrid: View {
    var plan: Plan
    @Binding var selected: Date

    /// First day of the displayed month.
    @State private var month: Date

    private let cal = Calendar.current

    init(plan: Plan, selected: Binding<Date>) {
        self.plan = plan
        _selected = selected
        let comps = Calendar.current.dateComponents([.year, .month], from: selected.wrappedValue)
        _month = State(initialValue: Calendar.current.date(from: comps)!)
    }

    private var today: Date { cal.startOfDay(for: Date()) }

    private var canGoBack: Bool {
        month > cal.date(from: cal.dateComponents([.year, .month], from: plan.startDate))!
    }
    private var canGoForward: Bool {
        cal.date(byAdding: .month, value: 1, to: month)! <= today
    }

    /// Start-of-day for each logged (has-activity) day, for the dots.
    private var loggedDays: Set<Date> {
        Set(plan.days.filter(\.hasActivity).map { cal.startOfDay(for: $0.date) })
    }

    /// Leading blanks (nil) + every day of the month.
    private var cells: [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: month)
        let leading = (firstWeekday - cal.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + range.map {
            cal.date(byAdding: .day, value: $0 - 1, to: month)!
        }
    }

    /// Weekday symbols rotated to the calendar's first weekday.
    private var weekdaySymbols: [String] {
        let symbols = cal.veryShortWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }

    var body: some View {
        VStack(spacing: 10) {
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
            .font(.body.bold())
            .padding(.horizontal, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 6) {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s)
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.textDim)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayCell(date)
                    } else {
                        Color.clear.frame(height: 40)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.hairline))
        )
    }

    @ViewBuilder
    private func dayCell(_ date: Date) -> some View {
        let inRange = date >= plan.startDate && date <= today
        let isSelected = cal.isDate(date, inSameDayAs: selected)
        let isToday = cal.isDate(date, inSameDayAs: today)
        let isLogged = loggedDays.contains(date)

        Button {
            selected = date
        } label: {
            VStack(spacing: 3) {
                Text("\(cal.component(.day, from: date))")
                    .font(.system(.subheadline, design: .rounded).weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : (inRange ? .primary : Theme.textDim.opacity(0.5)))
                // The logged marker — a dot, so it can't be confused with
                // today's ring or the selection pill.
                Circle()
                    .fill(isLogged ? (isSelected ? Color.white : Theme.accent) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background {
                if isSelected {
                    Circle().fill(Theme.gradient).frame(width: 38, height: 38)
                } else if isToday {
                    Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!inRange)
    }
}
