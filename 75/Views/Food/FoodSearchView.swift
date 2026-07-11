import SwiftUI
import SwiftData

/// Add food to a specific meal of the day. Gemini ("Describe Your Meal") is
/// the headline path; database search, barcode, food photos, and manual
/// entry back it up. Offline? Custom Food still works — just type the numbers.
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog

    @State private var meal: Meal
    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var searching = false
    @State private var searchFailed = false
    @State private var searchErrorText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var portionItem: FoodItem?
    @State private var showScanner = false
    @State private var showDescribe = false
    @State private var searchActive = false
    @State private var customRequest: CustomFoodRequest?
    @State private var scanned: FoodItem?
    @State private var scanError: String?
    @State private var looking = false

    // Photo-of-food (Gemini vision)
    @State private var showFoodCamera = false
    @State private var recognizing = false

    init(day: DayLog, meal: Meal = .suggested()) {
        self.day = day
        _meal = State(initialValue: meal)
    }

    var body: some View {
        List {
            // ===== Which meal this goes into (always visible)
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Meal.allCases) { m in
                            Button {
                                meal = m
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: m.icon).font(.caption)
                                    Text(m.label)
                                        .font(.subheadline.weight(meal == m ? .semibold : .regular))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(meal == m
                                    ? AnyShapeStyle(Theme.gradient)
                                    : AnyShapeStyle(Theme.surface2)))
                                .foregroundStyle(meal == m ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                .listRowBackground(Color.clear)
            } header: {
                SectionHeader(icon: "fork.knife", title: "Logging to")
            }

            if query.isEmpty {
                // ===== Headline path: Gemini
                Section {
                    Button { showDescribe = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "sparkles")
                                .font(.title2.bold())
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Describe Your Meal")
                                    .font(.title3.bold())
                                Text("Type or dictate what you ate — AI itemizes it with full nutrition")
                                    .font(.caption)
                                    .opacity(0.9)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.bold())
                                .opacity(0.7)
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 14)
                    }
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.gradient)
                    )
                }

                // ===== Smaller fallbacks
                Section {
                    Button { showFoodCamera = true } label: {
                        HStack {
                            Label("Photo of Food", systemImage: "camera.viewfinder")
                            if recognizing { Spacer(); ProgressView() }
                        }
                    }
                    Button { showScanner = true } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                    Button { searchActive = true } label: {
                        Label("Search the Database", systemImage: "magnifyingglass")
                    }
                    Button {
                        customRequest = CustomFoodRequest(name: "", autoEstimate: false)
                    } label: {
                        Label("Custom Food", systemImage: "square.and.pencil")
                    }
                } header: {
                    SectionHeader(icon: "tray.full.fill", title: "Other ways to log")
                } footer: {
                    Text("""
                    Photos and meal descriptions go through AI; search covers ~3M crowd-sourced products (Open Food Facts). No internet? Custom Food takes manual numbers.

                    Food colors are calorie density, Noom-style: 🟢 green = under 1 cal per gram (eat freely) · 🟠 orange = 1–2.4 (moderate) · 🔴 red = over 2.4 (calorie-dense — small portions add up fast).
                    """)
                }
            } else {
                Section {
                    if searching && results.isEmpty {
                        HStack {
                            Text("Searching…").foregroundStyle(.secondary)
                            Spacer()
                            ProgressView()
                        }
                    } else if searchFailed {
                        Text(searchErrorText)
                            .foregroundStyle(.secondary)
                        Button {
                            runSearch(immediately: true)
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                    } else if results.isEmpty && !searching && query.count >= 3 {
                        Text("No matches.").foregroundStyle(.secondary)
                    }
                    ForEach(results) { item in
                        Button { portionItem = item } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.densityBucket?.color ?? Color.secondary)
                                    .frame(width: 9, height: 9)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).lineLimit(2).foregroundStyle(.primary)
                                    Text(subtitle(for: item))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if query.count >= 3 {
                        Button {
                            customRequest = CustomFoodRequest(name: query, autoEstimate: true)
                        } label: {
                            Label("Not listed? AI estimates “\(query)”", systemImage: "sparkles")
                                .lineLimit(1)
                        }
                    }
                } footer: {
                    Text("Crowd-sourced data — sanity-check anything that looks off. Missing protein is estimated by AI on the portion screen.")
                }
            }
        }
        .themedForm()
        .navigationTitle("Add Food")
        .searchable(text: $query, isPresented: $searchActive,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search foods (e.g. chicken breast)")
        .onChange(of: query) { _ in runSearch() }
        .sheet(item: $portionItem) { item in
            PortionSheet(item: item, source: "off", mealLabel: meal.label) { log in
                add(log)
                dismiss()
            }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack {
                ZStack {
                    BarcodeScannerView { code in
                        showScanner = false
                        Task { await lookup(code) }
                    }
                    .ignoresSafeArea()
                    if looking { ProgressView().controlSize(.large) }
                }
                .navigationTitle("Scan Barcode")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showScanner = false }
                    }
                }
            }
            .themedRoot()
        }
        .sheet(item: $scanned) { item in
            PortionSheet(item: item, source: "barcode", mealLabel: meal.label) { log in
                add(log)
                scanned = nil
                dismiss()
            }
        }
        .sheet(isPresented: $showDescribe) {
            DescribeMealView(mealLabel: meal.label) { logs in
                logs.forEach { add($0) }
                dismiss()
            }
            .themedRoot()
        }
        .sheet(item: $customRequest) { req in
            CustomFoodSheet(request: req, mealLabel: meal.label) { log in
                add(log)
                dismiss()
            }
        }
        .sheet(isPresented: $showFoodCamera) {
            CameraCaptureView { image in
                showFoodCamera = false
                Task {
                    recognizing = true
                    do {
                        let est = try await AIFoodEstimator.estimate(photo: image)
                        customRequest = CustomFoodRequest(estimate: est)
                    } catch {
                        scanError = error.localizedDescription
                    }
                    recognizing = false
                }
            }
        }
        .alert("Product not found", isPresented: Binding(get: { scanError != nil },
                                                         set: { if !$0 { scanError = nil } })) {
            Button("OK") {}
        } message: {
            Text(scanError ?? "")
        }
    }

    private func add(_ log: FoodLog) {
        log.meal = meal
        day.foods.append(log)
    }

    private func subtitle(for item: FoodItem) -> String {
        var text = "\(Int(item.c)) cal · "
        text += item.proteinKnown ? "\(item.p.formatted()) g protein" : "protein: AI will estimate"
        text += " per 100 g"
        if let pd = item.pd, let pg = item.pg {
            text += "  ·  \(pd) = \(Int(pg)) g"
        }
        return text
    }

    /// Debounced live search — waits for a typing pause, then queries OFF.
    private func runSearch(immediately: Bool = false) {
        searchTask?.cancel()
        searchFailed = false
        guard query.count >= 3 else {
            results = []
            searching = false
            return
        }
        searching = true
        let q = query
        searchTask = Task {
            if !immediately {
                try? await Task.sleep(nanoseconds: 550_000_000)
                guard !Task.isCancelled else { return }
            }
            do {
                let items = try await OpenFoodFacts.search(q)
                guard !Task.isCancelled else { return }
                results = items
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchFailed = true
                searchErrorText = error.localizedDescription
            }
            searching = false
        }
    }

    private func lookup(_ code: String) async {
        looking = true
        defer { looking = false }
        do {
            if let item = try await OpenFoodFacts.lookup(barcode: code) {
                scanned = item
            } else {
                scanError = "That barcode isn't in Open Food Facts. Try Custom Food instead."
            }
        } catch {
            scanError = "Couldn't reach Open Food Facts — check your connection, or use Custom Food."
        }
    }
}

