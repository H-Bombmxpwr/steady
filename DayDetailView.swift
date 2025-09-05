import SwiftUI
import SwiftData
import PhotosUI

struct DayDetailView: View {
    @Environment(\.modelContext) private var context
    var state: ChallengeState
    var date: Date
    @State private var day: DayEntry

    // Photo capture/import UI state
    @State private var showCamera = false
    @State private var selectedItems: [PhotosPickerItem] = []

    // Keyboard focus for weight field
    @FocusState private var weightFocused: Bool

    init(state: ChallengeState, date: Date) {
        self.state = state
        self.date = date.startOfDay()
        let d = ensureDay(state: state, date: date)
        _day = State(initialValue: d)
    }

    // MARK: - Threshold helpers + status dot
    private func statusDot(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
            .foregroundStyle(ok ? Color.green : Color.red)
    }
    private func minutesOK(_ m: Int) -> Bool { m >= 45 }
    private func waterOK(_ oz: Int) -> Bool { oz >= 128 }
    private func pagesOK(_ p: Int) -> Bool { p >= 10 }

    var body: some View {
        Form {
            // ===== Live status indicators (turn green/red as values change)
            Section("Today’s Status") {
                HStack {
                    statusDot(minutesOK(day.workout1Minutes))
                    Text("Workout 1 ≥ 45m")
                    Spacer()
                    Text("\(day.workout1Minutes)m").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(minutesOK(day.workout2Minutes))
                    Text("Workout 2 ≥ 45m")
                    Spacer()
                    Text("\(day.workout2Minutes)m").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(day.workout1Outdoor || day.workout2Outdoor)
                    Text("At least 1 outdoor")
                    Spacer()
                    Image(systemName: (day.workout1Outdoor || day.workout2Outdoor) ? "sun.max.fill" : "cloud")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(waterOK(day.waterOunces))
                    Text("Water ≥ 128 oz")
                    Spacer()
                    Text("\(day.waterOunces) oz").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(pagesOK(day.pagesRead))
                    Text("Reading ≥ 10 pages")
                    Spacer()
                    Text("\(day.pagesRead)").foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(day.dietCompliant)
                    Text("Diet compliant")
                    Spacer()
                    Image(systemName: day.dietCompliant ? "fork.knife.circle.fill" : "fork.knife")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    statusDot(!day.photos.isEmpty)
                    Text("Progress photo attached")
                    Spacer()
                    Text("\(day.photos.count)x").foregroundStyle(.secondary)
                }
            }

            // ===== Workouts
            Section("Workouts") {
                Stepper(value: $day.workout1Minutes, in: 0...300, step: 5) {
                    Text("Workout 1: \(day.workout1Minutes) min")
                }
                Toggle("Workout 1 was outdoors", isOn: $day.workout1Outdoor)
                Stepper(value: $day.workout2Minutes, in: 0...300, step: 5) {
                    Text("Workout 2: \(day.workout2Minutes) min")
                }
                Toggle("Workout 2 was outdoors", isOn: $day.workout2Outdoor)

                NavigationLink("Add from Preset") {
                    WorkoutFormView(day: day, state: state)
                }
            }

            // ===== Hydration & Reading (uses configurable bottle step)
            Section("Hydration & Reading") {
                let step = max(1, (state.waterStepOunces)) // requires Models change; default set in model
                Stepper(value: $day.waterOunces, in: 0...10000, step: step) {
                    HStack {
                        Text("Water")
                        Spacer()
                        Text("\(day.waterOunces) oz (+\(step) oz)")
                            .foregroundStyle(.secondary)
                    }
                }
                Stepper(value: $day.pagesRead, in: 0...500, step: 1) {
                    HStack {
                        Text("Pages read")
                        Spacer()
                        Text("\(day.pagesRead)").foregroundStyle(.secondary)
                    }
                }
            }

            // ===== Weight (optional)
            Section("Weight (optional)") {
                TextField(
                    "Weight (lb)",
                    value: Binding(
                        get: { day.weight ?? 0 },
                        set: { newVal in day.weight = newVal == 0 ? nil : newVal }
                    ),
                    format: .number
                )
                .keyboardType(.decimalPad)
                .focused($weightFocused)
            }

            // ===== Diet & Alcohol
            Section("Diet & Alcohol") {
                Toggle("Diet compliant (\(state.dietName))", isOn: $day.dietCompliant)

                Button(action: toggleAlcohol) {
                    Label(
                        day.alcoholUsed ? "Alcohol marked for this day" : "Mark alcohol used today",
                        systemImage: day.alcoholUsed ? "checkmark.circle.fill" : "wineglass"
                    )
                }
                .disabled(!canUseAlcoholToday())
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
            // Keyboard toolbar for weight field
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { weightFocused = false }
            }
        }
    }

    // MARK: - Alcohol logic (1 per month)
    func toggleAlcohol() {
        if day.alcoholUsed { day.alcoholUsed = false; return }
        if canUseAlcoholToday() { day.alcoholUsed = true }
    }
    func canUseAlcoholToday() -> Bool {
        guard state.allowAlcoholMonthly else { return false }
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: day.date)
        let used = state.days.contains { d in
            let dc = cal.dateComponents([.year, .month], from: d.date)
            return dc.year == comps.year && dc.month == comps.month && d.alcoholUsed
        }
        return !used || day.alcoholUsed
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
