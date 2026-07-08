import Foundation

/// One food from the bundled USDA SR Legacy extract. Nutrients are per 100 g.
struct FoodItem: Codable, Identifiable, Hashable {
    let n: String          // name
    let c: Double          // kcal / 100 g
    let p: Double          // protein g / 100 g
    let f: Double          // fat g / 100 g
    let cb: Double         // carbs g / 100 g
    let pd: String?        // household portion description (e.g. "1 cup")
    let pg: Double?        // gram weight of that portion

    var id: String { n }
    var name: String { n }

    func calories(grams: Double) -> Int { Int((c * grams / 100).rounded()) }
    func protein(grams: Double) -> Int { Int((p * grams / 100).rounded()) }
}

/// Bundled offline food database (7,793 USDA SR Legacy foods, ~1 MB JSON).
/// Loaded lazily off the main thread on first search.
final class FoodDatabase {
    static let shared = FoodDatabase()

    private var _foods: [FoodItem]?
    private let lock = NSLock()

    var foods: [FoodItem] {
        lock.lock(); defer { lock.unlock() }
        if let f = _foods { return f }
        let loaded = Self.load()
        _foods = loaded
        return loaded
    }

    private static func load() -> [FoodItem] {
        guard let url = Bundle.main.url(forResource: "Foods", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([FoodItem].self, from: data) else {
            return []
        }
        return items
    }

    /// All query tokens must appear in the name; results ranked by how early
    /// the first token appears, then by name length (shorter = more generic).
    func search(_ query: String, limit: Int = 60) -> [FoodItem] {
        let tokens = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }

        var scored: [(FoodItem, Int)] = []
        for item in foods {
            let name = item.n.lowercased()
            guard tokens.allSatisfy({ name.contains($0) }) else { continue }
            let position = name.range(of: tokens[0])?.lowerBound.utf16Offset(in: name) ?? 999
            scored.append((item, position * 1000 + name.count))
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map { $0.0 }
    }
}

// MARK: - Open Food Facts barcode lookup

struct ScannedProduct {
    let name: String
    let caloriesPer100g: Double
    let proteinPer100g: Double
    let servingSizeText: String?
}

enum OpenFoodFacts {
    /// Fetch a product by barcode. Only used when the user scans — regular
    /// search stays fully offline.
    static func lookup(barcode: String) async throws -> ScannedProduct? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,nutriments,serving_size")!
        var request = URLRequest(url: url)
        request.setValue("75-fitness-ios - personal use", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Codable {
            struct Product: Codable {
                struct Nutriments: Codable {
                    let energyKcal100g: Double?
                    let proteins100g: Double?
                    enum CodingKeys: String, CodingKey {
                        case energyKcal100g = "energy-kcal_100g"
                        case proteins100g = "proteins_100g"
                    }
                }
                let productName: String?
                let nutriments: Nutriments?
                let servingSize: String?
                enum CodingKeys: String, CodingKey {
                    case productName = "product_name"
                    case nutriments
                    case servingSize = "serving_size"
                }
            }
            let status: Int
            let product: Product?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard decoded.status == 1,
              let product = decoded.product,
              let kcal = product.nutriments?.energyKcal100g else { return nil }
        return ScannedProduct(name: product.productName ?? "Scanned item",
                              caloriesPer100g: kcal,
                              proteinPer100g: product.nutriments?.proteins100g ?? 0,
                              servingSizeText: product.servingSize)
    }
}
