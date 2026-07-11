import Foundation

/// One food, nutrients per 100 g. Sourced from Open Food Facts (text search
/// or barcode scan); custom foods are entered manually.
struct FoodItem: Codable, Identifiable, Hashable {
    let n: String          // name
    let c: Double          // kcal / 100 g
    let p: Double          // protein g / 100 g
    let f: Double          // fat g / 100 g
    let cb: Double         // carbs g / 100 g
    let pd: String?        // household portion description (e.g. "1 cup")
    let pg: Double?        // gram weight of that portion
    var pu: Bool? = nil    // true when the source had no protein value

    var id: String { n }
    var name: String { n }
    var proteinKnown: Bool { !(pu ?? false) }

    func calories(grams: Double) -> Int { Int((c * grams / 100).rounded()) }
    func protein(grams: Double) -> Int { Int((p * grams / 100).rounded()) }
}

// MARK: - Open Food Facts (barcode + text search)

struct ScannedProduct {
    let name: String
    let caloriesPer100g: Double
    let proteinPer100g: Double?
    let servingSizeText: String?
}

enum OpenFoodFacts {
    /// Fetch a product by barcode.
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
                              proteinPer100g: product.nutriments?.proteins100g,
                              servingSizeText: product.servingSize)
    }

    /// Crowd-sourced text search across ~3M products — the main food search.
    /// OFF orders by scan popularity, not text relevance, so results are
    /// re-ranked here (exact word > prefix > substring; popularity tiebreak).
    static func search(_ query: String, limit: Int = 25) async throws -> [FoodItem] {
        // US subdomain: filters to US-market products with English names
        // (the world index surfaces mostly European entries).
        var comps = URLComponents(string: "https://us.openfoodfacts.org/cgi/search.pl")!
        comps.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "sort_by", value: "unique_scans_n"),
            URLQueryItem(name: "page_size", value: "\(limit)"),
            URLQueryItem(name: "fields", value: "product_name,brands,nutriments,serving_size")
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue("75-fitness-ios - personal use", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Codable {
            struct Product: Codable {
                struct Nutriments: Codable {
                    let kcal: Double?
                    let protein: Double?
                    let fat: Double?
                    let carbs: Double?
                    enum CodingKeys: String, CodingKey {
                        case kcal = "energy-kcal_100g"
                        case protein = "proteins_100g"
                        case fat = "fat_100g"
                        case carbs = "carbohydrates_100g"
                    }
                }
                let productName: String?
                let brands: String?
                let nutriments: Nutriments?
                let servingSize: String?
                enum CodingKeys: String, CodingKey {
                    case productName = "product_name"
                    case brands
                    case nutriments
                    case servingSize = "serving_size"
                }
            }
            let products: [Product]?
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let items: [FoodItem] = (decoded.products ?? []).compactMap { p in
            guard let name = p.productName, !name.isEmpty,
                  let kcal = p.nutriments?.kcal else { return nil }
            let brand = p.brands?.split(separator: ",").first
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let display = (brand != nil && !name.localizedCaseInsensitiveContains(brand!))
                ? "\(name) — \(brand!)" : name
            return FoodItem(n: display, c: kcal,
                            p: p.nutriments?.protein ?? 0,
                            f: p.nutriments?.fat ?? 0,
                            cb: p.nutriments?.carbs ?? 0,
                            pd: p.servingSize, pg: nil,
                            pu: p.nutriments?.protein == nil)
        }

        // Re-rank by how well the name matches the query; OFF's popularity
        // order breaks ties.
        let tokens = query.lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        let scored = items.enumerated().map { index, item in
            var score = index * 10
            let name = item.n.lowercased()
            let words = name.split(whereSeparator: { !$0.isLetter }).map(String.init)
            for token in tokens {
                if words.contains(token) || words.contains(token + "s") || words.contains(token + "es") {
                    score -= 10_000
                } else if words.contains(where: { $0.hasPrefix(token) }) {
                    score -= 4_000
                } else if name.contains(token) {
                    score -= 1_000
                }
            }
            score += min(name.count, 120)
            return (item, score)
        }
        return scored.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
