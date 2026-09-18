import SwiftUI
import SwiftData

/// Where you shop and what you won't eat.
///
/// Meal suggestions are only worth anything if the ingredients are buyable
/// and the food is edible — to you specifically. Without this, ideas drift
/// toward a generic idea of healthy eating: fresh branzino for someone whose
/// nearest store is an Aldi, a salmon bowl for someone who can't stand fish.
///
/// The exclusion list is enforced twice on purpose. It goes into the prompt
/// as a hard rule, and anything naming an excluded food is dropped locally
/// before it reaches the screen — a dislike list that holds four times out of
/// five is worse than no list at all, because you stop trusting the feature.
struct FoodPreferencesView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan

    @State private var newStore = ""
    @State private var newDislike = ""

    private var storeSuggestions: [String] {
        FoodPreferences.commonStores.filter { store in
            !plan.preferredStores.contains { $0.caseInsensitiveCompare(store) == .orderedSame }
        }
    }

    private var dislikeSuggestions: [String] {
        FoodPreferences.commonDislikes.filter { food in
            !plan.dislikedFoods.contains { $0.caseInsensitiveCompare(food) == .orderedSame }
        }
    }

    var body: some View {
        Form {
            // ===== Stores
            Section {
                ForEach(plan.preferredStores, id: \.self) { store in
                    Label(store, systemImage: "cart.fill")
                }
                .onDelete { offsets in
                    plan.preferredStores.remove(atOffsets: offsets)
                    save()
                }

                HStack {
                    TextField("Add a store", text: $newStore)
                        .textInputAutocapitalization(.words)
                        .onSubmit { addStore(newStore) }
                    Button {
                        addStore(newStore)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newStore.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Where you shop")
            } footer: {
                Text("Meal ideas stick to things you can actually buy at these stores, and name the store when it's relevant. Leave it empty and suggestions stay generic.")
            }

            if !storeSuggestions.isEmpty {
                Section {
                    ChipFlow(items: Array(storeSuggestions.prefix(12)), tint: Theme.foodTint) {
                        addStore($0)
                    }
                } header: {
                    Text("Common ones")
                }
            }

            // ===== Exclusions
            Section {
                ForEach(plan.dislikedFoods, id: \.self) { food in
                    Label(food, systemImage: "hand.raised.fill")
                }
                .onDelete { offsets in
                    plan.dislikedFoods.remove(atOffsets: offsets)
                    save()
                }

                HStack {
                    TextField("Add a food to exclude", text: $newDislike)
                        .textInputAutocapitalization(.sentences)
                        .onSubmit { addDislike(newDislike) }
                    Button {
                        addDislike(newDislike)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newDislike.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Never suggest")
            } footer: {
                Text("Dislikes, allergies, anything you're simply not eating — the app doesn't need to know which. Nothing on this list will be suggested, including as a minor ingredient. This only filters suggestions; you can still log whatever you like.")
            }

            if !dislikeSuggestions.isEmpty {
                Section {
                    ChipFlow(items: Array(dislikeSuggestions.prefix(12)), tint: Theme.workoutTint) {
                        addDislike($0)
                    }
                } header: {
                    Text("Common ones")
                }
            }
        }
        .themedForm()
        .keyboardDoneButton()
        .navigationTitle("Food Preferences")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addStore(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !plan.preferredStores.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        plan.preferredStores.append(trimmed)
        newStore = ""
        Haptics.tap()
        save()
    }

    private func addDislike(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !plan.dislikedFoods.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        plan.dislikedFoods.append(trimmed)
        newDislike = ""
        Haptics.tap()
        save()
    }

    private func save() { try? context.save() }
}

/// A wrapping row of tappable chips — the "common ones" shortcuts.
struct ChipFlow: View {
    let items: [String]
    let tint: Color
    let onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 7) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(tint.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Minimal wrapping layout — chips flow onto the next line when they run out
/// of width. `Layout` rather than a stack of rows so it reflows on rotation
/// and Dynamic Type without any width bookkeeping here.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
