import Foundation
import CoreLocation

/// Resolves GPS coordinates into meaningful place names and categories.
/// Uses Google Places API (Nearby Search) for rich business/POI data.
/// Falls back to Apple CLGeocoder when no API key is configured or on API failure.
/// API key is stored securely in the iOS Keychain.
class PlaceResolver {
    static let shared = PlaceResolver()

    private let geocoder = CLGeocoder()
    private var cache: [String: ResolvedPlace] = [:]
    private let keychainKey = "google_places_api_key"

    struct ResolvedPlace {
        let name: String
        let category: String      // "restaurant", "gym", "office", "home", "store", "medical", "park", "transit"
        let address: String?
        let placeId: String?      // Google Place ID for future lookups
        var details: PlaceDetails? // Rich data from Place Details API
    }

    /// Rich restaurant/business details from Google Places Details API.
    struct PlaceDetails {
        let priceLevel: Int?          // 0=free, 1=cheap, 2=moderate, 3=expensive, 4=very expensive
        let rating: Double?           // 1.0 - 5.0
        let editorialSummary: String? // Google's description: "Popular spot for biryani and kebabs"
        let cuisineTypes: [String]    // Specific types: ["indian_restaurant", "biryani_restaurant"]
        let popularItems: [String]    // Extracted from reviews: ["butter chicken", "naan", "mango lassi"]
        let website: String?          // Restaurant website (may have menu)
        let openNow: Bool?
    }

    private init() {}

    // MARK: - API Key Management

    var hasApiKey: Bool {
        KeychainService.shared.get(key: keychainKey) != nil
    }

    func setApiKey(_ key: String) {
        KeychainService.shared.save(key: keychainKey, value: key)
    }

    func removeApiKey() {
        KeychainService.shared.delete(key: keychainKey)
    }

    func getApiKey() -> String? {
        KeychainService.shared.get(key: keychainKey)
    }

