import Foundation

// MARK: - OpenFoodFacts barcode lookup
//
// Free public API, no key required. Decent global coverage including Indian
// brands (Britannia, Parle, Haldiram, Maggi, etc.). Returns nutrition per 100g.
//
// Endpoint: https://world.openfoodfacts.org/api/v2/product/<barcode>.json
//
// Response shape we care about:
//   {
//     "status": 1,                       // 1 = found, 0 = not found
//     "product": {
//       "product_name": "...",
//       "brands": "...",
//       "serving_size": "30g" | nil,
//       "serving_quantity": 30 | nil,    // grams per serving
//       "nutriments": {
//         "energy-kcal_100g": 380,
//         "proteins_100g": 5.2,
//         "carbohydrates_100g": 60.0,
//         "fat_100g": 12.0,
//         "fiber_100g": 2.1,
//         "sugars_100g": 25.0
//       }
//     }
//   }

actor OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let session: URLSession
    /// In-memory cache so repeat scans during a session are instant.
    private var cache: [String: BarcodeProduct] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6   // generous for slow networks
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Look up a product by EAN/UPC barcode. Returns nil when not found.
    /// Throws on network or decode errors so caller can show a retry UI.
    func lookup(barcode: String) async throws -> BarcodeProduct? {
        if let cached = cache[barcode] { return cached }

        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json") else {
            throw LookupError.invalidBarcode
        }

        var request = URLRequest(url: url)
        // Polite User-Agent per OpenFoodFacts API terms.
        request.setValue("NodeCompass-iOS/1.0 (https://nodecompass.app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LookupError.network
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard decoded.status == 1, let p = decoded.product else {
            return nil  // not found — UI falls back to manual entry
        }

        let product = BarcodeProduct(
            barcode: barcode,
            name: p.product_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Scanned Product",
            brand: p.brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines),
            servingGrams: p.serving_quantity ?? 100,   // default 100g if no serving info
            caloriesPer100g: p.nutriments?.energy_kcal_100g.map { Int($0) },
            proteinPer100g:  p.nutriments?.proteins_100g,
            carbsPer100g:    p.nutriments?.carbohydrates_100g,
            fatPer100g:      p.nutriments?.fat_100g,
            fiberPer100g:    p.nutriments?.fiber_100g
        )

        cache[barcode] = product
        return product
    }

    enum LookupError: Error, LocalizedError {
        case invalidBarcode
        case network
        var errorDescription: String? {
            switch self {
            case .invalidBarcode: return "That barcode looks invalid."
            case .network: return "Couldn't reach OpenFoodFacts. Check your connection."
            }
        }
    }

    // MARK: - API Response Models (private, decoded then mapped to public type)

    private struct APIResponse: Decodable {
        let status: Int
        let product: APIProduct?
    }

    private struct APIProduct: Decodable {
        let product_name: String?
        let brands: String?
        let serving_size: String?
        let serving_quantity: Double?
        let nutriments: APINutriments?
    }

    private struct APINutriments: Decodable {
        let energy_kcal_100g: Double?
        let proteins_100g: Double?
        let carbohydrates_100g: Double?
        let fat_100g: Double?
        let fiber_100g: Double?

        enum CodingKeys: String, CodingKey {
            case energy_kcal_100g    = "energy-kcal_100g"
            case proteins_100g       = "proteins_100g"
            case carbohydrates_100g  = "carbohydrates_100g"
            case fat_100g            = "fat_100g"
            case fiber_100g          = "fiber_100g"
        }
    }
}

// MARK: - Public model

/// A product resolved from a barcode scan. All nutrition values are
/// per-100g — caller scales to actual serving when adding to the food log.
struct BarcodeProduct: Identifiable {
    var id: String { barcode }
    let barcode: String
    let name: String
    let brand: String?
    /// Default serving size in grams (from packaging, or 100 if unknown).
    let servingGrams: Double
    let caloriesPer100g: Int?
    let proteinPer100g: Double?
    let carbsPer100g: Double?
    let fatPer100g: Double?
    let fiberPer100g: Double?

    /// Display name combining brand + product (e.g., "Britannia · Marie Gold").
    var displayName: String {
        if let brand, !brand.isEmpty { return "\(brand) · \(name)" }
        return name
    }

    /// Scale calories to a custom amount in grams.
    func calories(forGrams grams: Double) -> Int? {
        guard let cal = caloriesPer100g else { return nil }
        return Int(round(Double(cal) * grams / 100.0))
    }

    /// Scale macros to a custom amount in grams.
    func macros(forGrams grams: Double) -> Macros? {
        guard proteinPer100g != nil || carbsPer100g != nil || fatPer100g != nil else { return nil }
        let scale = grams / 100.0
        return Macros(
            protein: (proteinPer100g ?? 0) * scale,
            carbs:   (carbsPer100g ?? 0)   * scale,
            fat:     (fatPer100g ?? 0)     * scale,
            fiber:   (fiberPer100g ?? 0)   * scale
        )
    }
}
