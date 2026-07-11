import SwiftUI
import SwiftData
import PhotosUI

struct DayDetailView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var appLock: AppLockManager
    var plan: Plan
    var profile: UserProfile
    var date: Date
    @State private var day: DayLog

    // Photo capture/import UI state
    @State private var showCamera = false
    @State private var selectedItems: [PhotosPickerItem] = []

    @FocusState private var fieldFocused: Bool

    init(plan: Plan, profile: UserProfile, date: Date) {
        self.plan = plan
        self.profile = profile
        self.date = date.startOfDay()
        let d = ensureDay(plan: plan, date: date)
        _day = State(initialValue: d)
    }

    private var targets: DailyTargets { CalorieEngine.targets(profile: profile, plan: plan) }
    private var workoutScheduled: Bool { plan.isWorkoutScheduled(on: date) }

    private func statusDot(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? Theme.accent : Theme.danger)
    }

    var body: some View {
        Form {
            // ===== Live status vs today's targets
            Section("Status") {
                HStack {
                    statusDot(day.totalCalories > 0 && day.totalCalories <= targets.calories)
                    Text("Calories within budget")
                    Spacer()
                    Text("\(day.totalCalories) / \(targets.calories)").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(day.totalProtein >= targets.proteinGrams)
                    Text("Protein ≥ \(targets.proteinGrams) g")
                    Spacer()
                    Text("\(day.totalProtein) g").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(day.waterOunces >= targets.waterOunces)
                    Text("Water ≥ \(targets.waterOunces) oz")
                    Spacer()
                    Text("\(day.waterOunces) oz").foregroundStyle(.secondary)
                }
                if workoutScheduled {
                    HStack {
                        statusDot(!day.workouts.isEmpty)
                        Text("Scheduled workout")
                        Spacer()
                        Text("\(day.workoutMinutes) min").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    statusDot(!day.photos.isEmpty)
                    Text("Progress photo attached")
                    Spacer()
                    Text("\(day.photos.count)x").foregroundStyle(.secondary)
                }
            }

            // ===== Food
            Section("Food") {
                ForEach(day.foods) { f in
                    HStack(spacing: 8) {
                        if let d = FoodDensity(rawValue: f.density ?? "") {
                            Circle().fill(d.color).frame(width: 9, height: 9)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.name).lineLimit(1)
                            Text(foodSubtitle(f))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(f.calories) cal").foregroundStyle(.secondary)
                    }
                }
                .onDelete { idx in
                    idx.map { day.foods[$0] }.forEach { context.delete($0) }
                }
                NavigationLink {
                    FoodSearchView(day: day)
                } label: {
                    Label("Add Food", systemImage: "magnifyingglass")
                }
                HStack {
                    Text("Quick add")
                    Spacer()
                    TextField("cal", value: $day.caloriesEaten, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .focused($fieldFocused)
                    Text("cal +").foregroundStyle(.secondary)
                    TextField("g", value: $day.proteinGrams, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                        .focused($fieldFocused)
                    Text("g protein").foregroundStyle(.secondary)
                }
            }

            // ===== Hydration
            Section("Hydration") {
                let step = max(1, plan.waterStepOunces)
                Stepper(value: $day.waterOunces, in: 0...10000, step: step) {
                    HStack {
                        Text("Water")
                        Spacer()
                        Text("\(day.waterOunces) oz (+\(step) oz)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // ===== Weight
            Section("Weight") {
                TextField(
                    "Weight (lb)",
                    value: Binding(
                        get: { day.weight ?? 0 },
                        set: { newVal in day.weight = newVal == 0 ? nil : newVal }
                    ),
                    format: .number
                )
                .keyboardType(.decimalPad)
                .focused($fieldFocused)
            }

            // ===== Alcohol
            Section {
                Stepper(value: $day.standardDrinks, in: 0...30, step: 0.5) {
                    HStack {
                        Text("Standard drinks")
                        Spacer()
                        Text(day.standardDrinks.formatted()).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Alcohol")
            } footer: {
                Text("1 standard drink = 12 oz beer, 5 oz wine, or 1.5 oz spirits (~98 cal, counted toward your budget).")
            }

            // ===== Supplements (only those due today)
            if plan.supplements.contains(where: { $0.isDue(on: date) }) {
                Section("Supplements") {
                    ForEach(plan.supplements.filter { $0.isDue(on: date) }) { s in
                        Button {
                            toggleSupplement(s.name)
                        } label: {
                            HStack {
                                Image(systemName: day.takenSupplements.contains(s.name)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(day.takenSupplements.contains(s.name)
                                                     ? Theme.accent : .secondary)
                                Text(s.name).foregroundStyle(.primary)
                                Spacer()
                                Text(s.timeString).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            // ===== Workouts
            Section("Workouts") {
                if workoutScheduled && day.workouts.isEmpty {
                    let planned = plan.scheduledWorkouts(on: date)
                    ForEach(planned) { entry in
                        HStack {
                            Image(systemName: "calendar.badge.clock").foregroundStyle(Theme.warn)
                            Text("Planned: \(entry.name), \(entry.minutes) min at \(entry.timeString)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if day.workouts.isEmpty && !workoutScheduled {
                    Text("Rest day — nothing scheduled.").foregroundStyle(.secondary)
                }
                ForEach(day.workouts) { w in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(w.name)
                            Text("\(w.minutes) min\(w.outdoor ? " · outdoors" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if w.outdoor { Image(systemName: "sun.max.fill").foregroundStyle(.secondary) }
                    }
                }
                .onDelete { idx in
                    idx.map { day.workouts[$0] }.forEach { context.delete($0) }
                }
                NavigationLink("Log Workout") {
                    WorkoutFormView(day: day, plan: plan)
                }
            }

            // ===== Photos (Face ID gated)
            Section("Progress Photos") {
                if !day.photos.isEmpty && !appLock.photosUnlocked {
                    PhotoLockGate(compact: true)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(day.photos) { p in
                                let url = photosDir().appendingPathComponent(p.filename)
                                if let img = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 120)
                                        .clipped()
                                        .cornerRadius(6)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                HStack {
                    Button("Take Photo") { showCamera = true }
                    PhotosPicker("Pick from Library",
                                 selection: $selectedItems,
                                 maxSelectionCount: 5,
                                 matching: .images)
                }
            }
        }
        .themedForm()
        .navigationTitle(Text(date, style: .date))
        .onChange(of: selectedItems) { _ in Task { await handlePicked() } }
        .sheet(isPresented: $showCamera) { CameraCaptureView { saveImage($0) } }
        .onDisappear {
            try? context.save()
            let day = self.day
            Task { await HealthKitService.shared.syncDay(day) }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
        }
    }

    private func foodSubtitle(_ f: FoodLog) -> String {
        var parts: [String] = []
        if let g = f.grams { parts.append("\(Int(g)) g") }
        if f.proteinGrams > 0 { parts.append("\(f.proteinGrams) g protein") }
        if f.source == "barcode" { parts.append("scanned") }
        return parts.joined(separator: " · ")
    }

    private func toggleSupplement(_ name: String) {
        if let i = day.takenSupplements.firstIndex(of: name) {
            day.takenSupplements.remove(at: i)
        } else {
            day.takenSupplements.append(name)
        }
    }

    // MARK: - Photos import/save
    func handlePicked() async {
        for item in selectedItems {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                saveImage(image)
            }
        }
        selectedItems.removeAll()
    }

    func saveImage(_ image: UIImage) {
        let filename = "photo_\(Int(Date().timeIntervalSince1970)).jpg"
        let url = photosDir().appendingPathComponent(filename)
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: url)
        }
        let entry = PhotoEntry(filename: filename)
        day.photos.append(entry)
    }
}

// MARK: - Camera wrapper (keeps photos local; no auto-save to Photos app)
struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let img = info[.originalImage] as? UIImage { onCapture(img) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}
