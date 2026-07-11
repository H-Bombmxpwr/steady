import Foundation
import Vision
import UIKit

/// Photo-of-food recognition. Classification runs on-device with Apple's
/// built-in Vision classifier — the photo never leaves the phone. Only the
/// resulting label text is searched against Open Food Facts for candidates.
enum FoodPhotoRecognizer {

    struct Suggestion: Identifiable {
        let label: String            // human-readable classifier label
        let confidence: Double
        let matches: [FoodItem]      // Open Food Facts candidates for this label
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
            .filter { !nonFood.contains($0.label.lowercased()) }
            .prefix(4)

        var suggestions: [Suggestion] = []
        for c in candidates {
            let matches = (try? await OpenFoodFacts.search(c.label, limit: 5)) ?? []
            if !matches.isEmpty {
                suggestions.append(Suggestion(label: c.label.capitalized,
                                              confidence: c.conf,
                                              matches: matches))
            }
        }
        return suggestions
    }

    /// Generic classes the classifier emits around food scenes that aren't
    /// themselves foods. Labels with no Open Food Facts hits are dropped too.
    private static let nonFood: Set<String> = ["person", "people", "plate", "table", "bowl",
                                               "cup", "utensil", "fork", "knife", "spoon",
                                               "glass", "bottle", "kitchen", "restaurant",
                                               "food", "meal", "dish", "snack"]
}
