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
                                Text("What did you eat?")
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
                    Text("e.g. “two scrambled eggs, sourdough toast with butter, and a glass of orange juice”")
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
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(FoodDensity(rawValue: item.density ?? "")?.color ?? .secondary)
                                    .frame(width: 9, height: 9)
                                Text(item.name).lineLimit(2)
                                Spacer()
                                Text("\(item.calories) cal · \(item.proteinGrams)g")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                             ? "Swipe to remove anything that's wrong."
                             : "AI assumed: \(assumed)\nSwipe to remove anything that's wrong.")
                    }
                }
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
