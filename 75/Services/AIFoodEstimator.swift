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
        let calories: Int
        let proteinGrams: Int
        let assumed: String        // what food + serving the model based this on
    }

    struct ProteinEstimate {
        let gramsPer100g: Double
        let assumed: String
    }

    struct PhotoEstimate {
        let name: String
        let calories: Int
        let proteinGrams: Int
        let assumed: String
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

    /// Calories + protein for one typical serving (Custom Food "Estimate with AI").
    static func estimate(food: String) async throws -> Estimate {
        struct Payload: Decodable {
            let calories: Int?
            let protein_grams: Int?
            let assumed: String?
        }
        let prompt = """
        Estimate the nutrition for one typical serving of: "\(food)".
        Respond with only JSON:
        {"calories": <integer kcal>, "protein_grams": <integer grams>, \
        "assumed": "<one short sentence: exactly what food and serving size you assumed>"}
        """
        let payload: Payload = try await generate(prompt: prompt)
        guard let calories = payload.calories else { throw EstimatorError.badResponse }
        return Estimate(calories: calories,
                        proteinGrams: payload.protein_grams ?? 0,
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
    static func estimate(photo: UIImage) async throws -> PhotoEstimate {
        struct Payload: Decodable {
            let name: String?
            let calories: Int?
            let protein_grams: Int?
            let assumed: String?
        }
        guard let jpeg = downscaledJPEG(photo) else { throw EstimatorError.badResponse }
        let prompt = """
        Identify the food in this photo and estimate the nutrition for the \
        portion shown. Respond with only JSON:
        {"name": "<short food name>", "calories": <integer kcal>, \
        "protein_grams": <integer grams>, \
        "assumed": "<one short sentence: what you identified and the portion size you assumed>"}
        If there is no food in the photo, use {"name": null}.
        """
        let parts: [[String: Any]] = [
            ["text": prompt],
            ["inline_data": ["mime_type": "image/jpeg",
                             "data": jpeg.base64EncodedString()]]
        ]
        let payload: Payload = try await generate(parts: parts)
        guard let name = payload.name, !name.isEmpty, let calories = payload.calories else {
            throw EstimatorError.badResponse
        }
        return PhotoEstimate(name: name,
                             calories: calories,
                             proteinGrams: payload.protein_grams ?? 0,
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
