import Foundation

/// What to suggest and what never to suggest.
///
/// A meal idea is only useful if the person can actually get the ingredients
/// and would actually eat them. Without this, suggestions drift toward
/// whatever a language model thinks a healthy person eats — which is how you
/// get told to pick up branzino when the nearest store is an Aldi, or handed
/// a salmon bowl by someone who can't stand fish.
///
/// Both lists are plain strings the user typed. They're pushed into the
/// prompt as hard constraints rather than preferences, because "try to avoid"
/// gets ignored roughly a third of the time and a dislike list that doesn't
/// hold is worse than none at all.
struct FoodPreferences: Equatable {
    var stores: [String]
    var dislikes: [String]

    static let empty = FoodPreferences(stores: [], dislikes: [])

    init(stores: [String] = [], dislikes: [String] = []) {
        self.stores = FoodPreferences.clean(stores)
        self.dislikes = FoodPreferences.clean(dislikes)
    }

    init(plan: Plan) {
        self.init(stores: plan.preferredStores, dislikes: plan.dislikedFoods)
    }

    var isEmpty: Bool { stores.isEmpty && dislikes.isEmpty }

    /// Trim, drop blanks, de-duplicate case-insensitively, keep order.
    static func clean(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// The constraint block for a food prompt. Empty string when there's
    /// nothing to say, so callers can interpolate it unconditionally.
    var promptSection: String {
        var lines: [String] = []
        if !stores.isEmpty {
            lines.append("""
            Every ingredient must be something they can buy at one of these \
            stores: \(stores.joined(separator: ", ")). Prefer items these \
            stores are actually known for, and name the store when it's \
            relevant. Do not suggest anything requiring a specialty shop they \
            didn't list.
            """)
        }
        if !dislikes.isEmpty {
            lines.append("""
            Hard exclusions — never suggest these, and never suggest a dish \
            that contains them, including as a minor ingredient or garnish: \
            \(dislikes.joined(separator: ", ")). This is not a preference to \
            weigh against other factors; a suggestion containing any of these \
            is wrong and must be replaced.
            """)
        }
        guard !lines.isEmpty else { return "" }
        return "\n" + lines.joined(separator: "\n")
    }

    /// A short human summary for a settings row.
    var summary: String {
        var parts: [String] = []
        if !stores.isEmpty {
            parts.append("\(stores.count) store\(stores.count == 1 ? "" : "s")")
        }
        if !dislikes.isEmpty {
            parts.append("\(dislikes.count) food\(dislikes.count == 1 ? "" : "s") excluded")
        }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    /// Does anything in this text hit the exclusion list? A cheap local guard
    /// so a suggestion that slips past the prompt never reaches the screen.
    func excludes(_ text: String) -> Bool {
        let haystack = text.lowercased()
        return dislikes.contains { haystack.contains($0.lowercased()) }
    }

    /// Common chains, offered as taps so the list doesn't have to be typed.
    /// Not exhaustive and not meant to be — anything missing is free text.
    static let commonStores = [
        "Aldi", "Costco", "Trader Joe's", "Walmart", "Target", "Kroger",
        "Publix", "Safeway", "H-E-B", "Wegmans", "Whole Foods", "Sprouts",
        "Meijer", "Winco", "Food Lion", "Giant", "Albertsons", "Sam's Club",
        "Local farmers market"
    ]

    /// Starting points for the exclusion list — the things people most often
    /// won't eat, whether from taste, allergy, or diet.
    static let commonDislikes = [
        "Fish", "Shellfish", "Mushrooms", "Cilantro", "Olives", "Eggs",
        "Dairy", "Pork", "Red meat", "Tofu", "Beans", "Spicy food",
        "Blue cheese", "Liver", "Cottage cheese", "Gluten"
    ]
}
