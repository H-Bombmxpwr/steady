import SwiftUI
import SwiftData
import Charts

enum StatsRange: String, CaseIterable, Identifiable {
    case week = "7D"
    case month = "30D"
    case quarter = "90D"
    case ytd = "YTD"
    case all = "All"
    case custom = "Custom"

    var id: String { rawValue }
}

enum StatsTab: String, CaseIterable, Identifiable {
    case body = "Body"
    case food = "Food"
    var id: String { rawValue }
}

/// Every tracked series, charted over a selectable time range.
/// Two tabs: Body (weight, water, workouts, health) and Food (everything
/// nutrition).
struct StatsView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan
    var profile: UserProfile

    @State private var tab: StatsTab = .body
    @State private var range: StatsRange = .month
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
    @State private var customEnd = Date()

    // HealthKit series
    @State private var steps: [Date: Int] = [:]
    @State private var sleep: [Date: Double] = [:]

    @State private var showMeasurementSheet = false

    private var targets: DailyTargets { CalorieEngine.targets(profile: profile, plan: plan) }

    private var interval: (start: Date, end: Date) {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date())
        switch range {
        case .week:    return (cal.date(byAdding: .day, value: -6, to: end)!, end)
        case .month:   return (cal.date(byAdding: .day, value: -29, to: end)!, end)
        case .quarter: return (cal.date(byAdding: .day, value: -89, to: end)!, end)
        case .ytd:     return (cal.date(from: cal.dateComponents([.year], from: end))!, end)
        case .all:     return (plan.startDate, end)
        case .custom:  return (cal.startOfDay(for: customStart), cal.startOfDay(for: customEnd))
        }
    }

    private var daysInRange: [DayLog] {
        plan.days
            .filter { $0.date >= interval.start && $0.date <= interval.end }
            .sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Picker("Section", selection: $tab) {
                        ForEach(StatsTab.allCases) { t in Text(t.rawValue).tag(t) }
                    }
                    .pickerStyle(.segmented)

                    rangePicker

                    if tab == .body {
                        bodyTiles
                        weightChart
                        waterChart
                        workoutChart
                        if !steps.isEmpty { stepsChart }
                        if !sleep.isEmpty { sleepChart }
                        measurementsCard
                    } else {
                        foodTiles
                        caloriesChart
                        proteinChart
                        densityChart
                        fiberChart
                        sodiumChart
                        alcoholChart
                        if plan.labs.contains(where: { !$0.isEmpty }) { labsChart }
                    }
                }
                .padding()
            }
            .brandBackground()
            .navigationTitle("Stats")
            .task { await loadHealth() }
            .onChange(of: range) { _ in Task { await loadHealth() } }
            .sheet(isPresented: $showMeasurementSheet) {
                MeasurementSheet(plan: plan)
                    .themedRoot()
            }
        }
    }

    private func loadHealth() async {
        let days = max(7, Calendar.current.dateComponents([.day], from: interval.start, to: Date()).day ?? 30)
        steps = await HealthKitService.shared.dailySteps(days: days)
        sleep = await HealthKitService.shared.nightlySleepHours(days: days)
        _ = await HealthKitService.shared.importExternalWeights(into: plan)
        try? context.save()
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        VStack(spacing: 8) {
            Picker("Range", selection: $range) {
                ForEach(StatsRange.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
            if range == .custom {
                HStack {
                    DatePicker("From", selection: $customStart, in: plan.startDate...Date(), displayedComponents: .date)
                        .labelsHidden()
                    Text("–").foregroundStyle(Theme.textDim)
                    DatePicker("To", selection: $customEnd, in: customStart...Date(), displayedComponents: .date)
                        .labelsHidden()
                }
            }
        }
    }

    // MARK: - Summary tiles

    private var bodyTiles: some View {
        let days = daysInRange
        let totalMin = days.reduce(0) { $0 + $1.workoutMinutes }
        let totalWater = days.reduce(0) { $0 + $1.waterOunces }
        let trend = CalorieEngine.weightTrend(plan: plan)
        let trendInRange = trend.filter { $0.date >= interval.start && $0.date <= interval.end }
        let weightDelta = (trendInRange.last?.trend ?? 0) - (trendInRange.first?.trend ?? 0)

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile(String(format: "%+.1f", trendInRange.count >= 2 ? weightDelta : 0), "lb trend",
                 tint: Theme.weightTint)
            tile(hm(totalMin), "exercise", tint: Theme.workoutTint)
            tile("\(totalWater / max(1, days.count))", "avg oz water", tint: Theme.waterTint)
        }
    }

    private var foodTiles: some View {
        let days = daysInRange
        let logged = days.filter { $0.totalCalories > 0 }
        let avgCal = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.totalCalories } / logged.count
        let avgProtein = logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.totalProtein } / logged.count
        let facts = logged.map(\.totalFacts)
        let avgFiber = facts.isEmpty ? 0 : facts.reduce(0.0) { $0 + $1.fiberGrams } / Double(facts.count)
        let avgSodium = facts.isEmpty ? 0 : facts.reduce(0.0) { $0 + $1.sodiumMg } / Double(facts.count)
        let drinks = days.reduce(0.0) { $0 + $1.standardDrinks }

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            tile("\(avgCal)", "avg cal", tint: Theme.foodTint)
            tile("\(avgProtein)", "avg g protein", tint: Theme.workoutTint)
            tile("\(Int(avgFiber))", "avg g fiber", tint: .green)
            tile("\(Int(avgSodium))", "avg mg sodium", tint: Theme.weightTint)
            tile(drinks.formatted(), "drinks", tint: Theme.alcoholTint)
            tile("\(logged.count)/\(max(1, days.count))", "days logged", tint: Theme.supplementTint)
        }
    }

    private func tile(_ value: String, _ label: String, tint: Color = Theme.accent) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.headline, design: .rounded))
                .foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.25)))
        )
    }

    private func hm(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: - Charts

    private var weightChart: some View {
        let trend = CalorieEngine.weightTrend(plan: plan)
            .filter { $0.date >= interval.start && $0.date <= interval.end }
        return ChartCard(title: "Weight", empty: trend.count < 2,
                         emptyText: "Log weigh-ins to see your trend.") {
            Chart {
                ForEach(trend) { p in
                    if let raw = p.raw {
                        PointMark(x: .value("Date", p.date), y: .value("lb", raw))
                            .foregroundStyle(.white.opacity(0.25)).symbolSize(18)
                    }
                    LineMark(x: .value("Date", p.date), y: .value("Trend", p.trend))
                        .foregroundStyle(Theme.gradient)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(y: .value("Goal", plan.goalWeight))
                    .foregroundStyle(Theme.warn.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartYScale(domain: .automatic(includesZero: false))
        }
    }

    private var caloriesChart: some View {
        let data = daysInRange.filter { $0.totalCalories > 0 }
        return ChartCard(title: "Calories vs Budget", empty: data.isEmpty,
                         emptyText: "Log food to see calories here.") {
            Chart {
                ForEach(data) { d in
                    BarMark(x: .value("Date", d.date, unit: .day), y: .value("cal", d.totalCalories))
                        .foregroundStyle(d.totalCalories <= targets.calories
                                         ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.danger))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Budget", targets.calories))
                    .foregroundStyle(Theme.warn.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    private var proteinChart: some View {
        let data = daysInRange.filter { $0.totalProtein > 0 }
        return ChartCard(title: "Protein", empty: data.isEmpty,
                         emptyText: "Protein shows up once you log food.") {
            Chart {
                ForEach(data) { d in
                    BarMark(x: .value("Date", d.date, unit: .day), y: .value("g", d.totalProtein))
                        .foregroundStyle(d.totalProtein >= targets.proteinGrams
                                         ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface2))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", targets.proteinGrams))
                    .foregroundStyle(Theme.warn.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    private var waterChart: some View {
        let data = daysInRange.filter { $0.waterOunces > 0 }
        return ChartCard(title: "Water", empty: data.isEmpty,
                         emptyText: "Water logs appear here.") {
            Chart {
                ForEach(data) { d in
                    BarMark(x: .value("Date", d.date, unit: .day), y: .value("oz", d.waterOunces))
                        .foregroundStyle(d.waterOunces >= targets.waterOunces
                                         ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Theme.surface2))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", targets.waterOunces))
                    .foregroundStyle(Theme.warn.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    private var workoutChart: some View {
        struct Slice: Identifiable {
            let date: Date; let category: String; let minutes: Int
            var id: String { "\(date)-\(category)" }
        }
        let slices: [Slice] = daysInRange.flatMap { d in
            Dictionary(grouping: d.workouts, by: { $0.category.label })
                .map { Slice(date: d.date, category: $0.key, minutes: $0.value.reduce(0) { $0 + $1.minutes }) }
        }
        return ChartCard(title: "Workouts by Type", empty: slices.isEmpty,
                         emptyText: "Logged workouts stack up here by type.") {
            Chart(slices) { s in
                BarMark(x: .value("Date", s.date, unit: .day), y: .value("min", s.minutes))
                    .foregroundStyle(by: .value("Type", s.category))
                    .cornerRadius(3)
            }
            .chartLegend(position: .bottom, spacing: 8)
        }
    }

    /// Where the calories came from, Noom-style: stacked green/orange/red
    /// per day (gray = foods without a density rating, e.g. quick adds).
    private var densityChart: some View {
        struct Slice: Identifiable {
            let date: Date; let bucket: String; let calories: Int
            var id: String { "\(date)-\(bucket)" }
        }
        let slices: [Slice] = daysInRange.flatMap { d -> [Slice] in
            Dictionary(grouping: d.foods, by: { FoodDensity(rawValue: $0.density ?? "")?.rawValue ?? "unrated" })
                .map { Slice(date: d.date, bucket: $0.key.capitalized,
                             calories: $0.value.reduce(0) { $0 + $1.calories }) }
        }.filter { $0.calories > 0 }
        return ChartCard(title: "Calorie Density Mix", empty: slices.isEmpty,
                         emptyText: "Log foods to see how much of your intake is green vs red.") {
            Chart(slices) { s in
                BarMark(x: .value("Date", s.date, unit: .day), y: .value("cal", s.calories))
                    .foregroundStyle(by: .value("Bucket", s.bucket))
                    .cornerRadius(3)
            }
            .chartForegroundStyleScale([
                "Green": Color.green, "Orange": Color.orange,
                "Red": Color.red, "Unrated": Color.gray.opacity(0.5)
            ])
            .chartLegend(position: .bottom, spacing: 8)
        }
    }

    private var fiberChart: some View {
        let data = daysInRange.map { (date: $0.date, grams: $0.totalFacts.fiberGrams) }
            .filter { $0.grams > 0 }
        return ChartCard(title: "Fiber (goal 28 g)", empty: data.isEmpty,
                         emptyText: "Fiber shows up once foods carry detailed nutrition.") {
            Chart(data, id: \.date) { d in
                BarMark(x: .value("Date", d.date, unit: .day), y: .value("g", d.grams))
                    .foregroundStyle(d.grams >= 28
                                     ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.surface2))
                    .cornerRadius(3)
            }
            .chartYAxisLabel("g")
        }
    }

    private var sodiumChart: some View {
        let data = daysInRange.map { (date: $0.date, mg: $0.totalFacts.sodiumMg) }
            .filter { $0.mg > 0 }
        return ChartCard(title: "Sodium (limit 2,300 mg)", empty: data.isEmpty,
                         emptyText: "Sodium shows up once foods carry detailed nutrition.") {
            Chart {
                ForEach(data, id: \.date) { d in
                    BarMark(x: .value("Date", d.date, unit: .day), y: .value("mg", d.mg))
                        .foregroundStyle(d.mg > 2300
                                         ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.gradient))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Limit", 2300))
                    .foregroundStyle(Theme.warn.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
    }

    /// Logged lab panels over time — the levers the Food charts above
    /// pull on (worth bringing to the doctor, not medical advice).
    private var labsChart: some View {
        struct Point: Identifiable {
            let date: Date; let marker: String; let value: Double
            var id: String { "\(date)-\(marker)" }
        }
        let panels = plan.labs.filter { !$0.isEmpty }.sorted { $0.date < $1.date }
        let points: [Point] = panels.flatMap { l -> [Point] in
            var out: [Point] = []
            if let v = l.ldl { out.append(Point(date: l.date, marker: "LDL", value: v)) }
            if let v = l.hdl { out.append(Point(date: l.date, marker: "HDL", value: v)) }
            if let v = l.triglycerides { out.append(Point(date: l.date, marker: "Triglycerides", value: v)) }
            if let v = l.fastingGlucose { out.append(Point(date: l.date, marker: "Glucose", value: v)) }
            return out
        }
        return ChartCard(title: "Lab Panels (mg/dL)", empty: points.isEmpty,
                         emptyText: "Log lab results in Settings → Blood Work to track them here.") {
            Chart(points) { pt in
                LineMark(x: .value("Date", pt.date, unit: .day), y: .value("mg/dL", pt.value))
                    .foregroundStyle(by: .value("Marker", pt.marker))
                    .symbol(by: .value("Marker", pt.marker))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartLegend(position: .bottom, spacing: 8)
        }
    }

    private var alcoholChart: some View {
        let data = daysInRange.filter { $0.standardDrinks > 0 }
        return ChartCard(title: "Alcohol (standard drinks)", empty: data.isEmpty,
                         emptyText: "No drinks logged in this range. 🎉") {
            Chart(data) { d in
                BarMark(x: .value("Date", d.date, unit: .day), y: .value("drinks", d.standardDrinks))
                    .foregroundStyle(Theme.warn)
                    .cornerRadius(3)
            }
        }
    }

    private var stepsChart: some View {
        let data = steps
            .filter { $0.key >= interval.start && $0.key <= interval.end }
            .sorted { $0.key < $1.key }
        return ChartCard(title: "Steps (Apple Health)", empty: data.isEmpty, emptyText: "") {
            Chart(data, id: \.key) { day, count in
                BarMark(x: .value("Date", day, unit: .day), y: .value("steps", count))
                    .foregroundStyle(Theme.gradient)
                    .cornerRadius(3)
            }
        }
    }

    private var sleepChart: some View {
        let data = sleep
            .filter { $0.key >= interval.start && $0.key <= interval.end }
            .sorted { $0.key < $1.key }
        return ChartCard(title: "Sleep (Apple Health)", empty: data.isEmpty, emptyText: "") {
            Chart(data, id: \.key) { day, hours in
                BarMark(x: .value("Date", day, unit: .day), y: .value("h", hours))
                    .foregroundStyle(Color(hex: 0x818CF8))
                    .cornerRadius(3)
            }
            .chartYAxisLabel("hours")
        }
    }

    private var measurementsCard: some View {
        let data = plan.measurements
            .filter { $0.date >= interval.start && $0.date <= interval.end && !$0.isEmpty }
            .sorted { $0.date < $1.date }
        struct Point: Identifiable {
            let date: Date; let part: String; let value: Double
            var id: String { "\(date)-\(part)" }
        }
        let points: [Point] = data.flatMap { m -> [Point] in
            var out: [Point] = []
            if let v = m.waist { out.append(Point(date: m.date, part: "Waist", value: v)) }
            if let v = m.hips { out.append(Point(date: m.date, part: "Hips", value: v)) }
            if let v = m.chest { out.append(Point(date: m.date, part: "Chest", value: v)) }
            if let v = m.arm { out.append(Point(date: m.date, part: "Arm", value: v)) }
            if let v = m.thigh { out.append(Point(date: m.date, part: "Thigh", value: v)) }
            return out
        }
        return Card(title: "Measurements", icon: "ruler.fill", tint: Theme.weightTint) {
            if points.isEmpty {
                Text("Track waist, hips, chest, arm, and thigh — inches often move before the scale does.")
                    .font(.footnote).foregroundStyle(Theme.textDim)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Date", p.date, unit: .day), y: .value("in", p.value))
                        .foregroundStyle(by: .value("Part", p.part))
                        .symbol(by: .value("Part", p.part))
                        .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 170)
            }
            Button {
                showMeasurementSheet = true
            } label: {
                Label("Log Measurements", systemImage: "ruler")
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Chart card wrapper

private struct ChartCard<Content: View>: View {
    let title: String
    let empty: Bool
    let emptyText: String
    @ViewBuilder var content: Content

    var body: some View {
        Card(title: title) {
            if empty {
                Text(emptyText).font(.footnote).foregroundStyle(Theme.textDim)
            } else {
                content
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel().foregroundStyle(Theme.textDim)
                            AxisGridLine().foregroundStyle(.white.opacity(0.06))
                        }
                    }
                    .chartYAxis {
                        AxisMarks {
                            AxisValueLabel().foregroundStyle(Theme.textDim)
                            AxisGridLine().foregroundStyle(.white.opacity(0.06))
                        }
                    }
                    .frame(height: 170)
            }
        }
    }
}

// MARK: - Measurement entry

private struct MeasurementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var plan: Plan

    @State private var date = Date()
    @State private var waist = ""
    @State private var hips = ""
    @State private var chest = ""
    @State private var arm = ""
    @State private var thigh = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                Section("Inches (leave blank to skip)") {
                    field("Waist", $waist)
                    field("Hips", $hips)
                    field("Chest", $chest)
                    field("Arm", $arm)
                    field("Thigh", $thigh)
                }
                Button("Save") {
                    let m = MeasurementLog(date: date)
                    m.waist = Double(waist)
                    m.hips = Double(hips)
                    m.chest = Double(chest)
                    m.arm = Double(arm)
                    m.thigh = Double(thigh)
                    if !m.isEmpty {
                        plan.measurements.append(m)
                        try? context.save()
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .themedForm()
            .navigationTitle("Measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func field(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}
