import Foundation
import Vision
import UIKit

/// On-device photo-of-food recognition using Apple's built-in Vision
/// classifier (no network, no upload). Food-related labels are matched
/// against the bundled USDA database; the user confirms dish + portion.
enum FoodPhotoRecognizer {

    struct Suggestion: Identifiable {
        let label: String            // human-readable classifier label
        let confidence: Double
        let matches: [FoodItem]      // USDA candidates for this label
        var id: String { label }
    }

    static func recognize(image: UIImage) async -> [Suggestion] {
        guard let cgImage = image.cgImage else { return [] }

        let observations: [VNClassificationObservation] = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNClassifyImageRequest()
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try? handler.perform([request])
                continuation.resume(returning: request.results ?? [])
            }
        }

        // Vision's classifier returns ~1300 classes; keep confident, food-looking ones.
        let candidates = observations
            .filter { $0.confidence > 0.15 }
            .prefix(40)
            .map { (label: $0.identifier.replacingOccurrences(of: "_", with: " "), conf: Double($0.confidence)) }
            .filter { isFoodLabel($0.label) }
            .prefix(5)

        var suggestions: [Suggestion] = []
        for c in candidates {
            let matches = FoodDatabase.shared.search(c.label, limit: 5)
            if !matches.isEmpty {
                suggestions.append(Suggestion(label: c.label.capitalized,
                                              confidence: c.conf,
                                              matches: matches))
            }
        }
        return suggestions
    }

    /// The generic classifier includes plenty of non-food classes; keep a label
    /// only if the USDA database recognizes its head noun as an actual food.
    private static func isFoodLabel(_ label: String) -> Bool {
        let nonFood: Set<String> = ["person", "people", "plate", "table", "bowl", "cup",
                                    "utensil", "fork", "knife", "spoon", "glass", "bottle",
                                    "kitchen", "restaurant", "food", "meal", "dish"]
        let l = label.lowercased()
        guard !nonFood.contains(l) else { return false }
        return !FoodDatabase.shared.search(l, limit: 1).isEmpty
    }
}
