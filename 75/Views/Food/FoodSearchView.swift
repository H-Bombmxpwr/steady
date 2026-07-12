import SwiftUI
import SwiftData

/// Add food to a specific meal of the day. Gemini ("Describe Your Meal") is
/// the headline path; database search, barcode, food photos, and manual
/// entry back it up. Offline? Custom Food still works — just type the numbers.
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    var day: DayLog

    @State private var meal: Meal
    @State private var quickFoods: [FoodLog] = []
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
            // ===== Which meal this goes into (always visible, no scrolling)
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                          spacing: 8) {
                    ForEach(Meal.allCases) { m in
                        Button {
                            meal = m
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: m.icon)
                                    .font(.subheadline)
                                    .foregroundStyle(meal == m ? .white : m.color)
                                Text(m.label)
                                    .font(.caption.weight(meal == m ? .bold : .regular))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(meal == m
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [m.color, m.color.opacity(0.65)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing))
                                        : AnyShapeStyle(Theme.surface))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(meal == m ? Color.clear : Theme.hairline)
                            )
                            .foregroundStyle(meal == m ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            } header: {
                SectionHeader(icon: "fork.knife", title: "Logging to", tint: Theme.foodTint)
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
                                Text("Type or dictate what you ate — get every item with full nutrition")
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

                // ===== Quick log: starred foods first, then recent ones
                if !quickFoods.isEmpty {
                    Section {
                        ForEach(quickFoods, id: \.persistentModelID) { f in
                            HStack(spacing: 10) {
                                Button {
                                    toggleFavorite(f)
                                } label: {
                                    Image(systemName: f.favorite ? "star.fill" : "star")
                                        .foregroundStyle(f.favorite ? Theme.warn : Color.secondary)
                                }
                                .buttonStyle(.borderless)
                                Button {
                                    relog(f)
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(f.name).lineLimit(1).foregroundStyle(.primary)
                                            Text("\(f.calories) cal · \(f.proteinGrams) g protein")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } header: {
                        SectionHeader(icon: "star.fill", title: "Quick Log", tint: Theme.warn)
                    } footer: {
                        Text("Your starred and recent foods — tap ⊕ to log one again, star to pin it here.")
                    }
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
                    Photos and meal descriptions are estimated automatically; search covers ~3M crowd-sourced products (Open Food Facts). No internet? Custom Food takes manual numbers.

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
                            Label("Not listed? Estimate “\(query)”", systemImage: "sparkles")
                                .lineLimit(1)
                        }
                    }
                } footer: {
                    Text("Crowd-sourced data — sanity-check anything that looks off. Missing protein is filled in automatically on the portion screen.")
                }
            }
        }
        .themedForm()
        .navigationTitle("Add Food")
        .searchable(text: $query, isPresented: $searchActive,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search foods (e.g. chicken breast)")
        .onChange(of: query) { _ in runSearch() }
        .onAppear { loadQuickFoods() }
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
        day.addFood(log, meal: meal)
    }

    // MARK: Quick log (favorites + recents)

    /// Starred foods first, then the most recent distinct foods, 8 total.
    private func loadQuickFoods() {
        var descriptor = FetchDescriptor<FoodLog>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 300
        let all = (try? context.fetch(descriptor)) ?? []

        var seen = Set<String>()
        var favorites: [FoodLog] = []
        var recents: [FoodLog] = []
        let favoriteNames = Set(all.filter(\.favorite).map { $0.name.lowercased() })
        for f in all {
            let key = f.name.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            if favoriteNames.contains(key) {
                f.favorite = true    // surface the star on the newest instance
                favorites.append(f)
            } else {
                recents.append(f)
            }
        }
        quickFoods = favorites + recents.prefix(max(0, 8 - favorites.count))
    }

    /// Stars/unstars every logged instance of this food by name, so the
    /// pin survives whichever copy gets fetched next time.
    private func toggleFavorite(_ food: FoodLog) {
        let key = food.name.lowercased()
        let newValue = !food.favorite
        var descriptor = FetchDescriptor<FoodLog>()
        descriptor.fetchLimit = 1000
        for f in (try? context.fetch(descriptor)) ?? [] where f.name.lowercased() == key {
            f.favorite = newValue
        }
        try? context.save()
        loadQuickFoods()
    }

    /// Logs a fresh copy of a previous food into the selected meal.
    private func relog(_ f: FoodLog) {
        add(FoodLog(name: f.name,
                    calories: f.calories,
                    proteinGrams: f.proteinGrams,
                    grams: f.grams,
                    source: f.source,
                    density: f.density,
                    facts: f.facts))
        dismiss()
    }

    private func subtitle(for item: FoodItem) -> String {
        var text = "\(Int(item.c)) cal · "
        text += item.proteinKnown ? "\(item.p.formatted()) g protein" : "protein: auto-estimated"
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
                                Text("est.")
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
                        Text("Assumed: \(aiAssumed)")
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
                            Label("Estimate Nutrition", systemImage: "sparkles")
                            if estimating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || estimating)
                    if let err = estimateError {
                        Text(err).font(.footnote).foregroundStyle(.red)
                    }
                    if !assumedText.isEmpty {
                        Text("Assumed: \(assumedText)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(AIFoodEstimator.apiKey.isEmpty
                         ? "Add an API key in Settings → About Estimates to auto-fill the full nutrition panel from the name."
                         : estimated
                            ? "Estimated for one typical serving — if that's not what you meant, refine the name and estimate again."
                            : "Estimates one typical serving: calories, protein, fats, sodium, and more.")
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
                    Section("Full Nutrition") {
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
