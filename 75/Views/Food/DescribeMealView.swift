import SwiftUI
import Speech
import AVFoundation

/// "Describe your meal" — type or dictate plain text ("two eggs, sourdough
/// toast with butter, and an orange juice") and Gemini breaks it into items
/// with calories, protein, and a calorie-density color. Review, prune, log.
struct DescribeMealView: View {
    @Environment(\.dismiss) private var dismiss
    var mealLabel: String = "Today"
    let onLog: ([FoodLog]) -> Void

    @StateObject private var speech = SpeechTranscriber()
    @State private var text = ""
    @State private var dictationBase = ""
    @State private var building = false
    @State private var buildError: String?
    @State private var items: [AIFoodEstimator.MealItem] = []
    @State private var assumed = ""
    @State private var editingItem: AIFoodEstimator.MealItem?

    private var totalCalories: Int { items.reduce(0) { $0 + $1.calories } }
    private var totalProtein: Int { items.reduce(0) { $0 + $1.proteinGrams } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 100)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("What did you eat? Name the restaurant if you ate out.")
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
                    Text("e.g. “two scrambled eggs, sourdough toast with butter, and an orange juice” — or “Chipotle chicken bowl with white rice, black beans, and guac”. Named restaurants and brands are looked up against their published nutrition.")
                }

                Section {
                    Button {
                        Task { await build() }
                    } label: {
                        HStack {
                            Label(items.isEmpty ? "Build My Meal" : "Rebuild", systemImage: "sparkles")
                            if building { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || building)
                    if let err = buildError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                }

                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            Button { editingItem = item } label: {
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
                                        Text("\(item.calories) cal").foregroundStyle(.primary)
                                        Text("\(item.proteinGrams) g protein")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in items.remove(atOffsets: idx) }
                        Button {
                            onLog(items.map { FoodLog(name: $0.name,
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
                        Text("Your Meal")
                    } footer: {
                        Text(assumed.isEmpty
                             ? "Tap an item to edit its numbers · swipe to remove it."
                             : "Assumed: \(assumed)\nTap an item to edit its numbers · swipe to remove it.")
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                MealItemEditSheet(item: item) { edited in
                    if let i = items.firstIndex(where: { $0.id == edited.id }) {
                        items[i] = edited
                    }
                }
                .themedRoot()
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Describe Your Meal")
            .navigationBarTitleDisplayMode(.inline)
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
            let breakdown = try await AIFoodEstimator.mealBreakdown(description: text)
            items = breakdown.items
            assumed = breakdown.assumed
        } catch {
            buildError = error.localizedDescription
        }
    }
}

// MARK: - Per-item correction

/// Every number the AI guessed, editable — fix anything that looks off
/// before logging. Density re-buckets itself from the edited values.
private struct MealItemEditSheet: View {
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
