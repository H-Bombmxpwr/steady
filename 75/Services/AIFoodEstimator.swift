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

    private static let bundledKey: String = {
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
    Act like a careful nutrition coach: be realistic about restaurant and \
    home portion sizes (err large, people underestimate), include cooking \
    fats and condiments, and base values on USDA-style nutrition data. \
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

        init?(labs: LabResult?) {
            guard let labs, !labs.isEmpty else { return nil }
            ldl = labs.ldl
            hdl = labs.hdl
            triglycerides = labs.triglycerides
            fastingGlucose = labs.fastingGlucose
            a1c = labs.a1c
        }

        var promptLine: String {
            var parts: [String] = []
            if let ldl { parts.append("LDL \(Int(ldl)) mg/dL") }
            if let hdl { parts.append("HDL \(Int(hdl)) mg/dL") }
            if let triglycerides { parts.append("triglycerides \(Int(triglycerides)) mg/dL") }
            if let fastingGlucose { parts.append("fasting glucose \(Int(fastingGlucose)) mg/dL") }
            if let a1c { parts.append("A1C \(a1c.formatted(.number.precision(.fractionLength(1))))%") }
            return parts.joined(separator: ", ")
        }
    }

    /// End-of-day coach: looks at everything eaten vs the targets and
    /// suggests concrete substitutions for next time. When a lab snapshot is
    /// provided (opt-in), suggestions lean toward improving those markers.
    static func reviewDay(day: DayLog, targets: DailyTargets,
                          labs: LabSnapshot? = nil) async throws -> DayReview {
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
            .sorted { ($0.meal?.rawValue ?? "z", $0.createdAt) < ($1.meal?.rawValue ?? "z", $1.createdAt) }
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
            diagnose or recommend medication.
            """
        } else {
            labSection = ""
        }
        let prompt = """
        You are a supportive nutrition coach reviewing one day of eating. \
        Be specific and practical, never preachy. Suggestions must be food \
        SUBSTITUTIONS into what was actually eaten (swap X for Y in that \
        meal), not generic advice.\(labSection)
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
                           labs: LabSnapshot? = nil) async throws -> DayReview {
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
            diagnose or recommend medication.
            """
        } else {
            labSection = ""
        }
        let prompt = """
        You are a supportive nutrition coach reviewing a WEEK of eating. \
        Look for repeating patterns (a daily soda, heavy weekend meals, low \
        protein at breakfast) rather than one-off slips. Be specific and \
        practical, never preachy. Suggestions must be substitutions into \
        foods that were actually eaten repeatedly.\(labSection)
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
    }

    /// Suggest meals that fit what's LEFT of today's budget — the protein
    /// gap steers the picks, labs (opt-in) steer the ingredients.
    static func suggestMeals(meal: String, remainingCalories: Int, remainingProtein: Int,
                             eatenToday: [String], labs: LabSnapshot? = nil) async throws -> [MealSuggestion] {
        struct PayloadSuggestion: Decodable {
            let name: String?
            let why: String?
            let assumed: String?
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
            saying anything that sounds like medical advice.
            """
        } else {
            labSection = ""
        }
        let eatenLine = eatenToday.isEmpty
            ? "Nothing has been logged yet today."
            : "Already eaten today: \(eatenToday.joined(separator: ", ")). Don't repeat these."
        let prompt = """
        Suggest 3 realistic \(meal) options someone could actually make at \
        home or grab easily tonight. They have \(remainingCalories) calories \
        and \(remainingProtein) g protein left in today's budget — every \
        option must fit inside the remaining calories, and at least two \
        should make a real dent in the protein gap. \(eatenLine)\(labSection)
        \(nutritionGuidance)
        Respond with only JSON:
        {"suggestions": [{"name": "<short dish name>", \
        "why": "<one short sentence: why this fits right now>", \
        "assumed": "<short: the exact portion assumed>", \
        "food": {\(nutritionSchema)}}]}
        """
        let payload: Payload = try await generate(prompt: prompt)
        let suggestions = (payload.suggestions ?? []).compactMap { s -> MealSuggestion? in
            guard let name = s.name, !name.isEmpty,
                  let food = s.food, let calories = food.calories else { return nil }
            return MealSuggestion(name: name,
                                  why: s.why ?? "",
                                  calories: calories,
                                  proteinGrams: Int((food.protein_g ?? 0).rounded()),
                                  grams: food.portion_grams,
                                  facts: food.facts,
                                  density: food.density,
                                  assumed: s.assumed)
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

    enum EstimatorError: LocalizedError {
        case noKey, badResponse
        var errorDescription: String? {
            switch self {
            case .noKey:
                return "Add your free Gemini API key in Settings → AI Assist first."
            case .badResponse:
                return "Couldn't get an estimate — check the key, your connection, or try a more specific description."
            }
        }
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
        if let payload: T = try? await performGenerate(parts: parts, grounded: true) {
            return (payload, true)
        }
        return (try await performGenerate(parts: parts, grounded: false), false)
    }

    private static func performGenerate<T: Decodable>(parts: [[String: Any]], grounded: Bool) async throws -> T {
        let key = apiKey
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EstimatorError.badResponse
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

    /// Grounded replies come back as prose-wrapped or fenced JSON — take the
    /// outermost braces.
    private static func extractJSON(_ text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"), start < end else { return text }
        return String(text[start...end])
    }
}
