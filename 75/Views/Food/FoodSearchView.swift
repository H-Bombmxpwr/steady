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
    @Query(sort: \SavedMeal.createdAt, order: .reverse) private var savedMeals: [SavedMeal]
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
    @State private var capturedPlate: CapturedPlate?

    // Recipe-from-a-link (Gemini URL/video reading)
    @State private var showRecipeLink = false

    // A saved meal being logged — how many servings is a question, not an
    // assumption, once meals can be whole recipes.
    @State private var savedMealToLog: SavedMeal?

    // When the food was eaten. Logging is always behind eating, and the plan
    // reads the log's clock time, so this is asked here once and stamped on
    // everything this screen adds — rather than being corrected food by food
    // afterwards.
    @State private var eatenAt: Date
    /// False until the time is touched, so switching meals can still move it.
    @State private var timePicked = false
    @State private var showTimePicker = false

    init(day: DayLog, meal: Meal = .suggested()) {
        self.day = day
        _meal = State(initialValue: meal)
        _eatenAt = State(initialValue: Self.defaultTime(for: meal, on: day.date))
    }

    /// Now, on today. On any other day "now" is meaningless, so a back-filled
    /// log lands at the meal's usual hour instead.
    private static func defaultTime(for meal: Meal, on day: Date) -> Date {
        let cal = Calendar.current
        guard !cal.isDateInToday(day) else { return Date() }
        return cal.date(bySettingHour: meal.typicalMinutesOfDay / 60,
                        minute: meal.typicalMinutesOfDay % 60,
                        second: 0, of: cal.startOfDay(for: day)) ?? day
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
                            if !timePicked {
                                eatenAt = Self.defaultTime(for: m, on: day.date)
                            }
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

                // Eaten *when*. Collapsed to a line until it's needed — the
                // common case is "just now" and shouldn't cost a tap — but
                // logging lunch at three in the afternoon has to be able to
                // say so, or the plan moves lunch to three.
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showTimePicker.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .foregroundStyle(Theme.foodTint)
                        Text("Eaten at")
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(timeLabel)
                            .foregroundStyle(.secondary)
                        Image(systemName: showTimePicker ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("food.time.toggle")

                if showTimePicker {
                    // The flag is set in the binding rather than in an
                    // `onChange`: switching meals moves the time too, and that
                    // isn't the user picking one.
                    DatePicker("Eaten at",
                               selection: Binding(get: { eatenAt },
                                                  set: { eatenAt = $0; timePicked = true }),
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    if timePicked {
                        Button {
                            timePicked = false
                            eatenAt = Self.defaultTime(for: meal, on: day.date)
                        } label: {
                            Label(Calendar.current.isDateInToday(day.date)
                                    ? "Back to right now"
                                    : "Back to the usual \(meal.label.lowercased()) time",
                                  systemImage: "arrow.uturn.backward")
                                .font(.caption)
                        }
                    }
                }
            } header: {
                SectionHeader(icon: "fork.knife", title: "Logging to", tint: Theme.foodTint)
            } footer: {
                Text(timeFooter)
            }

            if query.isEmpty {
                // ===== Headline paths: describe it or shoot it — equal billing
                Section {
                    Button { showDescribe = true } label: {
                        headlineLabel(icon: "sparkles",
                                      title: "Describe Your Meal",
                                      subtitle: "Type or dictate what you ate — get every item with full nutrition")
                    }
                    .buttonStyle(.pressable)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.gradient)
                    )
                }
                Section {
                    Button { showFoodCamera = true } label: {
                        headlineLabel(icon: "camera.viewfinder",
                                      title: "Photo of Food",
                                      subtitle: "Point at the plate — every item identified and estimated")
                    }
                    .buttonStyle(.pressable)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.foodTint, Theme.photoTint],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                }
                Section {
                    Button { showRecipeLink = true } label: {
                        headlineLabel(icon: "link",
                                      title: "Recipe from a Link",
                                      subtitle: "Paste a recipe page or video — get every ingredient, per serving")
                    }
                    .buttonStyle(.pressable)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.photoTint, Theme.accent],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                }

                // ===== Saved meals: whole combos, one tap
                if !savedMeals.isEmpty {
                    Section {
                        ForEach(savedMeals) { saved in
                            Button {
                                // One serving is the common case, so a single
                                // tap still logs — but a recipe that makes six
                                // needs asking, and asking once beats editing
                                // six food rows afterwards.
                                if saved.isRecipe {
                                    savedMealToLog = saved
                                } else {
                                    logSavedMeal(saved)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 5) {
                                            Text(saved.name).lineLimit(1).foregroundStyle(.primary)
                                            if saved.isRecipe {
                                                Image(systemName: "book.closed.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(Theme.foodTint)
                                            }
                                        }
                                        Text("\(saved.items.count) item\(saved.items.count == 1 ? "" : "s") · \(saved.servingSummary)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: saved.isRecipe ? "slider.horizontal.3" : "plus.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.borderless)
                            // Every saved meal can be portioned, not just the
                            // ones that arrived as recipes: a meal you cooked
                            // double of becomes a batch by saying so here.
                            .contextMenu {
                                Button {
                                    savedMealToLog = saved
                                } label: {
                                    Label("Portion or batch size…", systemImage: "slider.horizontal.3")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    savedMealToLog = saved
                                } label: {
                                    Label("Portion", systemImage: "slider.horizontal.3")
                                }
                                .tint(Theme.foodTint)
                            }
                        }
                        .onDelete { idx in
                            idx.map { savedMeals[$0] }.forEach { context.delete($0) }
                            try? context.save()
                        }
                    } header: {
                        SectionHeader(icon: "bookmark.fill", title: "Saved Meals", tint: Theme.accent)
                    } footer: {
                        Text("Whole meals you saved — tap to log every item at once. A batch asks how much of it you're eating: servings, a fraction, or a percentage. Long-press any of them to portion it or fix what the batch makes; swipe to remove.")
                    }
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
                    Search covers ~3M crowd-sourced products (Open Food Facts). No internet? Custom Food takes manual numbers.

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
        .sheet(item: $savedMealToLog) { saved in
            SavedMealServingsSheet(saved: saved, mealLabel: meal.label) { servings in
                logSavedMeal(saved, servings: servings)
            }
            .themedRoot()
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
                capturedPlate = CapturedPlate(image: image)
            }
        }
        .sheet(isPresented: $showRecipeLink) {
            RecipeImportView(mealLabel: meal.label) { logs in
                logs.forEach { add($0) }
                dismiss()
            }
            .themedRoot()
        }
        .sheet(item: $capturedPlate) { plate in
            // Photo goes through the same itemized review as Describe —
            // per-component items, portion steppers, editable numbers.
            DescribeMealView(mealLabel: meal.label, photo: plate.image) { logs in
                logs.forEach { add($0) }
                dismiss()
            }
            .themedRoot()
        }
        .alert("Product not found", isPresented: Binding(get: { scanError != nil },
                                                         set: { if !$0 { scanError = nil } })) {
            Button("OK") {}
        } message: {
            Text(scanError ?? "")
        }
    }

    private func add(_ log: FoodLog) {
        day.addFood(log, meal: meal, at: eatenAt)
    }

    /// "Just now" beats a clock time nobody has to read.
    private var timeLabel: String {
        if !timePicked, Calendar.current.isDateInToday(day.date) { return "Just now" }
        return eatenAt.formatted(date: .omitted, time: .shortened)
    }

    private var timeFooter: String {
        if timePicked {
            return "Everything you add here lands at \(eatenAt.formatted(date: .omitted, time: .shortened)) — the plan reads that time, so logging late doesn't drag the rest of the day with it."
        }
        return Calendar.current.isDateInToday(day.date)
            ? "Logging late? Set the time you actually ate and the day plan keeps its shape."
            : "Back-filling an earlier day — food lands at the usual \(meal.label.lowercased()) time unless you set one."
    }

    /// Shared look for the two headline buttons so describing and shooting
    /// a meal carry equal weight.
    private func headlineLabel(icon: String, title: String, subtitle: String,
                               busy: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.bold())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.9)
            }
            Spacer()
            if busy {
                ProgressView().tint(.white)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .opacity(0.7)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 14)
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

    /// Logs a saved meal into the selected meal. `servings` is the number of
    /// servings being eaten, which for a recipe is usually not the batch.
    private func logSavedMeal(_ saved: SavedMeal, servings: Double = 1) {
        saved.makeLogs(servings: servings, meal: nil).forEach { add($0) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
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

}

/// Identifiable wrapper so the photo-review sheet always sees a fresh image.
private struct CapturedPlate: Identifiable {
    let id = UUID()
    let image: UIImage
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
    /// Whether the estimate came from a live web lookup (nil until one runs).
    @State private var groundedResult: Bool?
    /// Portion multiplier vs the assumed serving — stepping it rescales
    /// calories, protein, grams, and the full panel in place (by ratio, so
    /// it composes with manual edits).
    @State private var servings = 1.0

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
                        HStack(alignment: .top) {
                            Text("Assumed: \(assumedText)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let g = groundedResult {
                                GroundingBadge(grounded: g)
                            }
                        }
                    }
                } footer: {
                    Text(AIFoodEstimator.apiKey.isEmpty
                         ? "Add an API key in Settings → About Estimates to auto-fill the full nutrition panel from the name."
                         : estimated
                            ? "Estimated for one typical serving — if that's not what you meant, refine the name and estimate again."
                            : "Estimates one typical serving: calories, protein, fats, sodium, and more.")
                }
                if calories > 0 {
                    Stepper(value: $servings, in: 0.25...10, step: 0.25) {
                        HStack(spacing: 6) {
                            Text("Portion")
                            Spacer()
                            Text("\(servings.formatted())×\(grams.map { " · \(Int($0)) g" } ?? "")")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: servings) { old, new in
                        guard old > 0 else { return }
                        let f = new / old
                        calories = Int((Double(calories) * f).rounded())
                        if !proteinUnknown { protein = Int((Double(protein) * f).rounded()) }
                        grams = grams.map { $0 * f }
                        facts = facts.scaled(by: f)
                    }
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
            servings = 1
            assumedText = result.assumed
            groundedResult = result.grounded
        } catch {
            estimateError = error.localizedDescription
        }
    }
}


