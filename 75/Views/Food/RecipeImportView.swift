import SwiftUI
import UIKit

/// "Paste a link" — drop in a recipe web page or video URL and Gemini reads
/// it into its ingredients with full nutrition. Recipes make several
/// servings, so the whole-recipe numbers divide down to however many
/// servings you're actually logging (default one), and every item stays
/// editable before it lands in the day.
struct RecipeImportView: View {
    @Environment(\.dismiss) private var dismiss
    var mealLabel: String = "Today"
    let onLog: ([FoodLog]) -> Void

    @State private var url = ""
    @State private var importing = false
    @State private var importError: String?

    @State private var title = ""
    @State private var items: [AIFoodEstimator.MealItem] = []
    @State private var recipeServings = 1
    @State private var servingsToLog = 1.0
    @State private var assumed = ""
    @State private var note = ""
    @State private var grounded: Bool?
    @State private var editingItem: AIFoodEstimator.MealItem?

    /// Fraction of the whole recipe being logged.
    private var factor: Double { servingsToLog / Double(max(1, recipeServings)) }

    private func scaled(_ item: AIFoodEstimator.MealItem) -> AIFoodEstimator.MealItem {
        item.scaled(by: factor)
    }

    private var totalCalories: Int { items.reduce(0) { $0 + scaled($1).calories } }
    private var totalProtein: Int { items.reduce(0) { $0 + scaled($1).proteinGrams } }

    var body: some View {
        NavigationStack {
            Form {
                // --- The link
                Section {
                    TextField("https://…", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    Button {
                        if let s = UIPasteboard.general.string { url = s }
                    } label: {
                        Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!UIPasteboard.general.hasStrings)
                } footer: {
                    Text("A recipe website or a YouTube link works best. Short-form video (TikTok, Instagram) is hit-or-miss — if it can't be read, paste the ingredients into Describe Your Meal instead.")
                }

                Section {
                    Button {
                        Task { await runImport() }
                    } label: {
                        HStack {
                            Label(items.isEmpty ? "Read the Recipe" : "Re-read",
                                  systemImage: "link")
                            if importing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(url.trimmingCharacters(in: .whitespaces).isEmpty || importing)
                    if let importError {
                        Text(importError).font(.footnote).foregroundStyle(.red)
                    }
                }

                if !items.isEmpty {
                    // --- Servings
                    Section {
                        Stepper(value: $servingsToLog,
                                in: 0.5...Double(max(1, recipeServings)), step: 0.5) {
                            HStack {
                                Text("Log")
                                Text("\(servingsToLog.formatted()) serving\(servingsToLog == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Servings")
                    } footer: {
                        Text("This recipe makes about \(recipeServings) serving\(recipeServings == 1 ? "" : "s"). The numbers below are for the servings you're logging — step it up to log more, or the whole batch.")
                    }

                    // --- Items (whole recipe, scaled to servingsToLog)
                    Section {
                        ForEach(items) { item in
                            let s = scaled(item)
                            Button { editingItem = s } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(FoodDensity(rawValue: item.density ?? "")?.color ?? .secondary)
                                        .frame(width: 9, height: 9)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).lineLimit(2).foregroundStyle(.primary)
                                        if let a = item.assumed, !a.isEmpty {
                                            Text(a).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("\(s.calories) cal").foregroundStyle(.primary)
                                        Text("\(s.proteinGrams) g protein")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in items.remove(atOffsets: idx) }
                        Button {
                            onLog(items.map { scaled($0) }.map {
                                FoodLog(name: $0.name,
                                        calories: $0.calories,
                                        proteinGrams: $0.proteinGrams,
                                        grams: $0.grams,
                                        source: "ai",
                                        density: $0.density,
                                        facts: $0.facts)
                            })
                            dismiss()
                        } label: {
                            Text("Log \(items.count) Item\(items.count == 1 ? "" : "s") to \(mealLabel) — \(totalCalories) cal · \(totalProtein)g protein")
                                .bold()
                        }
                    } header: {
                        HStack {
                            Text(title.isEmpty ? "Ingredients" : title)
                            Spacer()
                            if let grounded { GroundingBadge(grounded: grounded) }
                        }
                    } footer: {
                        Text(footerText)
                    }
                }
            }
            .sheet(item: $editingItem) { item in
                MealItemEditSheet(item: item) { edited in
                    // The edit sheet works on the scaled (per-serving) item —
                    // fold the change back up to the whole-recipe baseline so
                    // the servings math stays consistent.
                    if let i = items.firstIndex(where: { $0.id == edited.id }) {
                        items[i] = factor > 0 ? edited.scaled(by: 1 / factor) : edited
                    }
                }
                .themedRoot()
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Recipe from a Link")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Prefill a link already sitting on the clipboard.
                if url.isEmpty, let s = UIPasteboard.general.string,
                   s.lowercased().hasPrefix("http") {
                    url = s
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var footerText: String {
        var parts: [String] = []
        if !assumed.isEmpty { parts.append("Assumed: \(assumed)") }
        if !note.isEmpty { parts.append(note) }
        parts.append("Tap an item to edit its numbers · swipe to remove one you're leaving out.")
        return parts.joined(separator: "\n")
    }

    private func runImport() async {
        importing = true
        importError = nil
        defer { importing = false }
        do {
            let recipe = try await AIFoodEstimator.recipeBreakdown(url: url)
            title = recipe.title
            items = recipe.items
            recipeServings = recipe.servings
            servingsToLog = 1
            assumed = recipe.assumed
            note = recipe.note
            grounded = recipe.grounded
        } catch {
            importError = error.localizedDescription
        }
    }
}
