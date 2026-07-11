import SwiftUI
import SwiftData

/// Search the bundled USDA database, scan a barcode, or enter a custom food,
/// then log a portion to the given day.
struct FoodSearchView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog

    @State private var query = ""
    @State private var results: [FoodItem] = []
    @State private var portionItem: FoodItem?
    @State private var portionSource = "usda"
    @State private var onlineResults: [FoodItem] = []
    @State private var searchingOnline = false
    @State private var searchedOnline = false
    @State private var showScanner = false
    @State private var showCustom = false
    @State private var scanned: ScannedProduct?
    @State private var scanError: String?
    @State private var looking = false

    // Photo-of-food
    @State private var showFoodCamera = false
    @State private var recognizing = false
    @State private var suggestions: [FoodPhotoRecognizer.Suggestion] = []
    @State private var showSuggestions = false

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    Button { showScanner = true } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                    Button { showFoodCamera = true } label: {
                        HStack {
                            Label("Photo of Food", systemImage: "camera.viewfinder")
                            if recognizing { Spacer(); ProgressView() }
                        }
                    }
                    Button { showCustom = true } label: {
                        Label("Custom Food", systemImage: "square.and.pencil")
                    }
                }
                Section(footer: Text("Search 7,800 USDA foods offline, or tap “Search online” under the results for ~3M crowd-sourced products. Photo recognition runs on-device; nothing is uploaded.")) {
                    EmptyView()
                }
            }
            ForEach(results) { item in
                Button { portionSource = "usda"; portionItem = item } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(2).foregroundStyle(.primary)
                        Text(subtitle(for: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if query.count >= 3 {
                Section {
                    if !searchedOnline {
                        Button {
                            Task { await searchOnline() }
                        } label: {
                            HStack {
                                Label("Search Open Food Facts online", systemImage: "globe")
                                if searchingOnline { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(searchingOnline)
                    } else if onlineResults.isEmpty {
                        Text("No online matches.").foregroundStyle(.secondary)
                    }
                    ForEach(onlineResults) { item in
                        Button { portionSource = "off"; portionItem = item } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(2).foregroundStyle(.primary)
                                Text(subtitle(for: item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Online search covers ~3M crowd-sourced products (brands, restaurants) — quality varies, so sanity-check the numbers.")
                }
            }
        }
        .themedForm()
        .navigationTitle("Add Food")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search foods (e.g. chicken breast)")
        .onChange(of: query) { _ in
            results = query.count >= 2 ? FoodDatabase.shared.search(query) : []
            onlineResults = []
            searchedOnline = false
        }
        .sheet(item: $portionItem) { item in
            PortionSheet(item: item, source: portionSource) { log in
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
                                            p: product.proteinPer100g,
                                            f: 0, cb: 0,
                                            pd: product.servingSizeText, pg: nil),
                             source: "barcode") { log in
                    day.foods.append(log)
                    scanned = nil
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showCustom) {
            CustomFoodSheet { log in
                day.foods.append(log)
                dismiss()
            }
        }
        .sheet(isPresented: $showFoodCamera) {
            CameraCaptureView { image in
                showFoodCamera = false
                Task {
                    recognizing = true
                    suggestions = await FoodPhotoRecognizer.recognize(image: image)
                    recognizing = false
                    if suggestions.isEmpty {
                        scanError = "Couldn't recognize a food in that photo. Try search or Custom Food."
                    } else {
                        showSuggestions = true
                    }
                }
            }
        }
        .sheet(isPresented: $showSuggestions) {
            NavigationStack {
                List {
                    ForEach(suggestions) { s in
                        Section("\(s.label) — \(Int(s.confidence * 100))% match") {
                            ForEach(s.matches) { item in
                                Button {
                                    showSuggestions = false
                                    portionItem = item
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name).lineLimit(2).foregroundStyle(.primary)
                                        Text(subtitle(for: item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Is it one of these?")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showSuggestions = false }
                    }
                }
            }
            .themedRoot()
            .presentationDetents([.medium, .large])
        }
        .alert("Product not found", isPresented: Binding(get: { scanError != nil },
                                                         set: { if !$0 { scanError = nil } })) {
            Button("OK") {}
        } message: {
            Text(scanError ?? "")
        }
    }

    private func subtitle(for item: FoodItem) -> String {
        var text = "\(Int(item.c)) cal · \(item.p.formatted()) g protein per 100 g"
        if let pd = item.pd, let pg = item.pg {
            text += "  ·  \(pd) = \(Int(pg)) g"
        }
        return text
    }

    private func searchOnline() async {
        searchingOnline = true
        defer { searchingOnline = false }
        do {
            onlineResults = try await OpenFoodFacts.search(query)
            searchedOnline = true
        } catch {
            scanError = "Couldn't reach Open Food Facts — check your connection."
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

// MARK: - Portion picker

private struct PortionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: FoodItem
    var source: String = "usda"
    let onAdd: (FoodLog) -> Void

    @State private var grams: Double = 100
    @State private var servings: Double = 1

    init(item: FoodItem, source: String = "usda", onAdd: @escaping (FoodLog) -> Void) {
        self.item = item
        self.source = source
        self.onAdd = onAdd
        _grams = State(initialValue: item.pg ?? 100)
    }

    private var effectiveGrams: Double {
        if let pg = item.pg { return pg * servings }
        return grams
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(item.name).font(.headline)
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
                        Text("\(item.protein(grams: effectiveGrams)) g").bold()
                    }
                }
                Button("Add to Today") {
                    onAdd(FoodLog(name: item.name,
                                  calories: item.calories(grams: effectiveGrams),
                                  proteinGrams: item.protein(grams: effectiveGrams),
                                  grams: effectiveGrams,
                                  source: source))
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
        }
        .themedRoot()
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Custom food

private struct CustomFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAdd: (FoodLog) -> Void

    @State private var name = ""
    @State private var calories = 0
    @State private var protein = 0
    @State private var proteinUnknown = false

    @State private var estimating = false
    @State private var estimateError: String?
    @State private var estimated = false

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
                } footer: {
                    Text(AIFoodEstimator.apiKey.isEmpty
                         ? "Add a free Gemini API key in Settings → AI Assist to auto-estimate calories and protein from the name — no more googling protein counts."
                         : estimated
                            ? "Estimated for one typical serving — adjust if your portion differs."
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
        } catch {
            estimateError = error.localizedDescription
        }
    }
}
