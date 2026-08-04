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
                    .font(.system(.body, design: .monospaced))
                    .focused($keyFocused)
                Label(keyStatus.text, systemImage: keyStatus.icon)
                    .font(.caption)
                    .foregroundStyle(keyStatus.color)
                NavigationLink {
                    GeminiKeyGuideView()
                } label: {
                    Label("How to get a free key", systemImage: "key.horizontal.fill")
                }
                Toggle("Higher accuracy (slower)", isOn: $accurateModel)
            } header: {
                Text("Model")
            } footer: {
                Text("A key is already bundled with the app, so estimates work out of the box — paste your own to use your own private quota. Higher accuracy switches estimates to the full Gemini Flash model: noticeably better numbers on complex meals, but a response takes several seconds instead of about one.")
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

    /// A quick read on what's in the key field, so pasting a bad key is
    /// obvious before an estimate ever fails. AI Studio has issued two key
    /// formats — the long-standing "AIza…" and the newer "AQ.…" — so accept
    /// either rather than flagging a perfectly good new key as broken.
    private var keyStatus: (text: String, icon: String, color: Color) {
        let trimmed = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ("Using the built-in key — paste your own to override it.",
                    "checkmark.circle", .secondary)
        }
        let knownPrefix = trimmed.hasPrefix("AIza") || trimmed.hasPrefix("AQ.")
        let looksValid = knownPrefix && trimmed.count >= 30
            && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
        return looksValid
            ? ("Key looks valid.", "checkmark.seal.fill", .green)
            : ("This doesn't look like a Gemini key — it should start with “AIza” or “AQ.”. See “How to get a free key”.",
               "exclamationmark.triangle.fill", Theme.warn)
    }
}

/// Step-by-step guide to creating a free Gemini API key in Google AI Studio,
/// with a button straight to the right page and exactly how to paste it back.
struct GeminiKeyGuideView: View {
    /// The API-keys page in Google AI Studio.
    private let studioURL = URL(string: "https://aistudio.google.com/apikey")!

    var body: some View {
        Form {
            Section {
                Text("The app already includes a shared key, so nothing is required. Add your own free key to use your own private quota — it's free, and no credit card is needed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link(destination: studioURL) {
                    Label("Open Google AI Studio", systemImage: "safari.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text("Get a free key")
            }

            Section {
                step(1, "Open Google AI Studio", "Tap the button above, or go to aistudio.google.com/apikey in Safari.")
                step(2, "Sign in with Google", "Use any Google account and accept the terms if you're asked.")
                step(3, "Create the key", "Tap “Create API key,” then “Create API key in a new project” (or pick an existing project).")
                step(4, "Copy it", "Your new key appears — tap it to copy the whole string.")
                step(5, "Paste it back here", "Return to AI & Estimates and paste it into the “Gemini API key” field. That's it.")
            } header: {
                Text("Step by step")
            }

            Section {
                Text("""
                A Gemini key looks like:

                AIzaSyD-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

                • It starts with “AIza” (or “AQ.” for newer keys) and is about 39 characters.
                • Only letters, numbers, “-” and “_” — no spaces.
                • Paste the key by itself. Don't add quotes, and don't paste a whole URL or “key=…”.

                The field shows a green “Key looks valid” once it's formatted right. (Stray spaces are trimmed automatically, but paste it clean when you can.)
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            } header: {
                Text("How the key should look")
            }

            Section {
                Text("The free tier is generous — plenty for everyday logging — and needs no card. If an estimate ever fails with a rate-limit error, wait a minute, or turn off “Higher accuracy” (the lighter model has a higher free limit).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Cost & limits")
            }

            Section {
                Text("Your key is stored only on this device and treated like a password — it's never shared. You can delete or regenerate it anytime in Google AI Studio; if it ever leaks, regenerate it there and paste the new one here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Keeping it safe")
            }
        }
        .themedForm()
        .navigationTitle("Get a Gemini Key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
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
