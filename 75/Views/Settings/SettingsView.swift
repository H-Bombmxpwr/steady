import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var plan: Plan
    @Bindable var profile: UserProfile

    // Share sheet for the JSON backup
    @State private var exportURL: URL?
    @State private var presentShare = false
    @State private var showEraseConfirm = false

    @FocusState private var fieldFocused: Bool

    private let paces: [Double] = [0.5, 1.0, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            Form {
                // --- Goal
                Section("Goal") {
                    HStack { Text("Started"); Spacer(); Text(plan.startDate, style: .date).foregroundStyle(.secondary) }
                    HStack {
                        Text("Goal weight")
                        Spacer()
                        TextField("lb", value: $plan.goalWeight, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($fieldFocused)
                        Text("lb").foregroundStyle(.secondary)
                    }
                    Picker("Pace", selection: $plan.paceLbsPerWeek) {
                        ForEach(paces, id: \.self) { p in
                            Text(String(format: "%.1f lb / week", p)).tag(p)
                        }
                    }
                }

                // --- Daily targets
                Section("Daily Targets") {
                    let targets = CalorieEngine.targets(profile: profile, plan: plan)
                    HStack {
                        Text("Calorie budget")
                        Spacer()
                        Text("\(targets.calories) cal").foregroundStyle(.secondary)
                    }
                    Toggle("Override budget", isOn: Binding(
                        get: { plan.calorieBudgetOverride != nil },
                        set: { on in
                            plan.calorieBudgetOverride = on ? targets.calories : nil
                        }
                    ))
                    if plan.calorieBudgetOverride != nil {
                        HStack {
                            Text("Custom budget")
                            Spacer()
                            TextField("cal", value: Binding(
                                get: { plan.calorieBudgetOverride ?? 0 },
                                set: { plan.calorieBudgetOverride = max(800, $0) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($fieldFocused)
                        }
                    }
                    Stepper("Protein target: \(plan.proteinTargetGrams) g",
                            value: $plan.proteinTargetGrams, in: 40...400, step: 5)
                    Stepper("Water goal: \(plan.waterGoalOunces) oz",
                            value: $plan.waterGoalOunces, in: 32...256, step: 8)
                    Stepper(value: Binding(
                        get: { max(1, plan.waterStepOunces) },
                        set: { plan.waterStepOunces = max(1, min($0, 256)) }
                    ), in: 1...256) {
                        HStack {
                            Text("Water log step")
                            Spacer()
                            Text("\(plan.waterStepOunces) oz").foregroundStyle(.secondary)
                        }
                    }
                    Text("Set the step to your bottle size (e.g., 48 oz).")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                // --- Profile
                Section("Profile") {
                    DatePicker("Birth date", selection: $profile.birthDate, in: ...Date(), displayedComponents: .date)
                    Picker("Sex", selection: Binding(get: { profile.sex }, set: { profile.sex = $0 })) {
                        ForEach(BiologicalSex.allCases) { Text($0.label).tag($0) }
                    }
                    HStack {
                        Text("Height")
                        Spacer()
                        Picker("Feet", selection: Binding(
                            get: { Int(profile.heightInches) / 12 },
                            set: { profile.heightInches = Double($0 * 12 + Int(profile.heightInches) % 12) }
                        )) {
                            ForEach(3...7, id: \.self) { Text("\($0) ft") }
                        }
                        .pickerStyle(.menu)
                        Picker("Inches", selection: Binding(
                            get: { Int(profile.heightInches) % 12 },
                            set: { profile.heightInches = Double((Int(profile.heightInches) / 12) * 12 + $0) }
                        )) {
                            ForEach(0...11, id: \.self) { Text("\($0) in") }
                        }
                        .pickerStyle(.menu)
                    }
                    Picker("Activity", selection: Binding(get: { profile.activityLevel }, set: { profile.activityLevel = $0 })) {
                        ForEach(ActivityLevel.allCases) { Text($0.label).tag($0) }
                    }
                }

                // --- Security
                Section("Security") {
                    Label("Face ID is required at launch and resume", systemImage: "faceid")
                        .foregroundStyle(.secondary)
                }

                // --- Backup / Export (JSON)
                Section("Backup / Export") {
                    Button("Export Backup (JSON)…") {
                        do {
                            exportURL = try BackupService.exportJSON(profile: profile, plan: plan)
                            presentShare = (exportURL != nil)
                        } catch {
                            exportURL = nil
                        }
                    }
                    .sheet(isPresented: $presentShare) {
                        if let url = exportURL {
                            ActivityView(activityItems: [url])
                        }
                    }
                }

                // --- Reset
                Section("Reset") {
                    Button(role: .destructive) { showEraseConfirm = true } label: {
                        Text("Erase All Data")
                    }
                    .confirmationDialog("Erase all local data? This cannot be undone.",
                                        isPresented: $showEraseConfirm,
                                        titleVisibility: .visible) {
                        Button("Erase All", role: .destructive) { eraseAll() }
                        Button("Cancel", role: .cancel) {}
                    }
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
    }

    private func eraseAll() {
        if let days = try? context.fetch(FetchDescriptor<DayLog>()) {
            days.forEach { context.delete($0) }
        }
        if let ps = try? context.fetch(FetchDescriptor<WorkoutPreset>()) {
            ps.forEach { context.delete($0) }
        }
        if let plans = try? context.fetch(FetchDescriptor<Plan>()) {
            plans.forEach { context.delete($0) }
        }
        if let profiles = try? context.fetch(FetchDescriptor<UserProfile>()) {
            profiles.forEach { context.delete($0) }
        }
        try? context.save()

        // Delete photos directory
        try? FileManager.default.removeItem(at: photosDir())
    }
}

// Simple share wrapper (unchanged)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
