import Foundation

/// Optional AI nutrition estimate for foods that aren't in any database
/// ("mom's lasagna"). Uses the Gemini API free tier with the user's own key
/// (Settings → AI Assist). Nothing is sent anywhere unless the user taps
/// Estimate, and only the food description goes out.
enum AIFoodEstimator {
    static let apiKeyKey = "ai.gemini.key"
    private static let model = "gemini-flash-latest"

    static var apiKey: String {
        UserDefaults.standard.string(forKey: apiKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    struct Estimate {
        let calories: Int
        let proteinGrams: Int
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

    static func estimate(food: String) async throws -> Estimate {
        let key = apiKey
        guard !key.isEmpty else { throw EstimatorError.noKey }

        var request = URLRequest(url: URL(string:
            "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")

        let prompt = """
        Estimate the nutrition for one typical serving of: "\(food)".
        Respond with only JSON: {"calories": <integer kcal>, "protein_grams": <integer grams>}
        """
        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json", "temperature": 0]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw EstimatorError.badResponse
        }

        struct GeminiResponse: Decodable {
            struct Candidate: Decodable {
                struct Content: Decodable {
                    struct Part: Decodable { let text: String? }
                    let parts: [Part]?
                }
                let content: Content?
            }
            let candidates: [Candidate]?
        }
        struct Payload: Decodable {
            let calories: Int?
            let protein_grams: Int?
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        guard let text = decoded.candidates?.first?.content?.parts?.first?.text,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(text.utf8)),
              let calories = payload.calories else {
            throw EstimatorError.badResponse
        }
        return Estimate(calories: calories, proteinGrams: payload.protein_grams ?? 0)
    }
}