// MARK: - Servings

/// How much of a saved meal is actually being eaten.
///
/// A meal snapshotted from a day's log is one serving and barely needs this
/// screen. A batch is a different object: the stored numbers are the whole
/// tray, and logging it without asking would put four dinners into one
/// evening. Everything scales together — calories, protein, and the full
/// micronutrient panel — so the iron and fiber in a third of a pot of chili
/// are a third of the pot's.
///
/// Two ways in, because meal prep is logged both ways in real life: the tray
/// you cut into four is *servings*, and the container you ate half of is a
/// *percentage*. Neither should require arithmetic, and the yield itself is
/// editable here — a recipe that said four but really fed six is a correction,
/// not a reason to re-import anything.
struct SavedMealServingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let saved: SavedMeal
    let mealLabel: String
    let onLog: (Double) -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case servings, percent
        var id: String { rawValue }
        var label: String { self == .servings ? "Servings" : "% of batch" }
    }

    @State private var mode: Mode = .servings
    @State private var servings: Double = 1
    @State private var percent: Double = 25
    @State private var editingYield = false

    /// The single source of truth: whichever control is on screen resolves to
    /// a number of servings, and everything below is scaled from that.
    private var loggedServings: Double {
        mode == .servings ? servings : saved.servings(forPercent: percent)
    }

    private var factor: Double { saved.factor(forServings: loggedServings) }
    private var calories: Int { Int((Double(saved.totalCalories) * factor).rounded()) }
    private var protein: Int { Int((Double(saved.totalProtein) * factor).rounded()) }
    private var facts: NutritionFacts { saved.totalFacts.scaled(by: factor) }

    /// Servings left in the batch after this portion, when there's a yield
    /// worth tracking — the actual question on a Wednesday.
    private var remaining: Double { max(0, saved.servings - loggedServings) }

    var body: some View {
        NavigationStack {
            Form {
                // --- What this batch is
                Section {
                    HStack {
                        Text("The batch")
                        Spacer()
                        Text("\(saved.totalCalories) cal · \(saved.totalProtein) g protein")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { editingYield.toggle() }
                    } label: {
                        HStack {
                            Text("Makes").foregroundStyle(.primary)
                            Spacer()
                            Text("\(saved.servings.formatted()) serving\(saved.servings == 1 ? "" : "s") · \(saved.caloriesPerServing) cal each")
                                .foregroundStyle(.secondary)
                            Image(systemName: editingYield ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(Theme.textDim)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if editingYield {
                        Stepper(value: Binding(get: { saved.servings },
                                               set: { saved.setServings($0) }),
                                in: 1...48, step: 1) {
                            HStack {
                                Text("Servings in the batch")
                                Spacer()
                                Text(saved.servings.formatted()).foregroundStyle(.secondary)
                            }
                        }
                        Text("Fixing the yield doesn't change the batch — it changes what one serving is, here and everywhere else this meal is logged.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(saved.name)
                }

                // --- How much of it
                Section {
                    Picker("How to measure", selection: $mode) {
                        ForEach(Mode.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)

                    if mode == .servings {
                        Stepper(value: $servings,
                                in: 0.25...max(1, saved.servings * 2), step: 0.25) {
                            HStack {
                                Text("Eating")
                                Spacer()
                                Text("\(servings.formatted()) serving\(servings == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        // The fractions people actually eat, without hunting
                        // the stepper for eight taps.
                        HStack(spacing: 8) {
                            fractionButton("¼", of: 0.25)
                            fractionButton("⅓", of: 1.0 / 3)
                            fractionButton("½", of: 0.5)
                            fractionButton("All", of: 1)
                        }
                        .padding(.vertical, 2)
                    } else {
                        Stepper(value: $percent, in: 5...200, step: 5) {
                            HStack {
                                Text("Eating")
                                Spacer()
                                Text("\(Int(percent))% of the batch")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 8) {
                            percentButton(10)
                            percentButton(25)
                            percentButton(50)
                            percentButton(100)
                        }
                        .padding(.vertical, 2)
                    }

                    HStack {
                        Text("That's")
                        Spacer()
                        Text("\(calories) cal · \(protein) g protein")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.foodTint)
                    }
                    HStack {
                        Text(mode == .servings ? "Which is" : "About")
                        Spacer()
                        Text(mode == .servings
                             ? "\(Int(saved.percent(forServings: servings).rounded()))% of the batch"
                             : "\(loggedServings.formatted(.number.precision(.fractionLength(0...2)))) serving\(loggedServings == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("How Much")
                } footer: {
                    Text(remaining > 0
                         ? "\(remaining.formatted(.number.precision(.fractionLength(0...2)))) serving\(remaining == 1 ? "" : "s") left in the batch after this — about \(Int((Double(saved.totalCalories) * (remaining / max(0.25, saved.servings))).rounded())) cal still in the fridge."
                         : "That's the whole batch.")
                }

                // --- What's in it
                Section {
                    ForEach(saved.orderedItems) { item in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(2)
                                if let g = item.grams, g > 0 {
                                    Text("\(Int((g * factor).rounded())) g")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(Int((Double(item.calories) * factor).rounded())) cal")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("In This Portion")
                }

                Section("Nutrition — This Portion") {
                    NutritionFactsRows(facts: facts, compact: true)
                }

                if let source = saved.sourceURL, let link = URL(string: source), !source.isEmpty {
                    Section {
                        Link(destination: link) {
                            Label("Open the recipe", systemImage: "link")
                        }
                    }
                }

                Section {
                    Button {
                        onLog(loggedServings)
                        dismiss()
                    } label: {
                        Text("Log to \(mealLabel) — \(calories) cal")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(calories <= 0)
                }
            }
            .themedForm()
            .navigationTitle("How Much?")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { servings = min(1, saved.servings) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func fractionButton(_ title: String, of share: Double) -> some View {
        let value = (saved.servings * share * 4).rounded() / 4
        return Button {
            servings = max(0.25, value)
        } label: {
            Text(title)
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Capsule().fill(Theme.foodTint.opacity(0.15)))
                .foregroundStyle(Theme.foodTint)
        }
        .buttonStyle(.plain)
    }

    private func percentButton(_ value: Double) -> some View {
        Button {
            percent = value
        } label: {
            Text("\(Int(value))%")
                .font(.caption.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Capsule().fill(Theme.foodTint.opacity(0.15)))
                .foregroundStyle(Theme.foodTint)
        }
        .buttonStyle(.plain)
    }
}
