import SwiftUI
import SwiftData

struct MainTabView: View {
    var state: ChallengeState
    var body: some View {
        TabView {
            DashboardView(state: state)
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
            CalendarScreen(state: state)
                .tabItem { Label("Calendar", systemImage: "calendar") }
            PhotosGalleryView(state: state)
                .tabItem { Label("Photos", systemImage: "photo.on.rectangle") }
            PresetsView(state: state)
                .tabItem { Label("Presets", systemImage: "list.bullet") }
            SettingsView(state: state)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    var state: ChallengeState
    @State private var today = Calendar.current.startOfDay(for: Date())

    // Break the math out of body
    private var elapsedDays: Int {
        max(0, daysBetween(state.startDate, today))
    }
    private var cappedIndex: Int {
        let cap = state.totalDays > 0 ? min(state.totalDays - 1, elapsedDays) : 0
        return max(0, cap)
    }
    private var currentDayNumber: Int { cappedIndex + 1 }
    private var remaining: Int { max(0, state.totalDays - currentDayNumber) }
    private var todayEntry: DayEntry { ensureDay(state: state, date: today) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HeaderBox(
                        currentDayNumber: currentDayNumber,
                        total: state.totalDays,
                        remaining: remaining,
                        today: today
                    )


                    TotalsBox(state: state, upTo: today)

                    ChecklistBox(state: state, day: todayEntry)

                    NavigationLink(value: today) {
                        Label("Open Today", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationDestination(for: Date.self) { d in
                DayDetailView(state: state, date: d)
            }
            .navigationTitle("Dashboard")
        }
    }

    // MARK: - Helpers

    private func daysBetween(_ start: Date, _ end: Date) -> Int {
        let a = Calendar.current.startOfDay(for: start)
        let b = Calendar.current.startOfDay(for: end)
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }
}

// MARK: - Subviews (keeps type-checker happy)

private struct HeaderBox: View {
    let currentDayNumber: Int
    let total: Int
    let remaining: Int
    let today: Date

    var body: some View {
        GroupBox {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day \(currentDayNumber) / \(total)")
                        .font(.title.bold())
                    Text("\(remaining) days to go")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(today, style: .date)
                        .font(.headline)
                    ProgressView(value: Double(currentDayNumber), total: Double(total))
                        .frame(width: 140)
                }
            }
        }
    }
}


private struct TotalsBox: View {
    let state: ChallengeState
    let upTo: Date

    var body: some View {
        GroupBox("Totals so far") {
            let s = sumStats(state: state, upTo: upTo)

            HStack {
                StatCell(title: "Indoor", value: hmString(s.indoorMin))
                Spacer()
                StatCell(title: "Outdoor", value: hmString(s.outdoorMin))
                Spacer()
                StatCell(title: "Pages", value: "\(s.pages)")
                Spacer()
                StatCell(title: "Water", value: "\(s.waterOz) oz")
            }

            if let start = state.startingWeight {
                Divider().padding(.vertical, 4)

                HStack {
                    Text("Weight start").foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f lb", start))
                }
                if let last = s.latestWeight {
                    HStack {
                        Text("Latest").foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f lb", last))
                    }
                }
                if let delta = s.deltaWeight {
                    HStack {
                        Text("Net change").foregroundStyle(.secondary)
                        Spacer()
                        let deltaColor: Color = (delta == 0) ? Color.primary : (delta < 0 ? Color.green : Color.red)
                        Text(signedWeight(delta) + " lb")
                            .foregroundColor(deltaColor)
                            .bold()

                    }
                }
            }
        }
    }

    // Local helpers to keep generic types small
    private func sumStats(state: ChallengeState, upTo date: Date) -> (indoorMin: Int, outdoorMin: Int, pages: Int, waterOz: Int, latestWeight: Double?, deltaWeight: Double?) {
        var indoor = 0, outdoor = 0, pages = 0, water = 0
        var lastWeight: Double? = nil
        let cutoff = Calendar.current.startOfDay(for: date)

        for d in state.days.sorted(by: { $0.date < $1.date }) {
            if d.date > cutoff { break }
            if d.workout1Outdoor { outdoor += d.workout1Minutes } else { indoor += d.workout1Minutes }
            if d.workout2Outdoor { outdoor += d.workout2Minutes } else { indoor += d.workout2Minutes }
            pages += max(0, d.pagesRead)
            water += max(0, d.waterOunces)
            if let w = d.weight { lastWeight = w }
        }

        var delta: Double? = nil
        if let start = state.startingWeight, let last = lastWeight { delta = last - start }
        return (indoor, outdoor, pages, water, lastWeight, delta)
    }

    private func hmString(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func signedWeight(_ d: Double) -> String {
        let sign = d > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", d))"
    }
}

private struct ChecklistBox: View {
    let state: ChallengeState
    let day: DayEntry

    var body: some View {
        GroupBox("Today's Checklist") {
            ChecklistRow(title: "Workout 1 ≥ 45 min", checked: day.workout1Minutes >= 45)
            ChecklistRow(title: "Workout 2 ≥ 45 min", checked: day.workout2Minutes >= 45)
            ChecklistRow(title: "One workout outdoors", checked: (day.workout1Outdoor || day.workout2Outdoor))
            ChecklistRow(title: "Water ≥ 128 oz", checked: day.waterOunces >= 128)
            ChecklistRow(title: "Read ≥ 10 pages", checked: day.pagesRead >= 10)
            ChecklistRow(title: "Diet compliant (\(state.dietName))", checked: day.dietCompliant)
            ChecklistRow(title: "Progress photo", checked: !day.photos.isEmpty)
            ChecklistRow(title: "Alcohol used this month", checked: usedAlcoholThisMonth(state: state, reference: day.date))
        }
    }

    private func usedAlcoholThisMonth(state: ChallengeState, reference: Date) -> Bool {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: reference)
        return state.days.contains { d in
            let dc = cal.dateComponents([.year, .month], from: d.date)
            return dc.year == comps.year && dc.month == comps.month && d.alcoholUsed
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

private struct StatCell: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).bold()
        }
    }
}
