import Foundation
import UIKit

/// Optional AI nutrition estimate for foods that aren't in any database
/// ("mom's lasagna"). Uses the Gemini API free tier with the user's own key
/// (Settings → AI Assist). Nothing is sent anywhere unless the user taps
/// Estimate, and only the food description goes out.
enum AIFoodEstimator {
    static let apiKeyKey = "ai.gemini.key"
    // Flash-Lite: no thinking pass, so answers come back in ~1 s instead of
    // 10+; plenty for a nutrition lookup, and a higher free-tier rate limit.
    private static let model = "gemini-flash-lite-latest"

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
    }

    struct MealBreakdown {
        let items: [MealItem]
        let assumed: String
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
    fats and condiments, and base values on USDA-style nutrition data.
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
        let payload: Payload = try await generate(prompt: prompt)
        let items = (payload.items ?? []).compactMap { p -> MealItem? in
            guard let name = p.name, !name.isEmpty, let calories = p.calories else { return nil }
            return MealItem(name: name, calories: calories,
                            proteinGrams: Int((p.protein_g ?? 0).rounded()),
                            grams: p.portion_grams,
                            facts: p.facts,
                            density: p.density,
                            assumed: p.assumed)
        }
        guard !items.isEmpty else { throw EstimatorError.badResponse }
        return MealBreakdown(items: items, assumed: payload.assumed ?? "")
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
        let payload: Payload = try await generate(prompt: prompt)
        guard let p = payload.food, let calories = p.calories else {
            throw EstimatorError.badResponse
        }
        return Estimate(name: p.name ?? food,
                        calories: calories,
                        proteinGrams: Int((p.protein_g ?? 0).rounded()),
                        grams: p.portion_grams,
                        facts: p.facts,
                        density: p.density,
                        assumed: payload.assumed ?? "")
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

    /// Identify a food photo and estimate its nutrition (Gemini vision).
    /// The image is downscaled and sent with the request — worth knowing,
    /// but this is a plate of food, not a progress photo.
    static func estimate(photo: UIImage) async throws -> Estimate {
        struct Payload: Decodable {
            let food: FoodPayload?
            let assumed: String?
        }
        guard let jpeg = downscaledJPEG(photo) else { throw EstimatorError.badResponse }
        let prompt = """
        Identify the food in this photo and estimate the full nutrition for \
        the portion shown. \(nutritionGuidance)
        Respond with only JSON:
        {"food": {"name": "<short food name>", \(nutritionSchema)}, \
        "assumed": "<one short sentence: what you identified and the portion size you assumed>"}
        If there is no food in the photo, use {"food": null}.
        """
        let parts: [[String: Any]] = [
            ["text": prompt],
            ["inline_data": ["mime_type": "image/jpeg",
                             "data": jpeg.base64EncodedString()]]
        ]
        let payload: Payload = try await generate(parts: parts)
        guard let p = payload.food, let name = p.name, !name.isEmpty,
              let calories = p.calories else {
            throw EstimatorError.badResponse
        }
        return Estimate(name: name,
                        calories: calories,
                        proteinGrams: Int((p.protein_g ?? 0).rounded()),
                        grams: p.portion_grams,
                        facts: p.facts,
                        density: p.density,
                        assumed: payload.assumed ?? "")
    }

    private static func downscaledJPEG(_ image: UIImage, maxDimension: CGFloat = 768) -> Data? {
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let resized = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.6)
    }

    /// One JSON-mode Gemini call; decodes the model's JSON reply into `T`.
    private static func generate<T: Decodable>(prompt: String) async throws -> T {
        try await generate(parts: [["text": prompt]])
    }

    private static func generate<T: Decodable>(parts: [[String: Any]]) async throws -> T {
        let key = apiKey
        guard !key.isEmpty else { throw EstimatorError.noKey }

        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let body: [String: Any] = [
            "contents": [["parts": parts]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EstimatorError.badResponse
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates?.first?.content?.parts?.first?.text,
              let payload = try? JSONDecoder().decode(T.self, from: Data(text.utf8)) else {
            throw EstimatorError.badResponse
        }
        return payload
    }
}
