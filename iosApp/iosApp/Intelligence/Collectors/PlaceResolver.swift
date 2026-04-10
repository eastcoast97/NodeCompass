import Foundation
import CoreLocation

/// Resolves GPS coordinates into meaningful place names and categories.
/// Uses Apple's CLGeocoder + MapKit POI data. All processing is on-device.
class PlaceResolver {
    static let shared = PlaceResolver()

    private let geocoder = CLGeocoder()
    private var cache: [String: ResolvedPlace] = [:]

    struct ResolvedPlace {
        let name: String
        let category: String      // "restaurant", "gym", "office", "home", "store", "medical", "park", "transit"
        let address: String?
    }

    private init() {}

    /// Resolve coordinates to a place name and category.
    func resolve(latitude: Double, longitude: Double) async -> ResolvedPlace? {
        // Check cache (bucket to ~50m grid)
        let cacheKey = "\(Int(latitude * 200))_\(Int(longitude * 200))"
        if let cached = cache[cacheKey] { return cached }

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
                address: address.isEmpty ? nil : address
            )
            cache[cacheKey] = resolved

            // Keep cache bounded
            if cache.count > 500 {
                cache.removeAll()
            }

            return resolved
        } catch {
            print("[PlaceResolver] Geocode error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Name Extraction

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

    // MARK: - Category Inference

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

        // Office/work (heuristic: if it has "office", "tower", "building", corporate-sounding)
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
            // Has a street number — likely residential
            return "residential"
        }

        return "other"
    }
}
