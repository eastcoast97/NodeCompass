import Foundation
import CoreLocation
import MapKit

/// Resolves GPS coordinates into meaningful place names and categories.
///
/// **Primary path:** Apple `MKLocalSearch` with `MKLocalPointsOfInterestRequest` —
/// queries Apple Maps' POI database for the nearest business, with real names
/// like "Blue Bottle Coffee" and typed categories (cafe, gym, park, ...).
///
/// **Fallback path:** `CLGeocoder` reverse-geocoding when no POI is found at
/// the coordinates (typical for residential addresses). We still get a street
/// address so the event isn't empty.
///
/// Both APIs are free, keyless, and stay inside Apple's ecosystem — no network
/// calls to Google or other third-parties, matching NodeCompass's privacy-first
/// architecture.
class PlaceResolver {
    static let shared = PlaceResolver()

    private let geocoder = CLGeocoder()
    private var cache: [String: ResolvedPlace] = [:]

    /// Search radius (meters) for the POI lookup around the user's coordinates.
    /// Tight enough to target "the place you're at", wide enough to survive GPS
    /// noise inside a mall / large building.
    private let poiSearchRadius: CLLocationDistance = 75

    struct ResolvedPlace {
        let name: String
        let category: String      // "restaurant", "gym", "office", "home", "store", "medical", "park", "transit"
        let address: String?
        let placeId: String?      // Reserved for future use — currently always nil after migration off Google Places
        var details: PlaceDetails? // Legacy enrichment envelope; MKLocalSearch fills only category hints via `allTypes`
    }

    /// Legacy envelope for rich place data. Previously populated from Google
    /// Place Details API (rating, editorial summary, review-extracted menu items).
    /// After the migration to MKLocalSearch, this is typically nil — Apple's POI
    /// database doesn't expose those fields. We keep the struct shape so
    /// downstream callers (LocationCollector.enrichLocation, FoodAutoDetector)
    /// stay source-compatible.
    struct PlaceDetails {
        let priceLevel: Int?
        let rating: Double?
        let editorialSummary: String?
        let allTypes: [String]        // Apple POI category name(s) as strings
        let cuisineTypes: [String]
        let popularItems: [String]
        let website: String?
        let openNow: Bool?
    }

    private init() {}

    // MARK: - Place Resolution

    /// Resolve coordinates to a place name + category.
    /// Caches results in a ~50m grid bucket to avoid repeated lookups for the
    /// same visit.
    func resolve(latitude: Double, longitude: Double) async -> ResolvedPlace? {
        let cacheKey = "\(Int(latitude * 200))_\(Int(longitude * 200))"
        if let cached = cache[cacheKey] { return cached }

        let coord = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        // 1. Try MKLocalSearch — real business names from Apple Maps' POI index
        if let place = await resolveWithMKLocalSearch(center: coord) {
            cache[cacheKey] = place
            boundCache()
            return place
        }

        // 2. Fall back to CLGeocoder reverse-geocoding for residential addresses
        //    and coordinates with no nearby POI
        if let place = await resolveWithCLGeocoder(latitude: latitude, longitude: longitude) {
            cache[cacheKey] = place
            boundCache()
            return place
        }

        return nil
    }

    /// Resolve + enrich in one call. Retained for source compatibility with
    /// `LocationCollector` — MKLocalSearch already returns everything we know,
    /// so this is functionally identical to `resolve(...)` now.
    func resolveWithDetails(latitude: Double, longitude: Double) async -> ResolvedPlace? {
        await resolve(latitude: latitude, longitude: longitude)
    }

    // MARK: - MKLocalSearch (Apple POI index)

