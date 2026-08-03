import SwiftUI
import UIKit
import Speech
import AVFoundation

/// "Describe your meal" — type or dictate plain text ("two eggs, sourdough
/// toast with butter, and an orange juice") and Gemini breaks it into items
/// with calories, protein, and a calorie-density color. Review, prune, log.
/// Pass a `photo` and the same flow reads the plate instead — the text field
/// becomes optional notes for what the photo can't show.
struct DescribeMealView: View {
    @Environment(\.dismiss) private var dismiss
    var mealLabel: String = "Today"
    var photo: UIImage? = nil
    let onLog: ([FoodLog]) -> Void

    @StateObject private var speech = SpeechTranscriber()
    @State private var text = ""
    @State private var dictationBase = ""
    @State private var building = false
    @State private var buildError: String?
    @State private var items: [AIFoodEstimator.MealItem] = []
    /// Per-item portion multiplier (item id → ×). Items stay at the AI's
    /// assumed portion as the baseline; display, totals, and logging all use
    /// the scaled values, so a half-portion is two taps, not a rebuild.
    @State private var multipliers: [UUID: Double] = [:]
    @State private var assumed = ""
    /// Whether the estimate came from a live web lookup (nil until built).
    @State private var grounded: Bool?
    @State private var editingItem: AIFoodEstimator.MealItem?

    private func portion(of item: AIFoodEstimator.MealItem) -> Double {
        multipliers[item.id] ?? 1
    }

    private var scaledItems: [AIFoodEstimator.MealItem] {
        items.map { $0.scaled(by: portion(of: $0)) }
    }