/// Item-driven request for the custom-food sheet (item sheets always see
/// fresh values; isPresented sheets can capture stale state).
private struct CustomFoodRequest: Identifiable {
    let id = UUID()
    var name: String
    var calories = 0
    var protein = 0
    var grams: Double?
    var facts = NutritionFacts()
    var density: String?
    var assumed = ""
    var autoEstimate = false

    init(name: String, autoEstimate: Bool) {
        self.name = name
        self.autoEstimate = autoEstimate
    }

    /// Pre-filled from a photo recognition result.
    init(estimate: AIFoodEstimator.Estimate) {
        name = estimate.name
        calories = estimate.calories
        protein = estimate.proteinGrams
        grams = estimate.grams
        facts = estimate.facts
        density = estimate.density
        assumed = estimate.assumed
    }
}

// MARK: - Portion picker

private struct PortionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: FoodItem
    var source: String = "off"
    var mealLabel: String = "Today"
    let onAdd: (FoodLog) -> Void

    @State private var grams: Double = 100
    @State private var servings: Double = 1

    // When the source has no protein value, Gemini fills it in automatically.
    @State private var aiProteinPer100g: Double?
    @State private var aiAssumed = ""
    @State private var aiFetching = false

    init(item: FoodItem, source: String = "off", mealLabel: String = "Today",
         onAdd: @escaping (FoodLog) -> Void) {
        self.item = item
        self.source = source
        self.mealLabel = mealLabel
        self.onAdd = onAdd
        _grams = State(initialValue: item.pg ?? 100)
    }

    private var effectiveGrams: Double {
        if let pg = item.pg { return pg * servings }
        return grams
    }

    private var effectiveProtein: Int {
        if item.proteinKnown { return item.protein(grams: effectiveGrams) }
        if let per100 = aiProteinPer100g {
            return Int((per100 * effectiveGrams / 100).rounded())
        }
        return 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.name).font(.headline)
                    if let d = item.densityBucket {
                        HStack(spacing: 8) {
                            Circle().fill(d.color).frame(width: 10, height: 10)
                            Text(d.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if let pd = item.pd, item.pg != nil {
                    Section("Portion") {
                        Stepper(value: $servings, in: 0.25...20, step: 0.25) {
                            HStack {
                                Text("\(servings.formatted()) × \(pd)")
                                Spacer()
                                Text("\(Int(effectiveGrams)) g").foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Section("Amount") {
                        HStack {
                            Text("Grams")
                            Spacer()
                            TextField("g", value: $grams, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                }
                Section {
                    HStack {
                        Text("Calories")
                        Spacer()
                        Text("\(item.calories(grams: effectiveGrams)) cal").bold()
                    }
                    HStack {
                        Text("Protein")
                        Spacer()
                        if aiFetching {
                            ProgressView()
                        } else {
                            if !item.proteinKnown && aiProteinPer100g != nil {
                                Text("AI")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.accent.opacity(0.2)))
                                    .foregroundStyle(Theme.accent)
                            }
                            Text("\(effectiveProtein) g").bold()
                        }
                    }
                    NutritionFactsRows(facts: item.facts(grams: effectiveGrams), compact: true)
                    if !aiAssumed.isEmpty {
                        Text("AI assumed: \(aiAssumed)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Add to \(mealLabel)") {
                    onAdd(FoodLog(name: item.name,
                                  calories: item.calories(grams: effectiveGrams),
                                  proteinGrams: effectiveProtein,
                                  grams: effectiveGrams,
                                  source: source,
                                  density: item.densityBucket?.rawValue,
                                  facts: item.facts(grams: effectiveGrams)))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                guard !item.proteinKnown, !AIFoodEstimator.apiKey.isEmpty else { return }
                aiFetching = true
                if let est = try? await AIFoodEstimator.proteinPer100g(food: item.name) {
                    aiProteinPer100g = est.gramsPer100g
                    aiAssumed = est.assumed
                }
                aiFetching = false
            }
        }
        .themedRoot()
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Custom food

private struct CustomFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (FoodLog) -> Void
    private let autoEstimate: Bool
    private let mealLabel: String

    @State private var name: String
    @State private var calories = 0
    @State private var protein = 0
    @State private var proteinUnknown = false

    // Carried along from AI estimates (manual entries leave these empty).
    @State private var grams: Double?
    @State private var facts = NutritionFacts()
    @State private var density: String?

    @State private var estimating = false
    @State private var estimateError: String?
    @State private var estimated = false
    @State private var assumedText = ""

    /// `autoEstimate` runs the AI fill immediately — used when a search had
    /// no Open Food Facts match and the user asked AI to take over. Photo
    /// recognition passes pre-computed values in instead.
    init(request: CustomFoodRequest, mealLabel: String = "Today",
         onAdd: @escaping (FoodLog) -> Void) {
        self.onAdd = onAdd
        self.mealLabel = mealLabel
        self.autoEstimate = request.autoEstimate && !request.name.isEmpty
        _name = State(initialValue: request.name)
        _calories = State(initialValue: request.calories)
        _protein = State(initialValue: request.protein)
        _grams = State(initialValue: request.grams)
        _facts = State(initialValue: request.facts)
        _density = State(initialValue: request.density)
        _assumedText = State(initialValue: request.assumed)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Section {
                    Button {
                        Task { await estimate() }
                    } label: {
                        HStack {
                            Label("Estimate with AI", systemImage: "sparkles")
                            if estimating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || estimating)
                    if let err = estimateError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                    if !assumedText.isEmpty {
                        Text("AI assumed: \(assumedText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(AIFoodEstimator.apiKey.isEmpty
                         ? "Add a free Gemini API key in Settings → AI Assist to auto-estimate the full nutrition panel from the name — no more googling protein counts."
                         : estimated
                            ? "Estimated for one typical serving — if that's not what you meant, refine the name and estimate again."
                            : "Estimates one typical serving (calories, protein, fats, sodium, and more) via Gemini using your API key.")
                }
                HStack {
                    Text("Calories")
                    Spacer()
                    TextField("0", value: $calories, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                Toggle("Protein unknown", isOn: $proteinUnknown)
                if !proteinUnknown {
                    HStack {
                        Text("Protein (g)")
                        Spacer()
                        TextField("0", value: $protein, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }
                if facts != NutritionFacts() {
                    Section("Full Nutrition (AI)") {
                        NutritionFactsRows(facts: facts, compact: true)
                    }
                }
                Button("Add to \(mealLabel)") {
                    onAdd(FoodLog(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  calories: calories,
                                  proteinGrams: proteinUnknown ? 0 : protein,
                                  grams: grams,
                                  source: "custom",
                                  density: density,
                                  facts: facts))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || calories <= 0)
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if autoEstimate { await estimate() }
            }
        }
        .themedRoot()
        .presentationDetents([.medium, .large])
    }

    private func estimate() async {
        estimating = true
        estimateError = nil
        defer { estimating = false }
        do {
            let result = try await AIFoodEstimator.estimate(food: name)
            calories = result.calories
            protein = result.proteinGrams
            proteinUnknown = false
            grams = result.grams
            facts = result.facts
            density = result.density
            estimated = true
            assumedText = result.assumed
        } catch {
            estimateError = error.localizedDescription
        }
    }
}
