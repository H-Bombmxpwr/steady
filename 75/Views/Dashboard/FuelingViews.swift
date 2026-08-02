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
                    Text("+\(totalBurn) cal added to today's budget for training")
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