    /// Validate a Google Places API key with a minimal request.
    func testApiKey(_ key: String) async -> (Bool, String?) {
        let urlString = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=0,0&radius=1&key=\(key)"
        guard let url = URL(string: urlString) else { return (false, "Invalid URL") }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else { return (false, "No response") }

            if httpResponse.statusCode == 200 {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String {
                    if status == "REQUEST_DENIED" {
                        let errorMsg = json["error_message"] as? String ?? "API key denied"
                        return (false, errorMsg)
                    }
                    return (true, nil)
                }
                return (true, nil)
            }
            return (false, "HTTP \(httpResponse.statusCode)")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Place Resolution

    /// Resolve coordinates to a place name and category.
    /// Uses Google Places API when available, falls back to Apple CLGeocoder.
    func resolve(latitude: Double, longitude: Double) async -> ResolvedPlace? {
        // Check cache (bucket to ~50m grid)
        let cacheKey = "\(Int(latitude * 200))_\(Int(longitude * 200))"
        if let cached = cache[cacheKey] { return cached }

        // Try Google Places API first (much better business names)
        if let apiKey = getApiKey() {
            if let place = await resolveWithGooglePlaces(latitude: latitude, longitude: longitude, apiKey: apiKey) {
                cache[cacheKey] = place
                boundCache()
                return place
            }
        }

        // Fall back to Apple CLGeocoder
        return await resolveWithApple(latitude: latitude, longitude: longitude, cacheKey: cacheKey)
    }

    // MARK: - Google Places API

    private func resolveWithGooglePlaces(latitude: Double, longitude: Double, apiKey: String) async -> ResolvedPlace? {
        // Nearby Search: finds the closest business/POI with rich name data
        let radius = 50 // 50 meters — tight radius for the place you're actually at
        let urlString = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
            + "?location=\(latitude),\(longitude)"
            + "&radius=\(radius)"
            + "&key=\(apiKey)"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  status == "OK",
                  let results = json["results"] as? [[String: Any]],
                  let best = pickBestResult(results) else {
                return nil
            }

            let name = best["name"] as? String ?? "Unknown"
            let types = best["types"] as? [String] ?? []
            let placeId = best["place_id"] as? String
            let category = mapGoogleTypesToCategory(types)
            let vicinity = best["vicinity"] as? String

            return ResolvedPlace(
                name: name,
                category: category,
                address: vicinity,
                placeId: placeId
            )
        } catch {
            print("[PlaceResolver] Google Places error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Pick the best result from Google Places results.
    /// Prioritizes establishments (businesses) over generic areas.
    private func pickBestResult(_ results: [[String: Any]]) -> [String: Any]? {
        guard !results.isEmpty else { return nil }

        // Prefer the first result that is a point_of_interest or establishment
        let preferred = results.first { result in
            let types = result["types"] as? [String] ?? []
            return types.contains("point_of_interest") || types.contains("establishment")
        }

        return preferred ?? results.first
    }

    /// Map Google Places types to our internal category system.
    private func mapGoogleTypesToCategory(_ types: [String]) -> String {
        let typeSet = Set(types)

        // Restaurant / food
        let foodTypes: Set<String> = [
            "restaurant", "food", "cafe", "bakery", "bar", "meal_delivery",
            "meal_takeaway", "night_club"
        ]
        if !typeSet.isDisjoint(with: foodTypes) { return "restaurant" }

        // Gym / fitness
        let gymTypes: Set<String> = ["gym", "stadium", "spa"]
        if !typeSet.isDisjoint(with: gymTypes) { return "gym" }

        // Shopping / store
        let storeTypes: Set<String> = [
            "store", "shopping_mall", "supermarket", "grocery_or_supermarket",
            "clothing_store", "convenience_store", "department_store",
            "electronics_store", "furniture_store", "hardware_store",
            "home_goods_store", "jewelry_store", "shoe_store", "book_store",
            "pet_store", "liquor_store"
        ]
        if !typeSet.isDisjoint(with: storeTypes) { return "store" }

        // Medical
        let medTypes: Set<String> = [
            "hospital", "doctor", "dentist", "pharmacy", "physiotherapist",
            "veterinary_care", "health"
        ]
        if !typeSet.isDisjoint(with: medTypes) { return "medical" }

        // Transit
        let transitTypes: Set<String> = [
            "airport", "bus_station", "subway_station", "train_station",
            "transit_station", "taxi_stand", "light_rail_station"
        ]
        if !typeSet.isDisjoint(with: transitTypes) { return "transit" }

        // Park / outdoor
        let parkTypes: Set<String> = [
            "park", "campground", "amusement_park", "zoo", "aquarium",
            "tourist_attraction", "natural_feature"
        ]
        if !typeSet.isDisjoint(with: parkTypes) { return "park" }

        // Education
        let eduTypes: Set<String> = [
            "school", "university", "library", "secondary_school",
            "primary_school"
        ]
        if !typeSet.isDisjoint(with: eduTypes) { return "education" }

        // Office / work
        let officeTypes: Set<String> = [
            "accounting", "insurance_agency", "lawyer", "real_estate_agency",
            "finance", "local_government_office"
        ]
        if !typeSet.isDisjoint(with: officeTypes) { return "office" }

        // Gas station
        if typeSet.contains("gas_station") { return "transport" }

        // Lodging
        if typeSet.contains("lodging") { return "travel" }

        // Place of worship
        if typeSet.contains("place_of_worship") || typeSet.contains("church") ||
           typeSet.contains("mosque") || typeSet.contains("hindu_temple") {
            return "worship"
        }

        return "other"
    }

    // MARK: - Google Place Details API

    /// Fetch rich details (price, reviews, menu hints) for a place we already resolved.
    /// Returns nil if no API key or the request fails.
    func fetchPlaceDetails(placeId: String) async -> PlaceDetails? {
        guard let apiKey = getApiKey() else { return nil }

        let fields = "price_level,rating,editorial_summary,types,reviews,website,opening_hours"
        let urlString = "https://maps.googleapis.com/maps/api/place/details/json"
            + "?place_id=\(placeId)"
            + "&fields=\(fields)"
            + "&reviews_sort=newest"
            + "&key=\(apiKey)"

        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String,
                  status == "OK",
                  let result = json["result"] as? [String: Any] else {
                return nil
            }

            let priceLevel = result["price_level"] as? Int
            let rating = result["rating"] as? Double
            let types = result["types"] as? [String] ?? []
            let website = result["website"] as? String

            // Editorial summary
            let editorialSummary: String?
            if let summary = result["editorial_summary"] as? [String: Any] {
                editorialSummary = summary["overview"] as? String
            } else {
                editorialSummary = nil
            }

            // Opening hours
            let openNow: Bool?
            if let hours = result["opening_hours"] as? [String: Any] {
                openNow = hours["open_now"] as? Bool
            } else {
                openNow = nil
            }

            // Extract popular food items from reviews
            let popularItems = extractFoodItemsFromReviews(result: result)

            // Filter to cuisine-specific types
            let cuisineTypes = types.filter { type in
                type.contains("restaurant") || type.contains("cafe") ||
                type.contains("bakery") || type.contains("coffee") ||
                type.contains("food") || type.contains("bar") ||
                type.contains("meal") || type.contains("pizza") ||
                type.contains("indian") || type.contains("chinese") ||
                type.contains("italian") || type.contains("mexican") ||
                type.contains("japanese") || type.contains("thai") ||
                type.contains("american") || type.contains("asian") ||
                type.contains("vegetarian") || type.contains("vegan") ||
                type.contains("seafood") || type.contains("steak") ||
                type.contains("ice_cream") || type.contains("dessert")
            }

            return PlaceDetails(
                priceLevel: priceLevel,
                rating: rating,
                editorialSummary: editorialSummary,
                cuisineTypes: cuisineTypes,
                popularItems: popularItems,
                website: website,
                openNow: openNow
            )
        } catch {
            print("[PlaceResolver] Place Details error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Extract commonly mentioned food items from Google Place reviews.
    private func extractFoodItemsFromReviews(result: [String: Any]) -> [String] {
        guard let reviews = result["reviews"] as? [[String: Any]] else { return [] }

        // Common food/drink keywords to look for in review text
        let foodPatterns: [String: String] = [
            // Drinks
            "coffee": "Coffee", "latte": "Latte", "cappuccino": "Cappuccino",
            "espresso": "Espresso", "mocha": "Mocha", "frappe": "Frappe",
            "chai": "Chai", "tea": "Tea", "smoothie": "Smoothie",
            "juice": "Juice", "milkshake": "Milkshake",
            // Indian
            "biryani": "Biryani", "butter chicken": "Butter Chicken",
            "naan": "Naan", "tandoori": "Tandoori", "paneer": "Paneer",
            "dosa": "Dosa", "idli": "Idli", "vada": "Vada",
            "samosa": "Samosa", "dal": "Dal", "tikka": "Tikka Masala",
            "paratha": "Paratha", "chole": "Chole Bhature",
            "rasam": "Rasam", "thali": "Thali", "kebab": "Kebab",
            "gulab jamun": "Gulab Jamun", "lassi": "Lassi",
            "pav bhaji": "Pav Bhaji", "pulao": "Pulao",
            // Western
            "burger": "Burger", "pizza": "Pizza", "pasta": "Pasta",
            "sandwich": "Sandwich", "salad": "Salad", "steak": "Steak",
            "fries": "Fries", "wrap": "Wrap", "taco": "Taco",
            "burrito": "Burrito", "wings": "Wings", "nuggets": "Nuggets",
            "waffle": "Waffle", "pancake": "Pancake", "croissant": "Croissant",
            "bagel": "Bagel", "muffin": "Muffin", "donut": "Donut",
            // Asian
            "sushi": "Sushi", "ramen": "Ramen", "noodle": "Noodles",
            "fried rice": "Fried Rice", "dim sum": "Dim Sum",
            "pad thai": "Pad Thai", "pho": "Pho", "spring roll": "Spring Rolls",
            // Desserts
            "ice cream": "Ice Cream", "gelato": "Gelato", "cake": "Cake",
            "brownie": "Brownie", "cookie": "Cookie", "pie": "Pie"
        ]

        // Count mentions across all reviews
        var itemCounts: [String: Int] = [:]

        for review in reviews {
            guard let text = review["text"] as? String else { continue }
            let lower = text.lowercased()

            for (pattern, displayName) in foodPatterns {
                if lower.contains(pattern) {
                    itemCounts[displayName, default: 0] += 1
                }
            }
        }

        // Return top items mentioned 2+ times, sorted by frequency
        return itemCounts
            .filter { $0.value >= 2 }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map { $0.key }
    }

    /// Resolve place and enrich with details in one call.
    /// Used by FoodAutoDetector for maximum intelligence.
    func resolveWithDetails(latitude: Double, longitude: Double) async -> ResolvedPlace? {
        guard var place = await resolve(latitude: latitude, longitude: longitude) else { return nil }

        // If we have a placeId and it's a food-related category, fetch rich details
        if let placeId = place.placeId,
           ["restaurant", "cafe", "food", "bar"].contains(where: { place.category.contains($0) }) {
            place.details = await fetchPlaceDetails(placeId: placeId)
        }

        return place
    }

    // MARK: - Apple CLGeocoder Fallback

    private func resolveWithApple(latitude: Double, longitude: Double, cacheKey: String) async -> ResolvedPlace? {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            let name = extractPlaceName(from: placemark)
            let category = inferCategory(from: placemark)
            let address = [placemark.thoroughfare, placemark.subLocality, placemark.locality]
                .compactMap { $0 }
                .joined(separator: ", ")

            let resolved = ResolvedPlace(
                name: name,
                category: category,
                address: address.isEmpty ? nil : address,
                placeId: nil
            )
            cache[cacheKey] = resolved
            boundCache()

            return resolved
        } catch {
            print("[PlaceResolver] Geocode error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Apple Fallback Helpers

    private func extractPlaceName(from placemark: CLPlacemark) -> String {
        // Prefer the business/POI name
        if let name = placemark.name,
           name != placemark.thoroughfare,
           name != placemark.subLocality {
            return name
        }

        // Fall back to street + area
        if let street = placemark.thoroughfare {
            if let subLocality = placemark.subLocality {
                return "\(street), \(subLocality)"
            }
            return street
        }

        return placemark.subLocality ?? placemark.locality ?? "Unknown"
    }

    private func inferCategory(from placemark: CLPlacemark) -> String {
        let name = (placemark.name ?? "").lowercased()

        // Restaurant/food keywords
        let foodKeywords = ["restaurant", "cafe", "coffee", "pizza", "burger", "sushi",
                           "taco", "grill", "diner", "bakery", "bistro", "bar",
                           "starbucks", "mcdonalds", "chipotle", "subway", "dunkin",
                           "dominos", "kfc", "wendy", "chick-fil-a", "panda express",
                           "kitchen", "eatery", "food", "biryani", "dhaba", "chai"]
        if foodKeywords.contains(where: { name.contains($0) }) {
            return "restaurant"
        }

        // Gym/fitness
        let gymKeywords = ["gym", "fitness", "yoga", "crossfit", "planet fitness",
                          "equinox", "orangetheory", "peloton", "workout", "sports"]
        if gymKeywords.contains(where: { name.contains($0) }) {
            return "gym"
        }

        // Shopping
        let shopKeywords = ["mall", "walmart", "target", "costco", "store", "shop",
                           "market", "grocery", "whole foods", "trader joe", "ikea",
                           "best buy", "amazon", "outlet"]
        if shopKeywords.contains(where: { name.contains($0) }) {
            return "store"
        }

        // Medical
        let medKeywords = ["hospital", "clinic", "doctor", "medical", "pharmacy",
                          "urgent care", "dental", "health"]
        if medKeywords.contains(where: { name.contains($0) }) {
            return "medical"
        }

        // Transit
        let transitKeywords = ["station", "airport", "terminal", "metro", "bus stop",
                              "transit", "railway"]
        if transitKeywords.contains(where: { name.contains($0) }) {
            return "transit"
        }

        // Park/outdoor
        let parkKeywords = ["park", "garden", "trail", "beach", "lake", "nature",
                           "playground", "recreation"]
        if parkKeywords.contains(where: { name.contains($0) }) {
            return "park"
        }

        // Office/work
        let officeKeywords = ["office", "tower", "plaza", "center", "building",
                             "corporate", "headquarters", "campus", "coworking", "wework"]
        if officeKeywords.contains(where: { name.contains($0) }) {
            return "office"
        }

        // Education
        let eduKeywords = ["school", "university", "college", "academy", "library",
                          "institute", "campus"]
        if eduKeywords.contains(where: { name.contains($0) }) {
            return "education"
        }

        // If it's a residential area
        if placemark.subThoroughfare != nil && placemark.thoroughfare != nil {
            return "residential"
        }

        return "other"
    }

    // MARK: - Cache Management

    private func boundCache() {
        if cache.count > 500 {
            cache.removeAll()
        }
    }
}
