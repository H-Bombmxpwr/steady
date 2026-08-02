import SwiftUI

/// Everything about how the app uses AI, moved out of the main Settings list
/// into its own screen: what it powers, where your data goes, your API key,
/// the accuracy toggle, and the exact prompts it sends — with the parts you
/// enter shown as ‹placeholders›.
struct AISettingsView: View {
    @AppStorage(AIFoodEstimator.apiKeyKey) private var geminiKey = ""
    @AppStorage(AIFoodEstimator.accurateModelKey) private var accurateModel = false
    @FocusState private var keyFocused: Bool

    var body: some View {
        Form {
            // --- What it powers / what leaves the device
            Section {
                Text("""
                Nutrition estimates in this app are powered by Google's Gemini model. It's behind:

                • Describe Your Meal — itemizing what you type or dictate
                • Photo of Food — reading a plate into separate items
                • Recipe from a Link — reading a web or video recipe into items
                • Estimate Nutrition on custom foods and “Not listed?” search results
                • Filling in protein when a database entry is missing it
                • What Should I Eat? — meal ideas that fit your remaining budget
                • Summarize My Day — the end-of-day review and swaps

                Only food descriptions and food photos are sent to Google. Progress photos, weight, and everything else never leave the device. Estimates are good, not perfect — every number stays editable after logging, and a green “Looked up” badge marks numbers checked against real published data (vs an orange “Best guess”).
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("How AI is used")
            }

            // --- Key + accuracy
            Section {
                TextField("Gemini API key", text: $geminiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($keyFocused)
                Toggle("Higher accuracy (slower)", isOn: $accurateModel)
            } header: {
                Text("Model")
            } footer: {
                Text("A key is already bundled with the app — paste your own from aistudio.google.com to override it. Higher accuracy switches estimates to the full Gemini Flash model: noticeably better numbers on complex meals, but a response takes several seconds instead of about one.")
            }

            // --- The exact prompts
            Section {
                ForEach(AIFoodEstimator.promptCatalog) { info in
                    NavigationLink {
                        PromptDetailView(info: info)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(info.title)
                                if info.grounded {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
                            }
                            Text(info.whenUsed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Prompts")
            } footer: {
                Text("The exact instructions sent for each feature. Anything you enter is shown as a ‹placeholder›. Nothing is sent until you actually use the feature.")
            }
        }
        .themedForm()
        .navigationTitle("AI & Estimates")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyFocused = false }
            }
        }
    }
}

/// One prompt in full — what fires it, what it sends, whether it's grounded,
/// and the verbatim template with ‹placeholders› for your input.
private struct PromptDetailView: View {
    let info: AIFoodEstimator.PromptInfo

    var body: some View {
        Form {
            Section {
                labeled("When", info.whenUsed)
                labeled("Sends", info.sends)
                labeled("Grounding", info.groundingNote)
            }
            Section {
                Text(info.template)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 2)
            } header: {
                Text("Prompt sent")
            } footer: {
                Text("The model is asked to reply with only JSON, which the app parses into editable nutrition numbers.")
            }
        }
        .themedForm()
        .navigationTitle(info.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
