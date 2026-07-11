import Foundation
import SwiftUI

/// Noom-style calorie-density buckets: green under 1 kcal/g, orange up to
/// 2.4, red above. Computed from per-100g data, or supplied by the AI for
/// described meals.
enum FoodDensity: String {
    case green, orange, red

    init?(caloriesPer100g: Double) {
        guard caloriesPer100g > 0 else { return nil }
        switch caloriesPer100g / 100 {
        case ..<1.0: self = .green
        case ..<2.4: self = .orange
        default: self = .red
        }
    }

    var color: Color {
        switch self {
        case .green: return .green
        case .orange: return .orange
        case .red: return .red
        }
    }

    var label: String {
        switch self {
        case .green: return "Green — low calorie density"
        case .orange: return "Orange — moderate calorie density"
        case .red: return "Red — high calorie density"
        }
    }
}

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
    var micro: Micro? = nil

    /// Extended nutrients per 100 g, when the source knows them.
    struct Micro: Codable, Hashable {
        var satFatG: Double = 0
        var transFatG: Double = 0
        var cholesterolMg: Double = 0
        var sodiumMg: Double = 0
        var fiberG: Double = 0
        var sugarG: Double = 0
        var potassiumMg: Double = 0
        var calciumMg: Double = 0
        var ironMg: Double = 0
    }

    var id: String { n }
    var name: String { n }
    var proteinKnown: Bool { !(pu ?? false) }
    var densityBucket: FoodDensity? { FoodDensity(caloriesPer100g: c) }

    func calories(grams: Double) -> Int { Int((c * grams / 100).rounded()) }
    func protein(grams: Double) -> Int { Int((p * grams / 100).rounded()) }

    func facts(grams: Double) -> NutritionFacts {
        let m = micro ?? Micro()
        return NutritionFacts(carbsGrams: cb, fatGrams: f,
                              saturatedFatGrams: m.satFatG,
                              transFatGrams: m.transFatG,
                              cholesterolMg: m.cholesterolMg,
                              sodiumMg: m.sodiumMg,
                              fiberGrams: m.fiberG,
                              sugarGrams: m.sugarG,
                              addedSugarGrams: 0,   // OFF rarely splits added sugar out
                              potassiumMg: m.potassiumMg,
                              calciumMg: m.calciumMg,
                              ironMg: m.ironMg)
            .scaled(by: grams / 100)
    }
}

// MARK: - Open Food Facts (barcode + text search)

enum OpenFoodFacts {
    enum OFFError: LocalizedError {
        case rateLimited, unreachable
        var errorDescription: String? {
            switch self {
            case .rateLimited:
                return "Open Food Facts is rate-limiting — wait a few seconds, then try again."
            case .unreachable:
                return "Couldn't reach Open Food Facts — check your connection, or use Custom Food."
            }
        }
    }

    /// Per-100g nutrient block shared by barcode lookup and text search.
    /// OFF reports cholesterol/sodium/potassium/calcium/iron in grams.
    private struct Nutriments: Codable {
        let kcal: Double?
        let protein: Double?
        let fat: Double?
        let carbs: Double?
        let satFat: Double?
        let transFat: Double?
        let cholesterol: Double?
        let sodium: Double?
        let fiber: Double?
        let sugars: Double?
        let potassium: Double?
        let calcium: Double?
        let iron: Double?
        enum CodingKeys: String, CodingKey {
            case kcal = "energy-kcal_100g"
            case protein = "proteins_100g"
            case fat = "fat_100g"
            case carbs = "carbohydrates_100g"
            case satFat = "saturated-fat_100g"
            case transFat = "trans-fat_100g"
            case cholesterol = "cholesterol_100g"
            case sodium = "sodium_100g"
            case fiber = "fiber_100g"
            case sugars = "sugars_100g"
            case potassium = "potassium_100g"
            case calcium = "calcium_100g"
            case iron = "iron_100g"
        }

        var micro: FoodItem.Micro {
            FoodItem.Micro(satFatG: satFat ?? 0,
                           transFatG: transFat ?? 0,
                           cholesterolMg: (cholesterol ?? 0) * 1000,
                           sodiumMg: (sodium ?? 0) * 1000,
                           fiberG: fiber ?? 0,
                           sugarG: sugars ?? 0,
                           potassiumMg: (potassium ?? 0) * 1000,
                           calciumMg: (calcium ?? 0) * 1000,
                           ironMg: (iron ?? 0) * 1000)
        }
    }

    private static let nutrimentFields =
        "product_name,brands,nutriments,serving_size"

    /// Fetch a product by barcode.
    static func lookup(barcode: String) async throws -> FoodItem? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(nutrimentFields)")!
        var request = URLRequest(url: url)
        request.setValue("75-fitness-ios - personal use", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)

        struct Response: Codable {
            struct Product: Codable {
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
              let nutriments = product.nutriments,
              let kcal = nutriments.kcal else { return nil }
        return FoodItem(n: product.productName ?? "Scanned item",
                        c: kcal,
                        p: nutriments.protein ?? 0,
                        f: nutriments.fat ?? 0,
                        cb: nutriments.carbs ?? 0,
                        pd: product.servingSize, pg: nil,
                        pu: nutriments.protein == nil,
                        micro: nutriments.micro)
    }

    // Session cache + retry: OFF's search endpoint 503s intermittently, so
    // transient failures retry silently and repeat queries never refetch.
    private static var cache: [String: [FoodItem]] = [:]
    private static let cacheLock = NSLock()

    /// Crowd-sourced text search across ~3M products — the main food search.
    /// Retries transient server errors (backoff) before surfacing anything.
    static func search(_ query: String, limit: Int = 25) async throws -> [FoodItem] {
        cacheLock.lock()
        let cached = cache[query]
        cacheLock.unlock()
        if let cached { return cached }

        var lastError: Error = OFFError.unreachable
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_500_000_000)
            }
            try Task.checkCancellation()
            do {
                let items = try await performSearch(query, limit: limit)
                cacheLock.lock()
                cache[query] = items
                cacheLock.unlock()
                return items
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// OFF orders by scan popularity, not text relevance, so results are
    /// re-ranked here (exact word > prefix > substring; popularity tiebreak).
    private static func performSearch(_ query: String, limit: Int) async throws -> [FoodItem] {
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
            URLQueryItem(name: "fields", value: nutrimentFields)
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 10
        request.setValue("75-fitness-ios - personal use", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw http.statusCode == 429 ? OFFError.rateLimited : OFFError.unreachable
        }

        struct Response: Codable {
            struct Product: Codable {
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
                            pu: p.nutriments?.protein == nil,
                            micro: p.nutriments?.micro)
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
