import Foundation
import UIKit

/// Optional AI nutrition estimate for foods that aren't in any database
/// ("mom's lasagna"). Uses the Gemini API free tier with the user's own key
/// (Settings → AI Assist). Nothing is sent anywhere unless the user taps
/// Estimate, and only the food description goes out.
enum AIFoodEstimator {
    static let apiKeyKey = "ai.gemini.key"
    /// Settings → About Estimates "Higher accuracy" toggle. Default is
    /// Flash-Lite (no thinking pass — answers in ~1 s, higher free-tier rate
    /// limit); accurate mode trades that speed for full Flash's better
    /// numbers on complex meals.
    static let accurateModelKey = "ai.model.accurate"

    private static var model: String {
        UserDefaults.standard.bool(forKey: accurateModelKey)
            ? "gemini-flash-latest" : "gemini-flash-lite-latest"
    }

    /// A key entered in Settings wins; otherwise the one bundled from
    /// Resources/Secrets.plist (git-ignored, so it never leaves this machine).
    static var apiKey: String {
        let user = UserDefaults.standard.string(forKey: apiKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return user.isEmpty ? bundledKey : user
    }

    /// True when the key in play came from Settings rather than the bundle.
    static var usingUserKey: Bool {
        let user = UserDefaults.standard.string(forKey: apiKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !user.isEmpty && user != bundledKey
    }

    static let bundledKey: String = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return "" }
        return (dict["GeminiAPIKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    struct Estimate {
        let name: String
        let calories: Int
        let proteinGrams: Int
        let grams: Double?         // estimated portion weight
        let facts: NutritionFacts
        let density: String?       // computed locally from kcal ÷ grams
        let assumed: String        // what food + serving the model based this on
        let grounded: Bool         // numbers came from a live web lookup
    }

    struct ProteinEstimate {
        let gramsPer100g: Double
        let assumed: String
    }

    struct MealItem: Identifiable {
        let id = UUID()
        var name: String
        var calories: Int
        var proteinGrams: Int
        var grams: Double?
        var facts: NutritionFacts
        var density: String?
        var assumed: String?       // portion assumption for THIS item

        /// Recompute the density bucket after the user edits values.
        mutating func refreshDensity() {
            guard let grams, grams > 0, calories > 0 else { return }
            density = FoodDensity(caloriesPer100g: Double(calories) / grams * 100)?.rawValue
        }

        /// The same food at a different portion size — every stat scales
        /// linearly. Density is per-gram, so it stays put.
        func scaled(by factor: Double) -> MealItem {
            var copy = self
            copy.calories = Int((Double(calories) * factor).rounded())
            copy.proteinGrams = Int((Double(proteinGrams) * factor).rounded())
            copy.grams = grams.map { $0 * factor }
            copy.facts = facts.scaled(by: factor)
            return copy
        }
    }

    struct MealBreakdown {
        let items: [MealItem]
        let assumed: String
        let grounded: Bool         // numbers came from a live web lookup
    }

    struct RecipeBreakdown {
        let title: String
        let items: [MealItem]      // nutrition for the WHOLE recipe as written
        let servings: Int          // how many servings the whole recipe yields
        let assumed: String
        let note: String           // e.g. "couldn't fully read the link" (may be empty)
        let grounded: Bool
    }

    /// The full nutrition panel every food estimate asks for. Density is NOT
    /// requested — the model was unreliable at bucketing it (large pancakes
    /// came back "green"), so it's computed locally from kcal ÷ grams.
    private static let nutritionSchema = """
    "portion_grams": <number, estimated weight of this exact portion in grams>, \
    "calories": <integer kcal for the portion>, \
    "protein_g": <number g>, "carbs_g": <number g>, "fat_g": <number g>, \
    "saturated_fat_g": <number g>, "trans_fat_g": <number g>, \
    "cholesterol_mg": <number mg>, "sodium_mg": <number mg>, \
    "fiber_g": <number g>, "sugar_g": <number g, total sugars>, \
    "added_sugar_g": <number g>, "potassium_mg": <number mg>, \
    "calcium_mg": <number mg>, "iron_mg": <number mg>
    """

    private static let nutritionGuidance = """
    Act like a careful nutrition coach. Estimate realistic, typical \
    portion sizes — do NOT inflate them; assume an average adult serving \
    unless the description clearly says otherwise. Base every value on \
    USDA-style nutrition data and aim for the accurate middle of the \
    plausible range, not the high end — most estimates come back too high, \
    so round toward the honest number rather than padding for safety. \
    Include cooking fats and condiments that are actually present, but \
    don't add extras that probably aren't there. \
    When a restaurant, chain, or packaged brand is named — or the dish is \
    clearly from one — search for and use that restaurant's or brand's \
    published nutrition numbers instead of generic estimates, and say so \
    in "assumed".
    """

    /// One food item's nutrition panel as Gemini returns it.
    private struct FoodPayload: Decodable {
        let name: String?
        let assumed: String?
        let portion_grams: Double?
        let calories: Int?
        let protein_g: Double?
        let carbs_g: Double?
        let fat_g: Double?
        let saturated_fat_g: Double?
        let trans_fat_g: Double?
        let cholesterol_mg: Double?
        let sodium_mg: Double?
        let fiber_g: Double?
        let sugar_g: Double?
        let added_sugar_g: Double?
        let potassium_mg: Double?
        let calcium_mg: Double?
        let iron_mg: Double?

        var facts: NutritionFacts {
            NutritionFacts(carbsGrams: carbs_g ?? 0,
                           fatGrams: fat_g ?? 0,
                           saturatedFatGrams: saturated_fat_g ?? 0,
                           transFatGrams: trans_fat_g ?? 0,
                           cholesterolMg: cholesterol_mg ?? 0,
                           sodiumMg: sodium_mg ?? 0,
                           fiberGrams: fiber_g ?? 0,
                           sugarGrams: sugar_g ?? 0,
                           addedSugarGrams: added_sugar_g ?? 0,
                           potassiumMg: potassium_mg ?? 0,
                           calciumMg: calcium_mg ?? 0,
                           ironMg: iron_mg ?? 0)
        }

        var density: String? {
            guard let calories, let grams = portion_grams, grams > 0 else { return nil }
            return FoodDensity(caloriesPer100g: Double(calories) / grams * 100)?.rawValue
        }
    }

    /// "Describe your meal" — plain text (typed or dictated) in, itemized
    /// estimate out.
    static func mealBreakdown(description: String) async throws -> MealBreakdown {
        struct Payload: Decodable {
            let items: [FoodPayload]?
            let assumed: String?
        }
        let prompt = """
        Break this meal description into separate food items and estimate the \
        full nutrition of each. \(nutritionGuidance)
        List EVERY distinct component or ingredient as its own item — never \
        merge two ingredients into one line. Oils, butter, cheeses, sauces, \
        and dressings each get their own item (feta and cream cheese are two \
        items; olive oil is never folded into the vegetables it's on). If the \
        user names an ingredient, it must appear as its own item.
        Meal: "\(description)"
        Respond with only JSON:
        {"items": [{"name": "<short item name>", \
        "assumed": "<short: the exact portion you assumed for this item, e.g. '2 tbsp, drizzled over the salad'>", \
        \(nutritionSchema)}], \
        "assumed": "<one short sentence: overall assumptions about the meal>"}
        """
        let (payload, grounded): (Payload, Bool) =
            try await generateGrounded(parts: [["text": prompt]])
        let items = mealItems(from: payload.items ?? [])
        guard !items.isEmpty else { throw EstimatorError.badResponse }
        return MealBreakdown(items: items, assumed: payload.assumed ?? "", grounded: grounded)
    }

    /// "Photo of Food" — same itemized breakdown as the text path, from a
    /// picture of the plate plus whatever notes the photo can't show
    /// (brand, cooking oil, portion context).
    static func mealBreakdown(photo: UIImage, notes: String = "") async throws -> MealBreakdown {
        struct Payload: Decodable {
            let items: [FoodPayload]?
            let assumed: String?
        }
        guard let jpeg = downscaledJPEG(photo) else { throw EstimatorError.badResponse }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesLine = trimmedNotes.isEmpty ? "" : "\nThe user adds: \"\(trimmedNotes)\"."
        let prompt = """
        Identify every distinct food in this photo and estimate the full \
        nutrition of each from the portions shown. \(nutritionGuidance)
        List EVERY distinct component as its own item — never merge two \
        foods into one line; sauces, dressings, sides, and drinks each get \
        their own item.\(notesLine)
        Respond with only JSON:
        {"items": [{"name": "<short item name>", \
        "assumed": "<short: what you identified and the portion you assumed>", \
        \(nutritionSchema)}], \
        "assumed": "<one short sentence: overall assumptions about the plate>"}
        If there is no food in the photo, use {"items": []}.
        """
        let parts: [[String: Any]] = [
            ["text": prompt],
            ["inline_data": ["mime_type": "image/jpeg",
                             "data": jpeg.base64EncodedString()]]
        ]
        let (payload, grounded): (Payload, Bool) = try await generateGrounded(parts: parts)
        let items = mealItems(from: payload.items ?? [])
        guard !items.isEmpty else { throw EstimatorError.badResponse }
        return MealBreakdown(items: items, assumed: payload.assumed ?? "", grounded: grounded)
    }

    /// "Paste a link" — read a recipe from a web page or video URL and break
    /// the WHOLE recipe into ingredients with nutrition, plus how many
    /// servings it yields (the UI divides down to the servings you log).
    /// Uses Gemini's URL-reading (`url_context`) for pages and native video
    /// understanding for YouTube; short-form video (TikTok/Instagram) is
    /// best-effort — when the link can't be read, `note` says so.
    static func recipeBreakdown(url: String) async throws -> RecipeBreakdown {
        struct Payload: Decodable {
            let title: String?
            let servings: Int?
            let items: [FoodPayload]?
            let assumed: String?
            let note: String?
        }
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: trimmed),
              parsed.scheme?.hasPrefix("http") == true else {
            throw EstimatorError.badLink
        }
        let host = (parsed.host ?? "").lowercased()
        let isYouTube = host.contains("youtube.com") || host.contains("youtu.be")

        let videoLine = isYouTube
            ? "This is a video — watch it and read its on-screen text, title, and description, and use the top comments to pin down exact quantities."
            : "Read the page. If it's a video post, use its caption, description, and top comments to pin down exact quantities."
        let prompt = """
        The user pasted a link to a recipe. \(videoLine) Get the ingredient \
        list and quantities as precisely as you can, then break the FULL \
        recipe (as written, not one serving) into its ingredients and \
        estimate the nutrition of each. \(nutritionGuidance)
        List EVERY ingredient as its own item — never merge two ingredients \
        into one line; oils, butter, and sauces each get their own item. \
        Base each item on the amount used in the WHOLE recipe.
        Also report how many servings the whole recipe makes.
        Link: \(trimmed)
        Respond with only JSON:
        {"title": "<recipe name>", \
        "servings": <integer: how many servings the whole recipe yields, best estimate, at least 1>, \
        "items": [{"name": "<ingredient>", \
        "assumed": "<short: the amount used in the whole recipe, e.g. '2 cups, ~250 g'>", \
        \(nutritionSchema)}], \
        "assumed": "<one short sentence: overall assumptions about the recipe>", \
        "note": "<if you could NOT read the link, say so in a few words; otherwise empty>"}
        If you cannot read the link at all, use {"items": [], "note": "<why>"}.
        """
        var parts: [[String: Any]] = [["text": prompt]]
        if isYouTube {
            parts.append(["file_data": ["file_uri": trimmed]])
        }
        // url_context reads the page; google_search lets it cross-check brand
        // or packaged-ingredient nutrition. Recipe import always uses the
        // fuller model — it's an occasional, get-it-right action.
        let tools: [[String: Any]] = [["url_context": [String: String]()],
                                      ["google_search": [String: String]()]]
        let payload: Payload = try await generateTooled(parts: parts, tools: tools,
                                                        modelName: "gemini-flash-latest")
        let items = mealItems(from: payload.items ?? [])
        guard !items.isEmpty else {
            let why = (payload.note?.isEmpty == false) ? payload.note! : nil
            throw EstimatorError.linkUnread(why)
        }
        return RecipeBreakdown(title: payload.title ?? "Recipe",
                               items: items,
                               servings: max(1, payload.servings ?? 1),
                               assumed: payload.assumed ?? "",
                               note: payload.note ?? "",
                               grounded: true)
    }

    private static func mealItems(from payloads: [FoodPayload]) -> [MealItem] {
        payloads.compactMap { p -> MealItem? in
            guard let name = p.name, !name.isEmpty, let calories = p.calories else { return nil }
            return MealItem(name: name, calories: calories,
                            proteinGrams: Int((p.protein_g ?? 0).rounded()),
                            grams: p.portion_grams,
                            facts: p.facts,
                            density: p.density,
                            assumed: p.assumed)
        }
    }

    struct DayReview {
        struct Suggestion: Identifiable {
            let id = UUID()
            let issue: String
            let swap: String
        }
        let headline: String       // one-line verdict on the day
        let wins: [String]
        let suggestions: [Suggestion]
    }

    /// Bare lab numbers for lab-aware coaching — values only, nothing
    /// identifying, and only sent when the user has the toggle on.
    struct LabSnapshot {
        let ldl: Double?
        let hdl: Double?
        let triglycerides: Double?
        let fastingGlucose: Double?
        let a1c: Double?
        let ferritin: Double?
        let hemoglobin: Double?
        let transferrinSaturation: Double?
        /// Set when the local iron reading says this is worth steering food
        /// toward — it turns a number in a list into an instruction.
        let ironStatus: String?

        init?(labs: LabResult?, iron: IronCoach.Finding? = nil) {
            guard let labs, !labs.isEmpty else { return nil }
            ldl = labs.ldl
            hdl = labs.hdl
            triglycerides = labs.triglycerides
            fastingGlucose = labs.fastingGlucose
            a1c = labs.a1c
            ferritin = labs.ferritin
            hemoglobin = labs.hemoglobin
            transferrinSaturation = labs.transferrinSaturation
            ironStatus = (iron?.status.isActionable ?? false) ? iron?.status.rawValue : nil
        }

        var promptLine: String {
            var parts: [String] = []
            if let ldl { parts.append("LDL \(Int(ldl)) mg/dL") }
            if let hdl { parts.append("HDL \(Int(hdl)) mg/dL") }
            if let triglycerides { parts.append("triglycerides \(Int(triglycerides)) mg/dL") }
            if let fastingGlucose { parts.append("fasting glucose \(Int(fastingGlucose)) mg/dL") }
            if let a1c { parts.append("A1C \(a1c.formatted(.number.precision(.fractionLength(1))))%") }
            if let ferritin { parts.append("ferritin \(Int(ferritin)) ng/mL") }
            if let hemoglobin {
                parts.append("hemoglobin \(hemoglobin.formatted(.number.precision(.fractionLength(1)))) g/dL")
            }
            if let transferrinSaturation {
                parts.append("transferrin saturation \(Int(transferrinSaturation))%")
            }
            return parts.joined(separator: ", ")
        }

        /// The extra instruction low iron earns. Dietary only — pairing,
        /// timing, and heme sources. Never supplements: that's a doctor's
        /// call, and getting it wrong does real damage.
        var ironInstruction: String {
            guard ironStatus != nil else { return "" }
            return """

            Their iron stores are low. Favor iron-rich foods — red meat, liver, \
            oysters, mussels, dark-meat poultry, lentils, beans, tofu, spinach, \
            fortified cereal — and pair plant sources with vitamin C (peppers, \
            citrus, tomato, strawberries) in the same dish, because that \
            combination is what actually gets the iron absorbed. Keep coffee, \
            tea, and large calcium servings out of these meals. Do not mention \
            or recommend iron supplements, and do not say anything diagnostic.
            """
        }
    }

    /// End-of-day coach: looks at everything eaten vs the targets and
    /// suggests concrete substitutions for next time. When a lab snapshot is
    /// provided (opt-in), suggestions lean toward improving those markers.
    static func reviewDay(day: DayLog, targets: DailyTargets,
                          labs: LabSnapshot? = nil,
                          preferences: FoodPreferences = .empty) async throws -> DayReview {
        struct PayloadSuggestion: Decodable {
            let issue: String?
            let swap: String?
        }
        struct Payload: Decodable {
            let headline: String?
            let wins: [String]?
            let suggestions: [PayloadSuggestion]?
        }

        let foodLines = day.foods
            .sorted { ($0.meal?.rawValue ?? "z", $0.occurredAt) < ($1.meal?.rawValue ?? "z", $1.occurredAt) }
            .map { f -> String in
                let meal = f.meal?.label ?? "Unspecified"
                var line = "- [\(meal)] \(f.name): \(f.calories) cal, \(f.proteinGrams) g protein"
                let facts = f.facts
                if facts.sodiumMg > 0 { line += ", \(Int(facts.sodiumMg)) mg sodium" }
                if facts.saturatedFatGrams > 0 { line += ", \(Int(facts.saturatedFatGrams)) g sat fat" }
                if facts.addedSugarGrams > 0 { line += ", \(Int(facts.addedSugarGrams)) g added sugar" }
                if facts.fiberGrams > 0 { line += ", \(Int(facts.fiberGrams)) g fiber" }
                return line
            }
            .joined(separator: "\n")

        let totals = day.totalFacts
        let labSection: String
        if let labs {
            labSection = """

            The user chose to share recent lab numbers (values only) to steer \
            food choices: \(labs.promptLine).
            Weight your suggestions toward improving these markers — for \
            high LDL or triglycerides favor swaps that cut saturated and \
            trans fat and add soluble fiber; for high glucose or A1C favor \
            swaps that cut added sugar and refined carbs. Where a suggestion \
            relates to a marker, phrase it as something worth raising with \
            their doctor. You are not giving medical advice and must not \
            diagnose or recommend medication.\(labs.ironInstruction)
            """
        } else {
            labSection = ""
        }
        let prompt = """
        You are a supportive nutrition coach reviewing one day of eating. \
        Be specific and practical, never preachy. Suggestions must be food \
        SUBSTITUTIONS into what was actually eaten (swap X for Y in that \
        meal), not generic advice.\(preferences.promptSection)\(labSection)
        Targets: \(targets.calories) cal, \(targets.proteinGrams) g protein.
        Eaten (total \(day.totalCalories) cal, \(day.totalProtein) g protein, \
        \(Int(totals.sodiumMg)) mg sodium, \(Int(totals.saturatedFatGrams)) g sat fat, \
        \(Int(totals.addedSugarGrams)) g added sugar, \(Int(totals.fiberGrams)) g fiber):
        \(foodLines)
        Respond with only JSON:
        {"headline": "<one sentence verdict on the day>", \
        "wins": ["<1-3 short things that went well>"], \
        "suggestions": [{"issue": "<what to improve, tied to a specific food eaten>", \
        "swap": "<the concrete substitution and roughly what it saves or adds>"}]}
        Give 2-4 suggestions.
        """
        let payload: Payload = try await generate(prompt: prompt)
        guard let headline = payload.headline, !headline.isEmpty else {
            throw EstimatorError.badResponse
        }
        let suggestions = (payload.suggestions ?? []).compactMap { s -> DayReview.Suggestion? in
            guard let issue = s.issue, let swap = s.swap else { return nil }
            return DayReview.Suggestion(issue: issue, swap: swap)
        }
        return DayReview(headline: headline,
                         wins: payload.wins ?? [],
                         suggestions: suggestions)
    }

    /// Week-level coach: looks for patterns across the last 7 days and
    /// suggests the swaps that would have moved the needle most.
    static func reviewWeek(days: [DayLog], targets: DailyTargets,
                           labs: LabSnapshot? = nil,
                           preferences: FoodPreferences = .empty) async throws -> DayReview {
        struct PayloadSuggestion: Decodable {
            let issue: String?
            let swap: String?
        }
        struct Payload: Decodable {
            let headline: String?
            let wins: [String]?
            let suggestions: [PayloadSuggestion]?
        }

        let logged = days.filter { $0.totalCalories > 0 }.sorted { $0.date < $1.date }
        let dayLines = logged.map { d -> String in
            let facts = d.totalFacts
            let biggest = d.foods.sorted { $0.calories > $1.calories }.prefix(3)
                .map { "\($0.name) (\($0.calories))" }
                .joined(separator: ", ")
            var line = "- \(d.date.formatted(.dateTime.weekday(.abbreviated).month().day())): "
            line += "\(d.totalCalories) cal, \(d.totalProtein) g protein, "
            line += "\(Int(facts.sodiumMg)) mg sodium, \(Int(facts.saturatedFatGrams)) g sat fat, "
            line += "\(Int(facts.addedSugarGrams)) g added sugar, \(Int(facts.fiberGrams)) g fiber"
            if !biggest.isEmpty { line += "; biggest: \(biggest)" }
            return line
        }.joined(separator: "\n")
        guard !dayLines.isEmpty else { throw EstimatorError.badResponse }

        let labSection: String
        if let labs {
            labSection = """

            The user chose to share recent lab numbers (values only) to steer \
            food choices: \(labs.promptLine).
            Weight suggestions toward improving these markers, phrase related \
            notes as things worth raising with their doctor, and never \
            diagnose or recommend medication.\(labs.ironInstruction)
            """
        } else {
            labSection = ""
        }
        let prompt = """
        You are a supportive nutrition coach reviewing a WEEK of eating. \
        Look for repeating patterns (a daily soda, heavy weekend meals, low \
        protein at breakfast) rather than one-off slips. Be specific and \
        practical, never preachy. Suggestions must be substitutions into \
        foods that were actually eaten repeatedly.\(preferences.promptSection)\(labSection)
        Daily targets: \(targets.calories) cal, \(targets.proteinGrams) g protein.
        The week (\(logged.count) logged day\(logged.count == 1 ? "" : "s")):
        \(dayLines)
        Respond with only JSON:
        {"headline": "<one sentence verdict on the week>", \
        "wins": ["<1-3 short things that went well this week>"], \
        "suggestions": [{"issue": "<the recurring pattern to improve, tied to specific foods>", \
        "swap": "<the concrete substitution and roughly what it saves per week>"}]}
        Give 2-4 suggestions.
        """
        let payload: Payload = try await generate(prompt: prompt)
        guard let headline = payload.headline, !headline.isEmpty else {
            throw EstimatorError.badResponse
        }
        let suggestions = (payload.suggestions ?? []).compactMap { s -> DayReview.Suggestion? in
            guard let issue = s.issue, let swap = s.swap else { return nil }
            return DayReview.Suggestion(issue: issue, swap: swap)
        }
        return DayReview(headline: headline,
                         wins: payload.wins ?? [],
                         suggestions: suggestions)
    }

    /// One "what should I eat" idea — carries a full nutrition panel so
    /// tapping Log writes a normal FoodLog with no second round-trip.
    struct MealSuggestion: Identifiable {
        let id = UUID()
        let name: String
        let why: String            // one line: why it fits right now
        let calories: Int
        let proteinGrams: Int
        let grams: Double?
        let facts: NutritionFacts
        let density: String?
        let assumed: String?
        /// Where to get it, when the idea came from a restaurant search.
        var restaurant: String? = nil
        /// How to order it so the numbers hold — "no crema, dressing on the
        /// side". The whole trick of eating out well is in this line.
        var order: String? = nil
    }

    /// The specific meal being planned, when the ask came from the day plan
    /// rather than from "what's left of today". Aiming at one meal's macros
    /// is a far better question than aiming at a day's remainder — it has a
    /// carb number, a protein number, and often a deadline attached.
    struct MealBrief {
        let label: String          // "Breakfast", "Recovery Snack"
        let calories: Int
        let carbGrams: Int
        let proteinGrams: Int
        let fatGrams: Int
        /// "pre-workout" / "recovery" / nil
        let role: String?
        /// Minutes until the session this meal is feeding, when there is one.
        let minutesBeforeSession: Int?

        var promptLine: String {
            var line = """
            This is specifically their \(label.lowercased()), and it has its own \
            target: about \(calories) calories, \(carbGrams) g carbs, \
            \(proteinGrams) g protein, \(fatGrams) g fat. Every suggestion \
            should land close to ALL FOUR of those numbers, not just the \
            calories.
            """
            switch role {
            case "pre-workout":
                let when = minutesBeforeSession.map { "about \($0) minutes" } ?? "shortly"
                line += """
                 They train \(when) after this meal, so it has to be easy to \
                digest: carb-forward, low fat, low fiber. Nothing heavy, greasy, \
                or high in fiber — it won't have cleared in time.
                """
            case "recovery":
                line += """
                 This is their post-session meal, eaten soon after training, so \
                it should pair real carbohydrate with real protein to refill \
                glycogen and start repair.
                """
            default:
                break
            }
            return line
        }
    }

    /// Suggest meals that fit — either one meal's own macro target (when the
    /// day plan asked) or what's LEFT of today's budget. Labs steer the
    /// ingredients when they're shared; stores and dislikes are hard limits.
    /// Ideas that fit — at home, or at a restaurant near a named place.
    ///
    /// `nearby` is the only thing that changes the character of the call: with
    /// a place name it has to name real restaurants and real menu items, which
    /// is a fact-finding question rather than a cooking one, so it runs
    /// search-grounded and *fails* rather than falling back. A model inventing
    /// a salad at a restaurant that doesn't exist — or inventing the calories
    /// of a real one — is worse than no answer.
    ///
    /// `avoid` is what's already on screen, so "refresh this one" can hand back
    /// something genuinely different instead of the same three ideas reshuffled.
    static func suggestMeals(meal: String,
                             remainingCalories: Int,
                             remainingProtein: Int,
                             eatenToday: [String],
                             labs: LabSnapshot? = nil,
                             preferences: FoodPreferences = .empty,
                             brief: MealBrief? = nil,
                             count: Int = 3,
                             avoid: [String] = [],
                             nearby: String? = nil) async throws -> [MealSuggestion] {
        struct PayloadSuggestion: Decodable {
            let name: String?
            let why: String?
            let assumed: String?
            let restaurant: String?
            let order: String?
            let food: FoodPayload?
        }
        struct Payload: Decodable {
            let suggestions: [PayloadSuggestion]?
        }
        let labSection: String
        if let labs {
            labSection = """

            The user chose to share recent lab numbers (values only): \
            \(labs.promptLine). Favor suggestions that would help those \
            markers (less saturated fat and added sugar, more fiber) without \
            saying anything that sounds like medical advice.\(labs.ironInstruction)
            """
        } else {
            labSection = ""
        }
        let eatenLine = eatenToday.isEmpty
            ? "Nothing has been logged yet today."
            : "Already eaten today: \(eatenToday.joined(separator: ", ")). Don't repeat these."
        // A meal brief replaces the day-remainder framing outright — they'd
        // contradict each other, and the specific target is the better one.
        let targetLine = brief?.promptLine ?? """
        They have \(remainingCalories) calories and \(remainingProtein) g \
        protein left in today's budget — every option must fit inside the \
        remaining calories, and at least two should make a real dent in the \
        protein gap.
        """
        let avoidLine = avoid.isEmpty ? "" : """
             Do NOT suggest any of these — they were already offered and \
            turned down: \(avoid.joined(separator: ", ")). Come back with \
            something genuinely different, not a variation on them.
            """

        let prompt: String
        if let nearby {
            prompt = """
            Find \(count) genuinely good \(meal) option\(count == 1 ? "" : "s") on the menus of \
            real restaurants, cafés or fast-casual chains in or very near \
            \(nearby). Search for their actual published menus and nutrition \
            information — only name places that really exist there, and only \
            dishes that are really on their menu. If you can't verify a place \
            has the dish, leave it out rather than guessing.
            \(targetLine) \(eatenLine)\(avoidLine)\(preferences.promptSection)\(labSection)
            Prefer things that are ordinary orders rather than obscure \
            hacks, and say plainly how to order each one so the numbers hold \
            (what to leave off, what to ask for on the side, what size).
            \(nutritionGuidance)
            Use the restaurant's own published numbers when they exist, and \
            say so in "assumed"; otherwise estimate from the ingredients and \
            say that instead.
            Respond with only JSON:
            {"suggestions": [{"name": "<the menu item, as they call it>", \
            "restaurant": "<the restaurant or chain name, and its neighbourhood>", \
            "order": "<one short sentence: how to order it>", \
            "why": "<one short sentence: why this fits right now>", \
            "assumed": "<short: published numbers, or what you estimated from>", \
            "food": {\(nutritionSchema)}}]}
            """
        } else {
            prompt = """
            Suggest \(count) realistic \(meal) option\(count == 1 ? "" : "s") someone could actually make at \
            home or grab easily. \(targetLine) \(eatenLine)\(avoidLine)\(preferences.promptSection)\(labSection)
            \(nutritionGuidance)
            Respond with only JSON:
            {"suggestions": [{"name": "<short dish name>", \
            "why": "<one short sentence: why this fits right now>", \
            "assumed": "<short: the exact portion assumed>", \
            "food": {\(nutritionSchema)}}]}
            """
        }

        // Restaurants are a question about the world, so they go out with
        // search attached and no silent fallback: an unverified restaurant is
        // not a suggestion, it's a fabrication.
        let payload: Payload = nearby == nil
            ? try await generate(prompt: prompt)
            : try await performGenerate(parts: [["text": prompt]], grounded: true)
        let suggestions = (payload.suggestions ?? []).compactMap { s -> MealSuggestion? in
            guard let name = s.name, !name.isEmpty,
                  let food = s.food, let calories = food.calories else { return nil }
            // A dislike list that only lives in the prompt isn't a dislike
            // list. Anything naming an excluded food is dropped here, whatever
            // the model thought.
            if preferences.excludes(name) || preferences.excludes(s.assumed ?? "") { return nil }
            // A restaurant idea with no restaurant on it is a guess wearing
            // the wrong hat — drop it rather than show it as local.
            if nearby != nil, (s.restaurant ?? "").isEmpty { return nil }
            return MealSuggestion(name: name,
                                  why: s.why ?? "",
                                  calories: calories,
                                  proteinGrams: Int((food.protein_g ?? 0).rounded()),
                                  grams: food.portion_grams,
                                  facts: food.facts,
                                  density: food.density,
                                  assumed: s.assumed,
                                  restaurant: s.restaurant,
                                  order: s.order)
        }
        guard !suggestions.isEmpty else { throw EstimatorError.badResponse }
        return suggestions
    }

    private struct GeminiResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String? }
                let parts: [Part]?
            }
            let content: Content?
        }
        let candidates: [Candidate]?
    }

    /// Why a call failed, told apart rather than lumped together.
    ///
    /// Every failure used to come back as "check the key, your connection, or
    /// try a more specific description", which is three guesses and no answer.
    /// The common failure in practice isn't the key at all — it's the free
    /// tier's quota for *search-grounded* calls running out, which returns 429
    /// while ordinary estimates keep working perfectly. Reading a recipe link
    /// needs those tools, so the one feature that can't fall back was also the
    /// one accusing a perfectly good key. These cases exist so each failure can
    /// say what actually happened and what to do about it.
    enum EstimatorError: LocalizedError {
        case noKey, badResponse, badLink, linkUnread(String?)
        /// The key was rejected outright — revoked, restricted, or mistyped.
        case invalidKey(String?)
        /// Free-tier quota spent. `grounded` when it was the search/URL tools
        /// rather than the model itself, which is the usual case by far.
        case quotaExhausted(grounded: Bool)
        /// Gemini is over capacity (503). Nothing to fix; try again.
        case overloaded
        case offline
        case timedOut
        /// Anything else Google said, passed through rather than swallowed.
        case server(code: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "Add your free Gemini API key in Settings → AI & Estimates first."
            case .badResponse:
                return "Gemini answered, but not with numbers this could read. Try again, or describe the food a little more specifically."
            case .badLink:
                return "That doesn't look like a web link — paste the full https:// address of the recipe."
            case .linkUnread(let why):
                let base = "Couldn't read that link"
                if let why, !why.isEmpty { return "\(base) — \(why). Try a recipe website or a YouTube link." }
                return "\(base). Short-form video (TikTok, Instagram) often can't be read — try a recipe website or YouTube, or paste the ingredients into Describe Your Meal."
            case .invalidKey(let detail):
                let base = "Google rejected the API key. Keys don't expire on their own, but they can be deleted or restricted in AI Studio — check Settings → AI & Estimates, or paste a fresh one."
                if let detail, !detail.isEmpty { return "\(base)\n\n(\(detail))" }
                return base
            case .quotaExhausted(let grounded):
                return grounded
                    ? "The free tier's quota for web-checked lookups is used up for now. Plain estimates still work — this only affects reading links and checking numbers against published data. It resets on Google's clock (usually within the day), or paste your own key in Settings → AI & Estimates."
                    : "The free tier's request quota is used up for now. It resets on Google's clock — usually within a day — or paste your own key in Settings → AI & Estimates to use your own."
            case .overloaded:
                return "Gemini is over capacity right now — that's on Google's end, not your key. Try again in a minute."
            case .offline:
                return "No connection. Custom Food still works offline — type the numbers in and fix them later."
            case .timedOut:
                return "Gemini took too long to answer. Try again — or turn off “Higher accuracy” in Settings → AI & Estimates, which trades some precision for a much faster reply."
            case .server(let code, let message):
                if let message, !message.isEmpty { return "Gemini returned an error (\(code)): \(message)" }
                return "Gemini returned an error (\(code)). Try again in a moment."
            }
        }

        /// True when trying again later is the whole answer.
        var isTransient: Bool {
            switch self {
            case .overloaded, .timedOut, .offline, .quotaExhausted: return true
            default: return false
            }
        }
    }

    /// Google's error envelope: `{"error": {"code", "message", "status"}}`.
    private struct APIError: Decodable {
        struct Body: Decodable {
            let code: Int?
            let message: String?
            let status: String?
        }
        let error: Body?
    }

    /// Turn a non-200 reply into the error that actually describes it.
    private static func failure(status: Int, data: Data, grounded: Bool) -> EstimatorError {
        let body = (try? JSONDecoder().decode(APIError.self, from: data))?.error
        let message = body?.message
        let code = body?.status ?? ""
        switch status {
        case 429:
            return .quotaExhausted(grounded: grounded)
        case 400 where (message ?? "").localizedCaseInsensitiveContains("api key")
                    || code == "INVALID_ARGUMENT" && (message ?? "").localizedCaseInsensitiveContains("key"):
            return .invalidKey(message)
        case 401, 403:
            return .invalidKey(message)
        case 500, 502, 503, 504:
            return .overloaded
        default:
            return .server(code: status, message: message)
        }
    }

    /// A transport failure, named. `URLError` is where a dead Wi-Fi network and
    /// a slow model both land, and they need different sentences.
    private static func transportFailure(_ error: Error) -> EstimatorError {
        guard let urlError = error as? URLError else { return .badResponse }
        switch urlError.code {
        case .notConnectedToInternet, .dataNotAllowed, .cannotFindHost,
             .cannotConnectToHost, .networkConnectionLost:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .badResponse
        }
    }

    // MARK: - Grounding cooldown

    /// When the search-grounded path is out of quota, stop leading with it.
    ///
    /// Every grounded call that 429s is a wasted round trip before the plain
    /// call that was always going to answer, and it burns request budget on
    /// the way. So a quota rejection parks grounding for a while and estimates
    /// go straight to the model, which is what the fallback was doing anyway —
    /// just without the detour.
    private static let groundingCooldownKey = "ai.grounding.cooldownUntil"
    private static let groundingCooldown: TimeInterval = 30 * 60

    static var groundingIsCoolingDown: Bool {
        let until = UserDefaults.standard.double(forKey: groundingCooldownKey)
        return until > Date().timeIntervalSince1970
    }

    /// When grounded lookups should start being tried again, if they're parked.
    static var groundingResumesAt: Date? {
        let until = UserDefaults.standard.double(forKey: groundingCooldownKey)
        guard until > Date().timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: until)
    }

    private static func parkGrounding() {
        UserDefaults.standard.set(Date().timeIntervalSince1970 + groundingCooldown,
                                  forKey: groundingCooldownKey)
    }

    static func resumeGrounding() {
        UserDefaults.standard.removeObject(forKey: groundingCooldownKey)
    }

    /// Full nutrition for one typical serving (Custom Food "Estimate with AI").
    static func estimate(food: String) async throws -> Estimate {
        struct Payload: Decodable {
            let food: FoodPayload?
            let assumed: String?
        }
        let prompt = """
        Estimate the full nutrition for one typical serving of: "\(food)". \
        \(nutritionGuidance)
        Respond with only JSON:
        {"food": {"name": "<short food name>", \(nutritionSchema)}, \
        "assumed": "<one short sentence: exactly what food and serving size you assumed>"}
        """
        let (payload, grounded): (Payload, Bool) =
            try await generateGrounded(parts: [["text": prompt]])
        guard let p = payload.food, let calories = p.calories else {
            throw EstimatorError.badResponse
        }
        return Estimate(name: p.name ?? food,
                        calories: calories,
                        proteinGrams: Int((p.protein_g ?? 0).rounded()),
                        grams: p.portion_grams,
                        facts: p.facts,
                        density: p.density,
                        assumed: payload.assumed ?? "",
                        grounded: grounded)
    }

    /// Protein per 100 g — auto-fills Open Food Facts results that are
    /// missing a protein value.
    static func proteinPer100g(food: String) async throws -> ProteinEstimate {
        struct Payload: Decodable {
            let protein_grams_per_100g: Double?
            let assumed: String?
        }
        let prompt = """
        Estimate the protein content of this food: "\(food)".
        Respond with only JSON:
        {"protein_grams_per_100g": <number, grams of protein per 100 grams>, \
        "assumed": "<short phrase: what food you assumed this is>"}
        """
        let payload: Payload = try await generate(prompt: prompt)
        guard let protein = payload.protein_grams_per_100g, protein >= 0 else {
            throw EstimatorError.badResponse
        }
        return ProteinEstimate(gramsPer100g: protein, assumed: payload.assumed ?? "")
    }

    private static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 768) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }

    /// One plain Gemini call decoding the model's JSON reply into `T`.
    private static func generate<T: Decodable>(prompt: String) async throws -> T {
        try await performGenerate(parts: [["text": prompt]], grounded: false)
    }

    /// Grounded call: runs with Google Search so nutrition comes from real
    /// sources (restaurant pages, USDA) instead of memory; if the grounded
    /// attempt fails (search quota, transport), it falls back to the plain
    /// call so logging never breaks. Reports which one actually answered so
    /// the UI can badge "looked up" vs "best guess".
    private static func generateGrounded<T: Decodable>(parts: [[String: Any]]) async throws -> (payload: T, grounded: Bool) {
        guard !groundingIsCoolingDown else {
            return (try await performGenerate(parts: parts, grounded: false), false)
        }

        // Both at once, rather than grounded-then-plain.
        //
        // This used to run the search-grounded call first and only fall back
        // when it failed, which meant the *normal* path was the slow one: a
        // grounded call runs a web search before it generates, and a meal with
        // seven items was waiting on that before the fast call had even
        // started. Now the plain call — a couple of seconds — is always in
        // flight, and grounding is an upgrade that has to arrive within
        // `groundingDeadline` to be used. Worst case is the deadline instead of
        // the sum of the two.
        async let plainAttempt = attempt { try await performGenerate(parts: parts, grounded: false) as T }
        async let groundedAttempt = attempt {
            try await withDeadline(seconds: groundingDeadline) {
                try await performGenerate(parts: parts, grounded: true) as T
            }
        }
        let plain = await plainAttempt
        let grounded = await groundedAttempt

        switch grounded {
        case .success(let payload):
            return (payload, true)
        case .failure(let error):
            if case EstimatorError.quotaExhausted = error {
                // Park it so the next estimate doesn't pay for the same
                // rejection — and skips straight to the fast call.
                parkGrounding()
            }
            return (try plain.get(), false)
        }
    }

    /// How long a web-checked answer gets to beat the plain one. Past this the
    /// numbers aren't worth the wait — they're an accuracy upgrade, not the
    /// answer itself.
    private static let groundingDeadline: TimeInterval = 6

    private static func attempt<T>(_ work: @escaping @Sendable () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }

    /// Run `work`, giving up on it after `seconds`. The losing task is
    /// cancelled, so a slow grounded call stops holding a connection open.
    private static func withDeadline<T: Sendable>(seconds: TimeInterval,
                                                  _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw EstimatorError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// A call that runs with explicit tools (url_context, google_search) on a
    /// named model. Tools can't be combined with JSON response mode, so the
    /// reply comes back as text and the JSON is extracted below. Reading a
    /// page or video is slow, so this gets a generous timeout.
    private static func generateTooled<T: Decodable>(parts: [[String: Any]],
                                                     tools: [[String: Any]],
                                                     modelName: String) async throws -> T {
        let key = apiKey
        guard !key.isEmpty else { throw EstimatorError.noKey }

        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent")!)
        request.timeoutInterval = 90
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = ["contents": [["parts": parts]],
                                   "tools": tools,
                                   "generationConfig": ["temperature": 0]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw transportFailure(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // Reading a link is a tool call, so a quota rejection here is the
            // grounded quota — the same one estimates fall back from. Say so
            // instead of blaming the key.
            let error = failure(status: status, data: data, grounded: true)
            if case .quotaExhausted = error { parkGrounding() }
            throw error
        }
        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = (decoded.candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
        guard let payload = try? JSONDecoder().decode(T.self, from: Data(extractJSON(text).utf8)) else {
            throw EstimatorError.badResponse
        }
        return payload
    }

    private static func performGenerate<T: Decodable>(parts: [[String: Any]],
                                                      grounded: Bool,
                                                      keyOverride: String? = nil) async throws -> T {
        let key = keyOverride ?? apiKey
        guard !key.isEmpty else { throw EstimatorError.noKey }

        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        // Full Flash thinks before answering — give accurate mode more room.
        let accurate = UserDefaults.standard.bool(forKey: accurateModelKey)
        request.timeoutInterval = accurate ? 60 : (grounded ? 35 : 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        // Search grounding can't be combined with JSON response mode, so
        // grounded calls ask for raw text and the JSON is extracted below.
        var body: [String: Any] = ["contents": [["parts": parts]]]
        if grounded {
            body["tools"] = [["google_search": [String: String]()]]
            body["generationConfig"] = ["temperature": 0]
        } else {
            body["generationConfig"] = ["responseMimeType": "application/json",
                                        "temperature": 0]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw transportFailure(error)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let error = failure(status: status, data: data, grounded: grounded)
            // A key the user pasted can be revoked or restricted while the
            // bundled one is fine. Falling back once — and only for a rejected
            // key, never for a quota or an outage — is the difference between
            // "AI stopped working" and never noticing.
            if case .invalidKey = error, keyOverride == nil,
               usingUserKey, !bundledKey.isEmpty {
                return try await performGenerate(parts: parts, grounded: grounded,
                                                 keyOverride: bundledKey)
            }
            throw error
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = (decoded.candidates?.first?.content?.parts ?? [])
            .compactMap(\.text)
            .joined()
        guard let payload = try? JSONDecoder().decode(T.self, from: Data(extractJSON(text).utf8)) else {
            throw EstimatorError.badResponse
        }
        return payload
    }

    // MARK: - Checking the key

    /// What a live check of the key found.
    struct KeyCheck {
        /// Ordinary estimates — the path almost everything uses.
        let plainWorks: Bool
        /// Web-checked lookups and reading recipe links.
        let groundedWorks: Bool
        /// Whose key answered.
        let usingUserKey: Bool
        /// One line for each result, in the order they should be read.
        let notes: [String]

        var headline: String {
            if plainWorks && groundedWorks { return "Everything works." }
            if plainWorks { return "Estimates work — web lookups don't." }
            return "Nothing is getting through."
        }

        var isHealthy: Bool { plainWorks }
    }

    /// Ask Google, rather than guessing from the shape of the string.
    ///
    /// A key that looks perfect can be revoked, and a key that's completely
    /// fine still fails every grounded lookup once the free tier's search quota
    /// is spent — which is what "the AI key stopped working" almost always
    /// turns out to be. Two tiny calls tell those apart in about a second, so
    /// the answer to "has it expired?" is a button rather than a guess.
    static func checkKey() async -> KeyCheck {
        let mine = usingUserKey
        guard !apiKey.isEmpty else {
            return KeyCheck(plainWorks: false, groundedWorks: false, usingUserKey: mine,
                            notes: ["No key at all — paste one above."])
        }

        struct Ping: Decodable { let ok: String? }
        var notes: [String] = []

        var plainWorks = false
        do {
            let _: Ping = try await performGenerate(
                parts: [["text": #"Reply with this JSON exactly: {"ok":"yes"}"#]],
                grounded: false)
            plainWorks = true
            notes.append("Estimates: working. Describing a meal, photos, custom foods, meal ideas and the day review all go through this.")
        } catch EstimatorError.badResponse {
            // Google answered; the model just phrased the ping oddly. The key
            // and the connection are the things being tested here.
            plainWorks = true
            notes.append("Estimates: working — the key and connection are fine.")
        } catch {
            notes.append("Estimates: failing — \(error.localizedDescription)")
        }

        var groundedWorks = false
        do {
            let _: Ping = try await performGenerate(
                parts: [["text": #"Reply with this JSON exactly: {"ok":"yes"}"#]],
                grounded: true)
            groundedWorks = true
            resumeGrounding()
            notes.append("Web-checked lookups: working. Numbers get checked against published data, and recipe links can be read.")
        } catch let error as EstimatorError {
            if case .badResponse = error {
                // Grounded replies come back as prose often enough that an
                // unparsed ping says nothing about the quota.
                groundedWorks = true
                resumeGrounding()
                notes.append("Web-checked lookups: working.")
            } else if case .quotaExhausted = error {
                parkGrounding()
                notes.append("Web-checked lookups: out of free quota. Estimates still work — they just fall back to the model's own knowledge, badged “Best guess”. Reading a recipe link needs this quota, so that feature waits for the reset.")
            } else {
                notes.append("Web-checked lookups: failing — \(error.localizedDescription)")
            }
        } catch {
            notes.append("Web-checked lookups: failing — \(error.localizedDescription)")
        }

        if plainWorks && !mine {
            notes.append("This is the key bundled with the app, shared by everyone using it — paste your own above for a private quota of your own.")
        }
        return KeyCheck(plainWorks: plainWorks, groundedWorks: groundedWorks,
                        usingUserKey: mine, notes: notes)
    }

    /// Grounded replies come back as prose-wrapped or fenced JSON — take the
    /// outermost braces.
    private static func extractJSON(_ text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }
}

// MARK: - Prompt transparency

extension AIFoodEstimator {
    /// A human-readable preview of one prompt the app can send, with the
    /// parts you enter shown as ‹placeholders›. Built from the same guidance
    /// and schema constants the live calls use, so what's shown here can't
    /// drift from what's actually sent.
    struct PromptInfo: Identifiable {
        let id: String
        let title: String
        let whenUsed: String       // when this call fires
        let sends: String          // what leaves the device
        let grounded: Bool         // runs with Google Search grounding
        let template: String       // the prompt, user input as ‹placeholders›

        var groundingNote: String {
            grounded
                ? "Runs with Google Search so numbers can be checked against real published data (green “Looked up” badge). Falls back to a plain estimate if search is unavailable."
                : "A plain model call — no web search."
        }
    }

    /// Every prompt the app sends, in the order they appear in the app, with
    /// user-entered text replaced by ‹placeholders›.
    static var promptCatalog: [PromptInfo] {
        [
            PromptInfo(
                id: "describe",
                title: "Describe Your Meal",
                whenUsed: "When you type or dictate a meal and tap estimate.",
                sends: "Only the meal text you entered.",
                grounded: true,
                template: """
                Break this meal description into separate food items and estimate the \
                full nutrition of each. \(nutritionGuidance)
                List EVERY distinct component or ingredient as its own item — never \
                merge two ingredients into one line. Oils, butter, cheeses, sauces, \
                and dressings each get their own item (feta and cream cheese are two \
                items; olive oil is never folded into the vegetables it's on). If the \
                user names an ingredient, it must appear as its own item.
                Meal: "‹your meal description›"
                Respond with only JSON:
                {"items": [{"name": "<short item name>", \
                "assumed": "<short: the exact portion you assumed for this item>", \
                \(nutritionSchema)}], \
                "assumed": "<one short sentence: overall assumptions about the meal>"}
                """),
            PromptInfo(
                id: "photo",
                title: "Photo of Food",
                whenUsed: "When you snap or pick a photo of a plate.",
                sends: "The food photo (downscaled) plus any notes you add.",
                grounded: true,
                template: """
                Identify every distinct food in this photo and estimate the full \
                nutrition of each from the portions shown. \(nutritionGuidance)
                List EVERY distinct component as its own item — never merge two \
                foods into one line; sauces, dressings, sides, and drinks each get \
                their own item.
                The user adds: "‹your notes, if any›".
                Respond with only JSON:
                {"items": [{"name": "<short item name>", \
                "assumed": "<short: what you identified and the portion you assumed>", \
                \(nutritionSchema)}], \
                "assumed": "<one short sentence: overall assumptions about the plate>"}
                If there is no food in the photo, use {"items": []}.
                [the photo is attached alongside this text]
                """),
            PromptInfo(
                id: "recipe",
                title: "Recipe from a Link",
                whenUsed: "When you paste a recipe web link or video URL.",
                sends: "Only the link you pasted (the model reads the page or video itself).",
                grounded: true,
                template: """
                The user pasted a link to a recipe. Read the page (or watch the \
                video and read its description and top comments) to get the \
                ingredient list and quantities as precisely as you can, then \
                break the FULL recipe into its ingredients and estimate the \
                nutrition of each. \(nutritionGuidance)
                List EVERY ingredient as its own item. Base each item on the \
                amount used in the WHOLE recipe. Also report how many servings \
                the whole recipe makes.
                Link: ‹the link you pasted›
                Respond with only JSON:
                {"title": "<recipe name>", \
                "servings": <integer servings the whole recipe yields>, \
                "items": [{"name": "<ingredient>", \
                "assumed": "<the amount used in the whole recipe>", \
                \(nutritionSchema)}], \
                "assumed": "<one short sentence: overall assumptions>", \
                "note": "<if the link couldn't be read, why; else empty>"}
                """),
            PromptInfo(
                id: "estimate",
                title: "Estimate Nutrition",
                whenUsed: "“Estimate with AI” on a custom food or a “Not listed?” search result.",
                sends: "Only the food name you entered.",
                grounded: true,
                template: """
                Estimate the full nutrition for one typical serving of: "‹food name›". \
                \(nutritionGuidance)
                Respond with only JSON:
                {"food": {"name": "<short food name>", \(nutritionSchema)}, \
                "assumed": "<one short sentence: exactly what food and serving size you assumed>"}
                """),
            PromptInfo(
                id: "protein",
                title: "Fill in Missing Protein",
                whenUsed: "When a database entry has no protein value.",
                sends: "Only the food name.",
                grounded: false,
                template: """
                Estimate the protein content of this food: "‹food name›".
                Respond with only JSON:
                {"protein_grams_per_100g": <number, grams of protein per 100 grams>, \
                "assumed": "<short phrase: what food you assumed this is>"}
                """),
            PromptInfo(
                id: "suggest",
                title: "What Should I Eat?",
                whenUsed: "When you ask for meal ideas — for one meal on the day plan, or for whatever's left of the budget.",
                sends: "The meal name and its target (or your remaining calories and protein), the names of foods already logged today, and the stores and excluded foods you set in Food Preferences (plus lab numbers only if you turned that on).",
                grounded: false,
                template: """
                Suggest 3 realistic ‹meal› options someone could actually make at \
                home or grab easily. This is specifically their ‹meal›, and it has \
                its own target: about ‹calories› calories, ‹carbs› g carbs, \
                ‹protein› g protein, ‹fat› g fat. Every suggestion should land \
                close to ALL FOUR of those numbers, not just the calories. \
                Already eaten today: ‹foods logged today›. Don't repeat these.
                Every ingredient must be something they can buy at one of these \
                stores: ‹your stores›.
                Hard exclusions — never suggest these, and never suggest a dish \
                that contains them: ‹foods you excluded›.
                \(nutritionGuidance)
                Respond with only JSON:
                {"suggestions": [{"name": "<short dish name>", \
                "why": "<one short sentence: why this fits right now>", \
                "assumed": "<short: the exact portion assumed>", \
                "food": {\(nutritionSchema)}}]}
                """),
            PromptInfo(
                id: "restaurants",
                title: "Feeling Restaurants?",
                whenUsed: "When you tap Restaurants in What Should I Eat — and only then.",
                sends: "The neighbourhood name your location resolves to (never coordinates, and nothing is stored), plus the same meal target, logged foods and preferences as the ideas above. Runs with web search so the places and menu items are real ones.",
                grounded: true,
                template: """
                Find 3 genuinely good ‹meal› options on the menus of real \
                restaurants, cafés or fast-casual chains in or very near \
                ‹your neighbourhood›. Search for their actual published menus \
                and nutrition information — only name places that really exist \
                there, and only dishes that are really on their menu. If you \
                can't verify a place has the dish, leave it out rather than \
                guessing.
                This is specifically their ‹meal›, and it has its own target: \
                about ‹calories› calories, ‹carbs› g carbs, ‹protein› g \
                protein, ‹fat› g fat.
                Already eaten today: ‹foods logged today›. Don't repeat these.
                ‹when you refresh one idea: do NOT suggest the ones already on \
                screen›
                Hard exclusions — never suggest these: ‹foods you excluded›.
                Prefer things that are ordinary orders rather than obscure \
                hacks, and say plainly how to order each one so the numbers \
                hold (what to leave off, what to ask for on the side, what size).
                \(nutritionGuidance)
                Use the restaurant's own published numbers when they exist, and \
                say so in "assumed"; otherwise estimate from the ingredients \
                and say that instead.
                Respond with only JSON:
                {"suggestions": [{"name": "<the menu item, as they call it>", \
                "restaurant": "<the restaurant or chain name, and its neighbourhood>", \
                "order": "<one short sentence: how to order it>", \
                "why": "<one short sentence: why this fits right now>", \
                "assumed": "<short: published numbers, or what you estimated from>", \
                "food": {\(nutritionSchema)}}]}
                """),
            PromptInfo(
                id: "day",
                title: "Summarize My Day",
                whenUsed: "The end-of-day review with swap suggestions.",
                sends: "Your calorie and protein targets and a list of what you ate that day (names and nutrition) — never anything identifying (lab numbers only if you turned that on).",
                grounded: false,
                template: """
                You are a supportive nutrition coach reviewing one day of eating. \
                Be specific and practical, never preachy. Suggestions must be food \
                SUBSTITUTIONS into what was actually eaten (swap X for Y in that \
                meal), not generic advice.
                Targets: ‹calorie target› cal, ‹protein target› g protein.
                Eaten (total ‹totals for the day›):
                ‹each food you logged today, one per line›
                Respond with only JSON:
                {"headline": "<one sentence verdict on the day>", \
                "wins": ["<1-3 short things that went well>"], \
                "suggestions": [{"issue": "<what to improve, tied to a specific food eaten>", \
                "swap": "<the concrete substitution and roughly what it saves or adds>"}]}
                Give 2-4 suggestions.
                """),
        ]
    }
}