    private func resolveWithMKLocalSearch(center: CLLocationCoordinate2D) async -> ResolvedPlace? {
        let request = MKLocalPointsOfInterestRequest(
            center: center,
            radius: poiSearchRadius
        )
        // Exclude broad "not-really-a-place" filters so we get business results.
        // (No explicit filter — we'll rank + pick the closest POI ourselves.)

        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            guard !response.mapItems.isEmpty else { return nil }

            // Pick the closest mapItem to the search center.
            let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
            let ranked = response.mapItems.sorted { lhs, rhs in
                let lCoord = lhs.placemark.coordinate
                let rCoord = rhs.placemark.coordinate
                let lDist = origin.distance(from: CLLocation(latitude: lCoord.latitude, longitude: lCoord.longitude))
                let rDist = origin.distance(from: CLLocation(latitude: rCoord.latitude, longitude: rCoord.longitude))
                return lDist < rDist
            }

            guard let best = ranked.first else { return nil }
            return mapItemToResolved(best)
        } catch {
            print("[PlaceResolver] MKLocalSearch error: \(error.localizedDescription)")
            return nil
        }
    }

    private func mapItemToResolved(_ item: MKMapItem) -> ResolvedPlace {
        let name = item.name ?? item.placemark.name ?? "Unknown"
        let category = categoryString(for: item.pointOfInterestCategory)
        let address = formatAddress(from: item.placemark)

        // Expose the POI category tag as `allTypes` so downstream detectors
        // (FoodAutoDetector) get at least the high-level type even without
        // Google's rich data.
        let categoryTag = item.pointOfInterestCategory?.rawValue
        let details = PlaceDetails(
            priceLevel: nil,
            rating: nil,
            editorialSummary: nil,
            allTypes: categoryTag.map { [$0] } ?? [],
            cuisineTypes: [],
            popularItems: [],
            website: item.url?.absoluteString,
            openNow: nil
        )

        return ResolvedPlace(
            name: name,
            category: category,
            address: address,
            placeId: nil,
            details: details
        )
    }

    /// Map an `MKPointOfInterestCategory` to our internal string category system.
    /// Returns "other" for nil or unmapped categories.
    private func categoryString(for poi: MKPointOfInterestCategory?) -> String {
        guard let poi = poi else { return "other" }

        // Food & drink
        let food: Set<MKPointOfInterestCategory> = [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket
        ]
        if food.contains(poi) { return "restaurant" }

        // Fitness & sports
        let fitness: Set<MKPointOfInterestCategory> = [
            .fitnessCenter, .stadium
        ]
        if fitness.contains(poi) { return "gym" }

        // Shopping & stores
        let shopping: Set<MKPointOfInterestCategory> = [
            .store
        ]
        if shopping.contains(poi) { return "store" }

        // Medical
        let medical: Set<MKPointOfInterestCategory> = [
            .hospital, .pharmacy
        ]
        if medical.contains(poi) { return "medical" }

        // Transit
        let transit: Set<MKPointOfInterestCategory> = [
            .airport, .publicTransport, .parking, .evCharger, .gasStation
        ]
        if transit.contains(poi) { return "transit" }

        // Parks & outdoor
        let outdoor: Set<MKPointOfInterestCategory> = [
            .park, .beach, .campground, .nationalPark, .marina, .amusementPark
        ]
        if outdoor.contains(poi) { return "park" }

        // Education
        let education: Set<MKPointOfInterestCategory> = [
            .school, .university, .library
        ]
        if education.contains(poi) { return "education" }

        // Lodging & travel
        let lodging: Set<MKPointOfInterestCategory> = [
            .hotel
        ]
        if lodging.contains(poi) { return "travel" }

        // Entertainment
        let entertainment: Set<MKPointOfInterestCategory> = [
            .movieTheater, .museum, .nightlife, .theater, .zoo, .aquarium
        ]
        if entertainment.contains(poi) { return "entertainment" }

        return "other"
    }

    // MARK: - CLGeocoder Fallback (reverse-geocode to street address)

    private func resolveWithCLGeocoder(latitude: Double, longitude: Double) async -> ResolvedPlace? {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }

            let name = extractPlaceName(from: placemark)
            let category = inferCategoryFromPlacemark(placemark)
            let address = formatAddress(from: placemark)

            return ResolvedPlace(
                name: name,
                category: category,
                address: address,
                placeId: nil,
                details: nil
            )
        } catch {
            print("[PlaceResolver] CLGeocoder error: \(error.localizedDescription)")
            return nil
        }
    }

    private func extractPlaceName(from placemark: CLPlacemark) -> String {
        if let name = placemark.name,
           name != placemark.thoroughfare,
           name != placemark.subLocality {
            return name
        }

        if let street = placemark.thoroughfare {
            if let subLocality = placemark.subLocality {
                return "\(street), \(subLocality)"
            }
            return street
        }

        return placemark.subLocality ?? placemark.locality ?? "Unknown"
    }

    private func formatAddress(from placemark: CLPlacemark) -> String? {
        let parts = [placemark.thoroughfare, placemark.subLocality, placemark.locality]
            .compactMap { $0 }
        let joined = parts.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private func formatAddress(from placemark: MKPlacemark) -> String? {
        let parts = [placemark.thoroughfare, placemark.subLocality, placemark.locality]
            .compactMap { $0 }
        let joined = parts.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    /// Inferred category when we only have a placemark (no POI category).
    /// Keyword-based fallback — used only when MKLocalSearch returns nothing.
    private func inferCategoryFromPlacemark(_ placemark: CLPlacemark) -> String {
        let name = (placemark.name ?? "").lowercased()

        let foodKeywords = ["restaurant", "cafe", "coffee", "pizza", "burger", "sushi",
                            "taco", "grill", "diner", "bakery", "bistro", "bar",
                            "starbucks", "mcdonalds", "chipotle", "subway", "dunkin",
                            "dominos", "kfc", "wendy", "kitchen", "eatery", "food",
                            "biryani", "dhaba", "chai"]
        if foodKeywords.contains(where: { name.contains($0) }) { return "restaurant" }

        let gymKeywords = ["gym", "fitness", "yoga", "crossfit", "planet fitness",
                           "equinox", "orangetheory", "workout", "sports"]
        if gymKeywords.contains(where: { name.contains($0) }) { return "gym" }

        let shopKeywords = ["mall", "walmart", "target", "costco", "store", "shop",
                            "market", "grocery", "whole foods", "trader joe", "ikea",
                            "best buy", "outlet"]
        if shopKeywords.contains(where: { name.contains($0) }) { return "store" }

        let medKeywords = ["hospital", "clinic", "doctor", "medical", "pharmacy",
                           "urgent care", "dental", "health"]
        if medKeywords.contains(where: { name.contains($0) }) { return "medical" }

        let transitKeywords = ["station", "airport", "terminal", "metro", "bus stop",
                               "transit", "railway"]
        if transitKeywords.contains(where: { name.contains($0) }) { return "transit" }

        let parkKeywords = ["park", "garden", "trail", "beach", "lake", "nature",
                            "playground", "recreation"]
        if parkKeywords.contains(where: { name.contains($0) }) { return "park" }

        let officeKeywords = ["office", "tower", "plaza", "center", "building",
                              "corporate", "headquarters", "campus", "coworking", "wework"]
        if officeKeywords.contains(where: { name.contains($0) }) { return "office" }

        let eduKeywords = ["school", "university", "college", "academy", "library",
                           "institute", "campus"]
        if eduKeywords.contains(where: { name.contains($0) }) { return "education" }

        // If the placemark has a street address, treat as residential
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
