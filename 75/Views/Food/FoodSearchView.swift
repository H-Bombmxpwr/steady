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
    @State private var showScanner = false
    @State private var showCustom = false
    @State private var scanned: ScannedProduct?
    @State private var scanError: String?
    @State private var looking = false

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    Button { showScanner = true } label: {
                        Label("Scan Barcode", systemImage: "barcode.viewfinder")
                    }
                    Button { showCustom = true } label: {
                        Label("Custom Food", systemImage: "square.and.pencil")
                    }
                }
                Section(footer: Text("Search 7,800 USDA foods — works fully offline.")) {
                    EmptyView()
                }
            }
            ForEach(results) { item in
                Button { portionItem = item } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(2).foregroundStyle(.primary)
                        Text(subtitle(for: item))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .themedForm()
        .navigationTitle("Add Food")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search foods (e.g. chicken breast)")
        .onChange(of: query) { _ in
            results = query.count >= 2 ? FoodDatabase.shared.search(query) : []
        }
        .sheet(item: $portionItem) { item in
            PortionSheet(item: item) { log in
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
            .navigationTitle("Portion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
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

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                HStack {
                    Text("Calories")
                    Spacer()
                    TextField("0", value: $calories, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                HStack {
                    Text("Protein (g)")
                    Spacer()
                    TextField("0", value: $protein, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                Button("Add to Today") {
                    onAdd(FoodLog(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  calories: calories,
                                  proteinGrams: protein,
                                  source: "custom"))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || calories <= 0)
            }
            .themedForm()
            .navigationTitle("Custom Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
