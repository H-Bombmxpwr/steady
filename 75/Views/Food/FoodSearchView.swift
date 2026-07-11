import SwiftUI
import SwiftData

/// Search Open Food Facts as you type (~3M crowd-sourced products), scan a
/// barcode, or enter a custom food, then log a portion to the given day.
/// Offline? Custom Food still works — just type the numbers in.
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog

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
    @State private var scanned: ScannedProduct?
    @State private var scanError: String?
    @State private var looking = false

    // Photo-of-food (Gemini vision)
    @State private var showFoodCamera = false
    @State private var recognizing = false

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    Button { searchActive = true } label: {
                        Label("Search the Database", systemImage: "magnifyingglass")
                    }
                    Button { showScanner = true } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                    Button { showFoodCamera = true } label: {
                        HStack {
                            Label("Photo of Food", systemImage: "camera.viewfinder")
                            if recognizing { Spacer(); ProgressView() }
                        }
                    }
                    Button { showDescribe = true } label: {
                        Label("Describe Your Meal", systemImage: "waveform")
                    }
                    Button {
                        customRequest = CustomFoodRequest(name: "", autoEstimate: false)
                    } label: {
                        Label("Custom Food", systemImage: "square.and.pencil")
                    }
                } footer: {
                    Text("""
                    Search covers ~3M crowd-sourced products (Open Food Facts); photos and meal descriptions go through AI. No internet? Custom Food takes manual numbers.

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
            PortionSheet(item: item, source: "off") { log in
                day.foods.append(log)
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
        .sheet(isPresented: Binding(get: { scanned != nil }, set: { if !$0 { scanned = nil } })) {
            if let product = scanned {
                PortionSheet(item: FoodItem(n: product.name,
                                            c: product.caloriesPer100g,
                                            p: product.proteinPer100g ?? 0,
                                            f: 0, cb: 0,
                                            pd: product.servingSizeText, pg: nil,
                                            pu: product.proteinPer100g == nil),
                             source: "barcode") { log in
                    day.foods.append(log)
                    scanned = nil
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showDescribe) {
            DescribeMealView { logs in
                logs.forEach { day.foods.append($0) }
                dismiss()
            }
            .themedRoot()
        }
        .sheet(item: $customRequest) { req in
            CustomFoodSheet(initialName: req.name,
                            initialCalories: req.calories,
                            initialProtein: req.protein,
                            initialAssumed: req.assumed,
                            autoEstimate: req.autoEstimate) { log in
                day.foods.append(log)
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
                        customRequest = CustomFoodRequest(name: est.name,
                                                          calories: est.calories,
                                                          protein: est.proteinGrams,
                                                          assumed: est.assumed,
                                                          autoEstimate: false)
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
            if let product = try await OpenFoodFacts.lookup(barcode: code) {
                scanned = product
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
    var assumed = ""
    var autoEstimate = false
}

// MARK: - Portion picker

private struct PortionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: FoodItem
    var source: String = "off"
    let onAdd: (FoodLog) -> Void

    @State private var grams: Double = 100
    @State private var servings: Double = 1

    // When the source has no protein value, Gemini fills it in automatically.
    @State private var aiProteinPer100g: Double?
    @State private var aiAssumed = ""
    @State private var aiFetching = false

    init(item: FoodItem, source: String = "off", onAdd: @escaping (FoodLog) -> Void) {
        self.item = item
        self.source = source
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
                    if !aiAssumed.isEmpty {
                        Text("AI assumed: \(aiAssumed)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Add to Today") {
                    onAdd(FoodLog(name: item.name,
                                  calories: item.calories(grams: effectiveGrams),
                                  proteinGrams: effectiveProtein,
                                  grams: effectiveGrams,
                                  source: source,
                                  density: item.densityBucket?.rawValue))
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

    @State private var name: String
    @State private var calories = 0
    @State private var protein = 0
    @State private var proteinUnknown = false

    @State private var estimating = false
    @State private var estimateError: String?
    @State private var estimated = false
    @State private var assumedText = ""

    /// `autoEstimate` runs the AI fill immediately — used when a search had
    /// no Open Food Facts match and the user asked AI to take over. Photo
    /// recognition passes pre-computed values in instead.
    init(initialName: String = "", initialCalories: Int = 0, initialProtein: Int = 0,
         initialAssumed: String = "", autoEstimate: Bool = false,
         onAdd: @escaping (FoodLog) -> Void) {
        self.onAdd = onAdd
        self.autoEstimate = autoEstimate && !initialName.isEmpty
        _name = State(initialValue: initialName)
        _calories = State(initialValue: initialCalories)
        _protein = State(initialValue: initialProtein)
        _assumedText = State(initialValue: initialAssumed)
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
                         ? "Add a free Gemini API key in Settings → AI Assist to auto-estimate calories and protein from the name — no more googling protein counts."
                         : estimated
                            ? "Estimated for one typical serving — if that's not what you meant, refine the name and estimate again."
                            : "Estimates one typical serving via Gemini using your API key.")
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
                Button("Add to Today") {
                    onAdd(FoodLog(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  calories: calories,
                                  proteinGrams: proteinUnknown ? 0 : protein,
                                  source: "custom"))
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
            estimated = true
            assumedText = result.assumed
        } catch {
            estimateError = error.localizedDescription
        }
    }
}
