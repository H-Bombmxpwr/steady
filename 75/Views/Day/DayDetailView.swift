import SwiftUI
import SwiftData
import PhotosUI

struct DayDetailView: View {
    @Environment(\.modelContext) private var context
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

    private func statusDot(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? Color.green : Color.red)
    }

    var body: some View {
        Form {
            // ===== Live status vs today's targets
            Section("Status") {
                HStack {
                    statusDot(day.caloriesEaten > 0 && day.caloriesEaten <= targets.calories)
                    Text("Calories within budget")
                    Spacer()
                    Text("\(day.caloriesEaten) / \(targets.calories)").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(day.proteinGrams >= targets.proteinGrams)
                    Text("Protein ≥ \(targets.proteinGrams) g")
                    Spacer()
                    Text("\(day.proteinGrams) g").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(day.waterOunces >= targets.waterOunces)
                    Text("Water ≥ \(targets.waterOunces) oz")
                    Spacer()
                    Text("\(day.waterOunces) oz").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(!day.workouts.isEmpty)
                    Text("Workout logged")
                    Spacer()
                    Text("\(day.workoutMinutes) min").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(!day.photos.isEmpty)
                    Text("Progress photo attached")
                    Spacer()
                    Text("\(day.photos.count)x").foregroundStyle(.secondary)
                }
            }

            // ===== Nutrition (manual quick-log until the food database lands)
            Section("Nutrition") {
                HStack {
                    Text("Calories eaten")
                    Spacer()
                    TextField("0", value: $day.caloriesEaten, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .focused($fieldFocused)
                    Text("cal").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Protein")
                    Spacer()
                    TextField("0", value: $day.proteinGrams, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .focused($fieldFocused)
                    Text("g").foregroundStyle(.secondary)
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
            Section("Alcohol") {
                Stepper(value: $day.alcoholDrinks, in: 0...50) {
                    HStack {
                        Text("Drinks")
                        Spacer()
                        Text("\(day.alcoholDrinks)").foregroundStyle(.secondary)
                    }
                }
            }

            // ===== Workouts
            Section("Workouts") {
                if day.workouts.isEmpty {
                    Text("No workouts logged.").foregroundStyle(.secondary)
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
                NavigationLink("Add Workout") {
                    WorkoutFormView(day: day, plan: plan)
                }
            }

            // ===== Photos
            Section("Progress Photos") {
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
                HStack {
                    Button("Take Photo") { showCamera = true }
                    PhotosPicker("Pick from Library",
                                 selection: $selectedItems,
                                 maxSelectionCount: 5,
                                 matching: .images)
                }
            }
        }
        .navigationTitle(Text(date, style: .date))
        .onChange(of: selectedItems) { _ in Task { await handlePicked() } }
        .sheet(isPresented: $showCamera) { CameraCaptureView { saveImage($0) } }
        .onDisappear { try? context.save() }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
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
