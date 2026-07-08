import SwiftUI

struct CalendarScreen: View {
    var state: ChallengeState
    @State private var selectedDate = Date().startOfDay()

    private var lastChallengeDay: Date {
        Calendar.current.date(byAdding: .day, value: state.totalDays - 1, to: state.startDate)!.startOfDay()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        in: state.startDate...min(lastChallengeDay, Date().startOfDay()),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)

                    let day = ensureDay(state: state, date: selectedDate)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(formattedDayNumber(for: selectedDate)) — \(day.isComplete ? "Complete" : "Incomplete")")
                            .font(.headline)
                        ProgressView(value: completionFraction(for: day))
                    }
                    .padding(.horizontal)

                    NavigationLink("Open Day", value: selectedDate)
                        .buttonStyle(.bordered)
                        .padding(.horizontal)

                    Divider().padding(.horizontal)

                    // All days grid/list — full page scrolls as one
                    LazyVStack(spacing: 10) {
                        ForEach(state.days.sorted(by: { $0.date < $1.date })) { d in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(d.date, style: .date)
                                    Text(formattedDayNumber(for: d.date))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: d.isComplete ? "checkmark.seal.fill" : "xmark.seal")
                                    .foregroundStyle(d.isComplete ? .green : .red)
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedDate = d.date }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationDestination(for: Date.self) { DayDetailView(state: state, date: $0) }
            .navigationTitle("Calendar")
        }
    }

    func completionFraction(for d: DayEntry) -> Double {
        let checks: [Bool] = [
            d.workout1Minutes >= 45,
            d.workout2Minutes >= 45,
            (d.workout1Outdoor || d.workout2Outdoor),
            d.waterOunces >= 128,
            d.pagesRead >= 10,
            d.dietCompliant,
            !d.photos.isEmpty
        ]
        return Double(checks.filter { $0 }.count) / Double(checks.count)
    }

    func formattedDayNumber(for date: Date) -> String {
        let idx = max(0, min(state.totalDays - 1, state.startDate.days(to: date)))
        return "Day \(idx + 1)"
    }
}
