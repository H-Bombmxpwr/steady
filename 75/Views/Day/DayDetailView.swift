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

    // Gemini end-of-day review
    @State private var showDaySummary = false

    // "What should I eat?" — meal ideas that fit the remaining budget
    @State private var showMealIdeas = false

    // Weight entry, text-backed so decimals type naturally
    @State private var weightText: String

    // Lab-aware coaching (opt-in; Settings → Blood Work)
    @AppStorage("labs.enabled") private var labsEnabled = false

    @FocusState private var fieldFocused: Bool

    init(plan: Plan, profile: UserProfile, date: Date) {
        self.plan = plan
        self.profile = profile
        self.date = date.startOfDay()
        let d = ensureDay(plan: plan, date: date)
        _day = State(initialValue: d)
        _weightText = State(initialValue: d.weight.map {
            $0.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        } ?? "")
    }

    /// Digits and one "." only; at most 3 digits before the point (nobody
    /// weighs 1,000 lb) and 1 after (scales read tenths).
    static func sanitizeWeight(_ raw: String) -> String {
        var intPart = ""
        var fracPart = ""
        var seenDot = false
        for ch in raw.replacingOccurrences(of: ",", with: ".") {
            if ch == "." {
                seenDot = true
            } else if ch.isNumber {
                if seenDot {
                    if fracPart.count < 1 { fracPart.append(ch) }
                } else {
                    if intPart.count < 3 { intPart.append(ch) }
                }
            }
        }
        return intPart + (seenDot ? "." : "") + fracPart
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
            Section {
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
            } header: {
                SectionHeader(icon: "checkmark.seal.fill", title: "Status")
            }

            // ===== Food — add at the top, meals grouped below
            Section {
                NavigationLink {
                    FoodSearchView(day: day)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add Food").font(.headline)
                            Text("Logging \(Meal.suggested().label.lowercased()) right now")
                                .font(.caption)
                                .opacity(0.9)
                        }
                        Spacer()
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.gradient)
                )
                // One row per meal — tap in to see and manage what you ate;
                // swipe to delete the whole meal.
                ForEach(mealGroups, id: \.meal) { group in
                    NavigationLink {
                        MealDetailView(day: day, meal: group.meal,
                                       label: group.label, icon: group.icon)
                    } label: {
                        HStack(spacing: 12) {
                            SectionIcon(systemImage: group.icon, size: 30,
                                        tint: group.meal?.color ?? Theme.foodTint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.label)
                                Text("\(group.foods.count) item\(group.foods.count == 1 ? "" : "s") · \(group.foods.reduce(0) { $0 + $1.proteinGrams }) g protein")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(group.foods.reduce(0) { $0 + $1.calories }) cal")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { mealGroups[$0].meal }.forEach { day.removeMeal($0) }
                }
                NavigationLink {
                    DayNutritionView(day: day, targets: targets,
                                     goals: .adjusted(for: labsEnabled ? plan.latestLabs : nil))
                } label: {
                    Label("Nutrition Report", systemImage: "chart.bar.doc.horizontal")
                }
                Button { showMealIdeas = true } label: {
                    Label("What Should I Eat?", systemImage: "wand.and.stars")
                }
                if !day.foods.isEmpty {
                    Button { showDaySummary = true } label: {
                        Label("Summarize My Day", systemImage: "sparkles")
                    }
                }
                HStack {
                    Text("Quick add")
                    Spacer()
                    TextField("cal", value: Binding<Int?>(
                        get: { day.caloriesEaten == 0 ? nil : day.caloriesEaten },
                        set: { day.caloriesEaten = $0 ?? 0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                        .focused($fieldFocused)
                    Text("cal +").foregroundStyle(.secondary)
                    TextField("g", value: Binding<Int?>(
                        get: { day.proteinGrams == 0 ? nil : day.proteinGrams },
                        set: { day.proteinGrams = $0 ?? 0 }
                    ), format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 50)
                        .focused($fieldFocused)
                    Text("g protein").foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader(icon: "fork.knife", title: "Food", tint: Theme.foodTint)
            }

            // ===== Hydration
            Section {
                let step = max(1, plan.waterStepOunces)
                Stepper(value: $day.waterOunces, in: 0...10000, step: step) {
                    HStack {
                        Text("Water")
                        Spacer()
                        Text("\(day.waterOunces) oz (+\(step) oz)")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SectionHeader(icon: "drop.fill", title: "Hydration", tint: Theme.waterTint)
            }

            // ===== Weight
            Section {
                // Text-backed on purpose: the value+format TextField mangles
                // live decimal typing ("224.9" became 2249). This keeps every
                // keystroke sane: digits, one decimal point, max 999.9.
                TextField("Weight (lb)", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($fieldFocused)
                    .onChange(of: weightText) { newValue in
                        let cleaned = Self.sanitizeWeight(newValue)
                        if cleaned != newValue {
                            weightText = cleaned
                            return
                        }
                        day.weight = Double(cleaned)
                    }
            } header: {
                SectionHeader(icon: "scalemass.fill", title: "Weight", tint: Theme.weightTint)
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
                SectionHeader(icon: "wineglass.fill", title: "Alcohol", tint: Theme.alcoholTint)
            } footer: {
                Text("1 standard drink = 12 oz beer, 5 oz wine, or 1.5 oz spirits (~98 cal, counted toward your budget).")
            }

            // ===== Supplements (only those due today)
            if plan.supplements.contains(where: { $0.isDue(on: date) }) {
                Section {
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
                } header: {
                    SectionHeader(icon: "pills.fill", title: "Supplements", tint: Theme.supplementTint)
                }
            }

            // ===== Workouts
            Section {
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
            } header: {
                SectionHeader(icon: "figure.strengthtraining.traditional", title: "Workouts", tint: Theme.workoutTint)
            }

            // ===== Photos (Face ID gated)
            Section {
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
                    // The tab-level bottom content margin is for vertical
                    // scrollers; don't let it stretch this photo strip.
                    .contentMargins(.bottom, 0, for: .scrollContent)
                    // Own horizontal drags so swiping photos doesn't flip tabs.
                    .claimsHorizontalDrag()
                }
                HStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                            Text("Camera")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    PhotosPicker(selection: $selectedItems,
                                 maxSelectionCount: 5,
                                 matching: .images) {
                        HStack(spacing: 6) {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Library")
                        }
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.bordered)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                .listRowBackground(Color.clear)
            } header: {
                SectionHeader(icon: "camera.fill", title: "Progress Photos", tint: Theme.photoTint)
            }
        }
        .themedForm()
        .navigationTitle(Text(date, style: .date))
        .sheet(isPresented: $showMealIdeas) {
            MealIdeasView(day: day, targets: targets,
                          labs: labsEnabled ? AIFoodEstimator.LabSnapshot(labs: plan.latestLabs) : nil)
                .themedRoot()
        }
        .sheet(isPresented: $showDaySummary) {
            let labs = labsEnabled ? AIFoodEstimator.LabSnapshot(labs: plan.latestLabs) : nil
            CoachReviewSheet(title: "Day Summary") { [day, targets] in
                try await AIFoodEstimator.reviewDay(day: day, targets: targets, labs: labs)
            }
            .themedRoot()
        }
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

    /// Meals with at least one food, in day order; pre-meals-era logs land
    /// in a trailing "Other" group.
    private var mealGroups: [(meal: Meal?, label: String, icon: String, foods: [FoodLog])] {
        var groups: [(Meal?, String, String, [FoodLog])] = Meal.allCases.map {
            ($0, $0.label, $0.icon, day.foods(for: $0))
        }
        groups.append((nil, "Other", "fork.knife", day.foods(for: nil)))
        return groups.filter { !$0.3.isEmpty }.map {
            (meal: $0.0, label: $0.1, icon: $0.2, foods: $0.3)
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
