import SwiftUI

// MARK: - Dashboard card

/// Today's Fuel — appears only on days with a scheduled workout. Shows the
/// carbs-per-hour target (and the calories added back to the budget) at a
/// glance; tap a session for the full during/before/after breakdown.
struct FuelCard: View {
    let plan: Plan
    @State private var detail: FuelingPlan?

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var workouts: [WorkoutScheduleEntry] {
        plan.scheduledWorkouts(on: today).sorted { $0.minutes > $1.minutes }
    }
    private func fuel(for entry: WorkoutScheduleEntry) -> FuelingPlan {
        FuelingEngine.plan(category: entry.category, intensity: entry.intensity,
                           minutes: entry.minutes, bodyweightLbs: plan.currentWeight)
    }
    private var totalBurn: Int {
        workouts.reduce(0) { $0 + fuel(for: $1).burnCalories }
    }

    var body: some View {
        Card(title: "Today's Fuel", icon: "bolt.fill", tint: Theme.foodTint) {
            ForEach(workouts, id: \.persistentModelID) { entry in
                let fp = fuel(for: entry)
                Button { detail = fp } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).foregroundStyle(.primary)
                            Text("\(entry.minutes) min · \(entry.intensity.label)")
                                .font(.caption).foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if fp.needsInWorkoutFuel {
                                Text("\(fp.carbsPerHour) g/hr")
                                    .font(.system(.body, design: .rounded).weight(.bold))
                                    .foregroundStyle(.primary)
                                Text("carbs during").font(.caption2).foregroundStyle(Theme.textDim)
                            } else {
                                Text("pre / post")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(Theme.textDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if plan.fuelTrainingDays && totalBurn > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    Text(FuelCard.budgetLine(burn: totalBurn,
                                             fluidOz: CalorieEngine.trainingFluidOunces(plan: plan, on: today)))
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(Theme.textDim)
                .padding(.top, 2)
            }
        }
        .sheet(item: $detail) { fp in
            NavigationStack {
                Form { FuelPlanBreakdown(plan: fp) }
                    .themedForm()
                    .navigationTitle("Fueling")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .themedRoot()
            .presentationDetents([.medium, .large])
        }
    }

    /// "+450 cal · +20 oz water added to today's budget for training"
    static func budgetLine(burn: Int, fluidOz: Int) -> String {
        var line = "+\(burn) cal"
        if fluidOz > 0 { line += " · +\(fluidOz) oz water" }
        return line + " added to today's budget for training"
    }
}

// MARK: - Day detail section

/// Fueling guidance inside any day's detail form — the same per-session
/// plans as the dashboard card, but for whatever date is open, so the
/// week ahead can be planned from the calendar.
struct DayFuelSection: View {
    let plan: Plan
    let date: Date
    @State private var detail: FuelingPlan?

    private var workouts: [WorkoutScheduleEntry] {
        plan.scheduledWorkouts(on: date).sorted { $0.minutes > $1.minutes }
    }
    private func fuel(for entry: WorkoutScheduleEntry) -> FuelingPlan {
        FuelingEngine.plan(category: entry.category, intensity: entry.intensity,
                           minutes: entry.minutes, bodyweightLbs: plan.currentWeight)
    }

    var body: some View {
        Section {
            ForEach(workouts, id: \.persistentModelID) { entry in
                let fp = fuel(for: entry)
                Button { detail = fp } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(entry.name).foregroundStyle(.primary)
                            Spacer()
                            Text("\(entry.minutes) min · \(entry.intensity.label)")
                                .font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Text(fp.headline)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            SectionHeader(icon: "bolt.fill", title: "Fueling", tint: Theme.foodTint)
        } footer: {
            if plan.fuelTrainingDays {
                let burn = CalorieEngine.trainingBurn(plan: plan, on: date)
                let oz = CalorieEngine.trainingFluidOunces(plan: plan, on: date)
                Text("This day's targets already include the training: \(FuelCard.budgetLine(burn: burn, fluidOz: oz)).")
            }
        }
        .sheet(item: $detail) { fp in
            NavigationStack {
                Form { FuelPlanBreakdown(plan: fp) }
                    .themedForm()
                    .navigationTitle("Fueling")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .themedRoot()
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Week outlook

/// The training week's nutrition at a glance — one row per day for the next
/// seven, showing what's scheduled and how it changes that day's eating:
/// carbs during long sessions, the calorie add-back, and extra fluids.
struct WeekFuelView: View {
    let plan: Plan
    @State private var detail: FuelingPlan?

    private var days: [Date] {
        let start = Calendar.current.startOfDay(for: Date())
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        Form {
            ForEach(days, id: \.self) { day in
                daySection(day)
            }
        }
        .themedForm()
        .navigationTitle("Week's Fuel")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { fp in
            NavigationStack {
                Form { FuelPlanBreakdown(plan: fp) }
                    .themedForm()
                    .navigationTitle("Fueling")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .themedRoot()
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func daySection(_ day: Date) -> some View {
        let entries = plan.scheduledWorkouts(on: day).sorted { $0.minutes > $1.minutes }
        let isToday = Calendar.current.isDateInToday(day)
        let title = (isToday ? "Today · " : "")
            + day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())

        Section {
            if entries.isEmpty {
                Text("Rest day — base budget, protein still the priority.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries, id: \.persistentModelID) { entry in
                    let fp = FuelingEngine.plan(category: entry.category,
                                                intensity: entry.intensity,
                                                minutes: entry.minutes,
                                                bodyweightLbs: plan.currentWeight)
                    Button { detail = fp } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).foregroundStyle(.primary)
                                Text("\(entry.minutes) min · \(entry.intensity.label) at \(entry.timeString)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if fp.needsInWorkoutFuel {
                                    Text("\(fp.carbsPerHour) g/hr")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                    Text("carbs during").font(.caption2).foregroundStyle(.secondary)
                                } else {
                                    Text("\(fp.recoveryProtein) g protein")
                                        .font(.subheadline.weight(.semibold).monospacedDigit())
                                    Text("after").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if plan.fuelTrainingDays {
                    let burn = CalorieEngine.trainingBurn(plan: plan, on: day)
                    let oz = CalorieEngine.trainingFluidOunces(plan: plan, on: day)
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        Text("+\(burn) cal" + (oz > 0 ? " · +\(oz) oz water" : "") + " on this day's budget")
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(title)
        }
    }
}

// MARK: - Shared breakdown

/// The full during / before / after fueling breakdown for one session —
/// reused by the dashboard card's detail sheet and the calculator.
struct FuelPlanBreakdown: View {
    let plan: FuelingPlan

    var body: some View {
        Section {
            Text(plan.headline).font(.callout)
        }

        if plan.needsInWorkoutFuel {
            Section("During") {
                row("Carbs", "\(plan.carbsPerHour) g/hr", detail: "≈\(plan.duringCarbs) g across the session")
                row("Fluid", "\(plan.fluidOzPerHour) oz/hr")
                if plan.sodiumMgPerHour > 0 {
                    row("Sodium", "\(plan.sodiumMgPerHour) mg/hr")
                }
            }
        }

        Section("Before") {
            if plan.preCarbs > 0 {
                row("Carbs", "\(plan.preCarbs) g", detail: "a light top-up in the hour or two before")
            } else {
                Text("No special pre-load needed — normal meals cover it.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }

        Section("After") {
            row("Carbs", "\(plan.recoveryCarbs) g", detail: "to refill what you burned")
            if plan.recoveryProtein > 0 {
                row("Protein", "\(plan.recoveryProtein) g", detail: "for muscle repair")
            }
        }

        Section {
            row("Estimated burn", "\(plan.burnCalories) cal")
        } footer: {
            Text("Guidance, not a prescription — dial it to how you feel. Numbers follow mainstream endurance nutrition (≈30–60 g carb/hr for 1–2.5 h, up to ~90 beyond that; 1 g/kg carb + ~0.3 g/kg protein to recover) and scale with your weight, the duration, and how hard the session is.")
        }
    }

    private func row(_ label: String, _ value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value)
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
        }
    }
}

// MARK: - On-demand calculator

/// "What should I eat for a workout?" without touching the schedule — pick a
/// type, intensity, and length and the plan updates live. Sized to the
/// current weight in the plan.
struct FuelCalculatorView: View {
    let plan: Plan

    @State private var category: WorkoutCategory = .cardio
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var minutes = 90

    private var fuelingPlan: FuelingPlan {
        FuelingEngine.plan(category: category, intensity: intensity,
                           minutes: minutes, bodyweightLbs: plan.currentWeight)
    }

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $category) {
                    ForEach(WorkoutCategory.allCases) { c in
                        Label(c.label, systemImage: c.icon).tag(c)
                    }
                }
                Picker("Intensity", selection: $intensity) {
                    ForEach(WorkoutIntensity.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(intensity.cue).font(.caption).foregroundStyle(.secondary)
                Stepper("Duration: \(minutes) min", value: $minutes, in: 15...360, step: 15)
            } header: {
                Text("Workout")
            } footer: {
                Text("Sized to your current weight (\(Int(plan.currentWeight)) lb). Carbs mid-workout mainly matter for cardio and sports longer than an hour; strength and short sessions are all about before and after.")
            }

            FuelPlanBreakdown(plan: fuelingPlan)
        }
        .themedForm()
        .navigationTitle("Fuel Calculator")
        .navigationBarTitleDisplayMode(.inline)
    }
}
