import SwiftUI
import SwiftData

/// Everything eaten in one meal — tap a food for its full nutrition,
/// swipe to remove it, add more, fix when it was eaten, or delete the whole
/// meal from the toolbar.
struct MealDetailView: View {
    @Environment(\.dismiss) private var dismiss
    var day: DayLog
    let meal: Meal?
    let label: String
    let icon: String

    @Environment(\.modelContext) private var context
    @State private var inspectedFood: FoodLog?
    @State private var confirmDeleteMeal = false

    // "Save as Meal" — name, batch yield, then a reusable snapshot
    @State private var showSavePrompt = false
    @State private var savedToast = false

    // Moving the whole meal to when it was actually eaten
    @State private var showTimePicker = false
    @State private var mealTime = Date()

    private var foods: [FoodLog] { day.foods(for: meal) }
    private var calories: Int { foods.reduce(0) { $0 + $1.calories } }
    private var protein: Int { foods.reduce(0) { $0 + $1.proteinGrams } }

    var body: some View {
        Form {
            Section {
                HStack {
                    SectionIcon(systemImage: icon, tint: meal?.color ?? Theme.foodTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label).font(.headline)
                        Text("\(calories) cal · \(protein) g protein")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // When the meal happened, not when it got typed in. The day
                // plan moves a meal to its logged time and pushes everything
                // after it along, so "logged at three, eaten at one" has to be
                // a correction you can make to the whole meal at once.
                if !foods.isEmpty {
                    Button {
                        mealTime = foods.first?.occurredAt ?? Date()
                        withAnimation(.easeInOut(duration: 0.2)) { showTimePicker.toggle() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .foregroundStyle(meal?.color ?? Theme.foodTint)
                            Text("Eaten at").foregroundStyle(.primary)
                            Spacer()
                            Text(timeSpan).foregroundStyle(.secondary)
                            Image(systemName: showTimePicker ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                                .foregroundStyle(Theme.textDim)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal.time.toggle")
                    if showTimePicker {
                        DatePicker("Eaten at", selection: $mealTime,
                                   displayedComponents: .hourAndMinute)
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        Button {
                            day.setMealTime(meal, to: mealTime)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.easeInOut(duration: 0.2)) { showTimePicker = false }
                        } label: {
                            Label("Move \(label) to \(mealTime.formatted(date: .omitted, time: .shortened))",
                                  systemImage: "clock.arrow.circlepath")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            Section {
                ForEach(foods) { f in
                    Button { inspectedFood = f } label: {
                        HStack(spacing: 8) {
                            if let d = FoodDensity(rawValue: f.density ?? "") {
                                Circle().fill(d.color).frame(width: 9, height: 9)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name).lineLimit(1).foregroundStyle(.primary)
                                Text(subtitle(f))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(f.calories) cal").foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { foods[$0] }.forEach { day.removeFood($0) }
                }
                if let meal {
                    NavigationLink {
                        FoodSearchView(day: day, meal: meal)
                    } label: {
                        Label("Add to \(label)", systemImage: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            } footer: {
                Text("Tap a food for its full nutrition · swipe to remove it.")
            }
            if !foods.isEmpty {
                Section {
                    Button {
                        showSavePrompt = true
                    } label: {
                        Label(savedToast ? "Saved — find it in Add Food" : "Save as Meal",
                              systemImage: savedToast ? "checkmark.circle.fill" : "bookmark.fill")
                            .foregroundStyle(savedToast ? .green : Theme.accent)
                    }
                    .disabled(savedToast)
                } footer: {
                    Text("Eat this combo often? Save it once and re-log the whole thing with one tap next time. Cooked a batch? Say how many servings it makes and logging a portion of it is a stepper from then on.")
                }
            }
            Section {
                Button(role: .destructive) {
                    confirmDeleteMeal = true
                } label: {
                    Label("Delete \(label)", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .themedForm()
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    confirmDeleteMeal = true
                } label: {
                    Image(systemName: "trash")
                }
                .tint(Theme.danger)
            }
        }
        .confirmationDialog("Delete \(label)?", isPresented: $confirmDeleteMeal,
                            titleVisibility: .visible) {
            Button("Delete \(foods.count) item\(foods.count == 1 ? "" : "s")",
                   role: .destructive) {
                day.removeMeal(meal)
                dismiss()
            }
        } message: {
            Text("Removes everything logged under \(label) for this day.")
        }
        .sheet(item: $inspectedFood) { FoodNutritionSheet(food: $0) }
        .sheet(isPresented: $showSavePrompt) {
            SaveAsMealSheet(defaultName: label, itemCount: foods.count,
                            calories: calories, defaultMeal: meal) { name, servings in
                saveMeal(name: name, servings: servings)
            }
            .themedRoot()
        }
    }

    /// The meal's clock time — a single time, or the span it was eaten over.
    private var timeSpan: String {
        guard let first = foods.first?.timeString else { return "—" }
        guard let last = foods.last?.timeString, last != first else { return first }
        return "\(first) – \(last)"
    }

    /// Snapshot this meal's foods into a reusable SavedMeal.
    ///
    /// `servings` is what the snapshot *makes*, not what was eaten: a batch
    /// cooked on Sunday and logged whole is one save that four dinners come
    /// out of, and storing the yield is what turns next time into a stepper.
    private func saveMeal(name: String, servings: Double) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let saved = SavedMeal(name: trimmed, servings: servings, defaultMeal: meal)
        for (i, f) in foods.enumerated() {
            saved.items.append(SavedMealItem(food: f, orderIndex: i))
        }
        context.insert(saved)
        try? context.save()
        savedToast = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { savedToast = false }
    }

    private func subtitle(_ f: FoodLog) -> String {
        var parts: [String] = [f.timeString]
        if let g = f.grams { parts.append("\(Int(g)) g") }
        if f.proteinGrams > 0 { parts.append("\(f.proteinGrams) g protein") }
        if f.source == "barcode" { parts.append("scanned") }
        if f.source == "ai" { parts.append("estimated") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Saving a meal (and a batch)

/// Name it, and say how much of it this is.
///
/// A meal snapshotted off one day's log is usually one serving, and the sheet
/// stays out of the way in that case. Meal prep is the other case and the
/// reason this isn't a one-line alert any more: you cook a tray of chicken and
/// rice on Sunday, log the whole tray once, and save it as *four* servings.
/// From then on Add Food hands you a stepper and a percentage instead of
/// arithmetic.
struct SaveAsMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    let defaultName: String
    let itemCount: Int
    let calories: Int
    let defaultMeal: Meal?
    let onSave: (String, Double) -> Void

    @State private var name = ""
    @State private var servings: Double = 1
    @FocusState private var nameFocused: Bool

    private var perServing: Int { Int((Double(calories) / max(0.25, servings)).rounded()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Sunday chicken and rice)", text: $name)
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Saves these \(itemCount) item\(itemCount == 1 ? "" : "s") — \(calories) cal in total — for one-tap logging from Add Food.")
                }

                Section {
                    Stepper(value: $servings, in: 1...24, step: 1) {
                        HStack {
                            Text("Makes")
                            Spacer()
                            Text("\(servings.formatted()) serving\(servings == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Each serving")
                        Spacer()
                        Text("\(perServing) cal")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.foodTint)
                    }
                } header: {
                    Text("Batch Size")
                } footer: {
                    Text(servings > 1
                         ? "Stored as the whole batch. Next time, logging a portion is a stepper — servings or a percentage of the batch — and every number, micronutrients included, scales with it."
                         : "One serving — the usual case for a meal you just ate. Cooked a batch? Step this up to what it makes.")
                }

                Section {
                    Button {
                        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), servings)
                        dismiss()
                    } label: {
                        Text(servings > 1
                             ? "Save as a \(servings.formatted())-serving batch"
                             : "Save the Meal")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .themedForm()
            .keyboardDoneButton()
            .navigationTitle("Save as Meal")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if name.isEmpty { name = defaultName }
                nameFocused = true
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Gemini end-of-day review

/// Shared coach-review sheet: headline, wins, and swap suggestions.
/// Backs both "Summarize My Day" and the weekly report — pass the call.
struct CoachReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let run: () async throws -> AIFoodEstimator.DayReview

    @State private var review: AIFoodEstimator.DayReview?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let review {
                    Section {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Circle().fill(Theme.gradient))
                            Text(review.headline)
                                .font(.headline)
                        }
                        .padding(.vertical, 4)
                    }
                    if !review.wins.isEmpty {
                        Section("What Went Well") {
                            ForEach(review.wins, id: \.self) { win in
                                Label {
                                    Text(win)
                                } icon: {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    if !review.suggestions.isEmpty {
                        Section {
                            ForEach(review.suggestions) { s in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(s.issue)
                                        .font(.subheadline.weight(.semibold))
                                    Label {
                                        Text(s.swap)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    } icon: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        } header: {
                            Text("Try These Swaps")
                        } footer: {
                            Text("Take what's useful, skip what isn't.")
                        }
                    }
                } else if let error {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                        Button {
                            self.error = nil
                            Task { await load() }
                        } label: {
                            Label("Try Again", systemImage: "arrow.clockwise")
                        }
                    }
                } else {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking everything over…").foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .themedForm()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard review == nil else { return }
        do {
            review = try await run()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