    private var totalCalories: Int { scaledItems.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Int { scaledItems.reduce(0) { $0 + $1.proteinGrams } }

    var body: some View {
        NavigationStack {
            Form {
                if let photo {
                    Section {
                        HStack {
                            Spacer()
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: 240, maxHeight: 160)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                }
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: photo == nil ? 100 : 60)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(photo == nil
                                     ? "What did you eat? Name the restaurant if you ate out."
                                     : "Anything the photo can't show? Brand, cooking oil, what's in the cup…")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .allowsHitTesting(false)
                            }
                        }
                    Button {
                        if speech.isRecording {
                            speech.stop()
                        } else {
                            dictationBase = text.trimmingCharacters(in: .whitespacesAndNewlines)
                            speech.start()
                        }
                    } label: {
                        HStack {
                            Image(systemName: speech.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                                .font(.title2)
                                .foregroundStyle(speech.isRecording ? .red : Theme.accent)
                                .symbolEffect(.pulse, isActive: speech.isRecording)
                            Text(speech.isRecording ? "Listening — tap to stop" : "Dictate it instead")
                                .foregroundStyle(speech.isRecording ? .red : .primary)
                        }
                    }
                    if let msg = speech.errorMessage {
                        Text(msg).font(.caption).foregroundStyle(.red)
                    }
                } footer: {
                    Text(photo == nil
                         ? "e.g. “two scrambled eggs, sourdough toast with butter, and an orange juice” — or “Chipotle chicken bowl with white rice, black beans, and guac”. Named restaurants and brands are looked up against their published nutrition."
                         : "Notes are optional — the photo is read on its own, but a brand name or a hidden ingredient sharpens the numbers.")
                }

                Section {
                    Button {
                        Task { await build() }
                    } label: {
                        HStack {
                            Label(photo == nil
                                  ? (items.isEmpty ? "Build My Meal" : "Rebuild")
                                  : (items.isEmpty ? "Read the Photo" : "Re-read with Notes"),
                                  systemImage: "sparkles")
                            if building { Spacer(); ProgressView() }
                        }
                    }
                    .disabled((photo == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) || building)
                    if let err = buildError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }

                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            let scaled = item.scaled(by: portion(of: item))
                            VStack(spacing: 6) {
                                Button { editingItem = scaled } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Circle()
                                            .fill(FoodDensity(rawValue: item.density ?? "")?.color ?? .secondary)
                                            .frame(width: 9, height: 9)
                                            .padding(.top, 5)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name).lineLimit(2).foregroundStyle(.primary)
                                            if let a = item.assumed, !a.isEmpty {
                                                Text(a)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("\(scaled.calories) cal").foregroundStyle(.primary)
                                            Text("\(scaled.proteinGrams) g protein")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Stepper(value: Binding(get: { portion(of: item) },
                                                       set: { multipliers[item.id] = $0 }),
                                        in: 0.25...5, step: 0.25) {
                                    HStack(spacing: 6) {
                                        Text("\(portion(of: item).formatted())× portion")
                                        if let g = scaled.grams {
                                            Text("\(Int(g)) g")
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { idx in items.remove(atOffsets: idx) }
                        Button {
                            Haptics.success()
                            onLog(scaledItems.map { FoodLog(name: $0.name,
                                                      calories: $0.calories,
                                                      proteinGrams: $0.proteinGrams,
                                                      grams: $0.grams,
                                                      source: "ai",
                                                      density: $0.density,
                                                      facts: $0.facts) })
                            dismiss()
                        } label: {
                            Text("Log \(items.count) Item\(items.count == 1 ? "" : "s") to \(mealLabel) — \(totalCalories) cal · \(totalProtein)g protein")
                                .bold()
                        }
                    } header: {
                        HStack {
                            Text("Your Meal")
                            Spacer()
                            if let grounded {
                                GroundingBadge(grounded: grounded)
                            }
                        }
                    } footer: {
                        Text(assumed.isEmpty
                             ? "Step a portion up or down and every stat follows · tap an item to edit its numbers · swipe to remove it."
                             : "Assumed: \(assumed)\nStep a portion up or down and every stat follows · tap an item to edit its numbers · swipe to remove it.")
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                MealItemEditSheet(item: item) { edited in
                    if let i = items.firstIndex(where: { $0.id == edited.id }) {
                        // Hand-corrected numbers become the new 1× baseline.
                        items[i] = edited
                        multipliers[edited.id] = 1
                    }
                }
                .themedRoot()
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle(photo == nil ? "Describe Your Meal" : "Photo of Food")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if photo != nil && items.isEmpty && !building { await build() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        speech.stop()
                        dismiss()
                    }
                }
            }
            .onChange(of: speech.transcript) { t in
                guard speech.isRecording else { return }
                text = dictationBase.isEmpty ? t : dictationBase + " " + t
            }
            .onDisappear { speech.stop() }
        }
    }

    private func build() async {
        speech.stop()
        building = true
        buildError = nil
        defer { building = false }
        do {
            let breakdown: AIFoodEstimator.MealBreakdown
            if let photo {
                breakdown = try await AIFoodEstimator.mealBreakdown(photo: photo, notes: text)
            } else {
                breakdown = try await AIFoodEstimator.mealBreakdown(description: text)
            }
            items = breakdown.items
            multipliers = [:]
            assumed = breakdown.assumed
            grounded = breakdown.grounded
        } catch {
            buildError = error.localizedDescription
        }
    }
}

// MARK: - Per-item correction

/// Every number the AI guessed, editable — fix anything that looks off
/// before logging. Density re-buckets itself from the edited values.
struct MealItemEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (AIFoodEstimator.MealItem) -> Void

    @State private var item: AIFoodEstimator.MealItem
    @State private var grams: Double

    init(item: AIFoodEstimator.MealItem, onSave: @escaping (AIFoodEstimator.MealItem) -> Void) {
        self.onSave = onSave
        _item = State(initialValue: item)
        _grams = State(initialValue: item.grams ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $item.name)
                    if let a = item.assumed, !a.isEmpty {
                        Text("Assumed: \(a)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Portion & Macros") {
                    numberRow("Portion (g)", value: $grams)
                    intRow("Calories", value: $item.calories)
                    intRow("Protein (g)", value: $item.proteinGrams)
                    numberRow("Carbs (g)", value: $item.facts.carbsGrams)
                    numberRow("Fat (g)", value: $item.facts.fatGrams)
                }
                Section("Detail") {
                    numberRow("Saturated Fat (g)", value: $item.facts.saturatedFatGrams)
                    numberRow("Trans Fat (g)", value: $item.facts.transFatGrams)
                    numberRow("Cholesterol (mg)", value: $item.facts.cholesterolMg)
                    numberRow("Sodium (mg)", value: $item.facts.sodiumMg)
                    numberRow("Fiber (g)", value: $item.facts.fiberGrams)
                    numberRow("Total Sugar (g)", value: $item.facts.sugarGrams)
                    numberRow("Added Sugar (g)", value: $item.facts.addedSugarGrams)
                    numberRow("Potassium (mg)", value: $item.facts.potassiumMg)
                    numberRow("Calcium (mg)", value: $item.facts.calciumMg)
                    numberRow("Iron (mg)", value: $item.facts.ironMg)
                }
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        item.grams = grams > 0 ? grams : nil
                        item.refreshDensity()
                        onSave(item)
                        dismiss()
                    }
                    .disabled(item.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func numberRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    private func intRow(_ label: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}

// MARK: - Live speech-to-text

/// On-device-capable live dictation via SFSpeechRecognizer + AVAudioEngine.
@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() {
        errorMessage = nil
        transcript = ""
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.errorMessage = "Speech recognition not allowed — enable it in iOS Settings."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.errorMessage = "Microphone access not allowed — enable it in iOS Settings."
                            return
                        }
                        self.beginRecording()
                    }
                }
            }
        }
    }

    private func beginRecording() {
        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        self.transcript = result.bestTranscription.formattedString
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        self.stop()
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        guard isRecording || audioEngine.isRunning else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
