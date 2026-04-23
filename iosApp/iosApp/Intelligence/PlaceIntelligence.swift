import Foundation

/// Cross-pillar place intelligence engine.
/// Takes resolved place data from Google Places and classifies it behaviorally,
/// determines which life pillars it affects, and infers behavior tags.
///
/// This is the brain that turns "you were at coordinates X,Y" into
/// "you visited your routine coffee shop (Wealth: ₹180 avg spend, Health: caffeine habit, Mind: morning ritual)".
struct PlaceIntelligence {

    // MARK: - Pillar Classification

    /// Determine which pillars a place visit is relevant to.
    /// A single visit can affect multiple pillars:
    /// - Wealth: any place where money is spent
    /// - Health: gym, restaurant (food), medical, park (outdoor activity)
    /// - Mind: routine places (stability), new places (exploration), worship, education
    static func pillarTags(
        category: String?,
        googleTypes: [String]?,
        totalSpent: Double?,
        visitCount: Int
    ) -> [String] {
        var tags: [String] = []
        let cat = category?.lowercased() ?? ""
        let types = Set(googleTypes ?? [])

        // WEALTH: any place where you spend money
        if (totalSpent ?? 0) > 0 || isSpendingCategory(cat) {
            tags.append("wealth")
        }

        // HEALTH: places that affect physical health
        if isHealthCategory(cat, types: types) {
            tags.append("health")
        }

        // MIND: places that affect mental wellbeing / routine
        if isMindCategory(cat, types: types, visitCount: visitCount) {
            tags.append("mind")
        }

        // If nothing matched, at least tag as mind (every visit is data about your routine)
        if tags.isEmpty {
            tags.append("mind")
        }

        return tags
    }

    // MARK: - Behavior Tag Inference

    /// Infer a behavioral tag for the place based on all available signals.
    /// These tags help the AI coach and cross-source analyzer understand
    /// what role this place plays in the user's life.
    static func inferBehaviorTag(
        category: String?,
        googleTypes: [String]?,
        visitCount: Int,
        typicalVisitHour: Int?,
        typicalVisitDay: Int?,
        totalSpent: Double?,
        rating: Double?,
        priceLevel: Int?
    ) -> String {
        let cat = category?.lowercased() ?? ""
        let types = Set(googleTypes ?? [])
        let hour = typicalVisitHour ?? -1
        let isRoutine = visitCount >= 3

        // Food & Drink
        if cat == "restaurant" || types.contains("restaurant") || types.contains("cafe") {
            if types.contains("cafe") || types.contains("coffee_shop") ||
               types.containsAny(["coffee", "tea"]) {
                return isRoutine ? "routine_coffee" : "occasional_coffee"
            }
            if types.containsAny(["meal_delivery", "meal_takeaway"]) {
                return "food_delivery"
            }
            if types.contains("bar") || types.contains("night_club") {
                return "nightlife"
            }
            if types.contains("bakery") {
                return isRoutine ? "routine_snack" : "occasional_treat"
            }
            // General restaurant
            if isRoutine {
                return hour >= 6 && hour <= 10 ? "routine_breakfast" :
                       hour >= 11 && hour <= 14 ? "routine_lunch" :
                       hour >= 17 && hour <= 22 ? "routine_dinner" :
                       "routine_dining"
            }
            return "occasional_dining"
        }

        // Fitness
        if cat == "gym" || types.containsAny(["gym", "spa", "stadium"]) {
            return isRoutine ? "routine_fitness" : "occasional_fitness"
        }

        // Shopping
        if cat == "store" || types.contains("store") || types.contains("shopping_mall") {
            if types.containsAny(["supermarket", "grocery_or_supermarket"]) {
                return isRoutine ? "routine_grocery" : "occasional_grocery"
            }
            if types.containsAny(["convenience_store"]) {
                return "quick_errand"
            }
            // Cannabis/dispensary
            if types.containsAny(["cannabis_store"]) {
                return isRoutine ? "routine_dispensary" : "occasional_dispensary"
            }
            // Liquor/wine
            if types.containsAny(["liquor_store"]) {
                return isRoutine ? "routine_liquor" : "occasional_liquor"
            }
            // High spend + low frequency = impulse buy
            if !isRoutine && (totalSpent ?? 0) > 0 {
                return "impulse_buy"
            }
            return isRoutine ? "routine_shopping" : "occasional_shopping"
        }

        // Medical
        if cat == "medical" || types.containsAny(["hospital", "doctor", "dentist", "pharmacy"]) {
            if types.contains("pharmacy") {
                return isRoutine ? "routine_pharmacy" : "pharmacy_visit"
            }
            return "medical_visit"
        }

        // Transit
        if cat == "transit" || types.containsAny(["transit_station", "bus_station", "subway_station", "train_station"]) {
            return isRoutine ? "daily_commute" : "transit"
        }

        // Park / Outdoor
        if cat == "park" || types.containsAny(["park", "campground", "natural_feature"]) {
            return isRoutine ? "routine_outdoor" : "weekend_leisure"
        }

        // Education
        if cat == "education" || types.containsAny(["school", "university", "library"]) {
            return isRoutine ? "daily_study" : "learning"
        }

        // Office / Work
        if cat == "office" {
            return isRoutine ? "daily_work" : "work_visit"
        }

        // Worship
        if cat == "worship" || types.contains("place_of_worship") {
            return isRoutine ? "routine_worship" : "occasional_worship"
        }

        // Travel / Lodging
        if cat == "travel" || types.contains("lodging") {
            return "travel"
        }

        // Gas station / transport
        if cat == "transport" || types.contains("gas_station") {
            return isRoutine ? "routine_fuel" : "fuel_stop"
        }

        // Default
        return isRoutine ? "frequent_visit" : "one_off_visit"
    }

    // MARK: - Typical Visit Patterns

    /// Calculate typical visit day from visit dates.
    /// Returns 1=Sun...7=Sat (matching Calendar.component(.weekday)).
    static func typicalVisitDay(from dates: [Date]) -> Int? {
        guard dates.count >= 2 else { return nil }
        let cal = Calendar.current
        var dayCounts: [Int: Int] = [:]
        for date in dates {
            let weekday = cal.component(.weekday, from: date)
            dayCounts[weekday, default: 0] += 1
        }
        return dayCounts.max(by: { $0.value < $1.value })?.key
    }

    /// Calculate typical visit hour from visit dates.
    /// Returns 0-23.
    static func typicalVisitHour(from dates: [Date]) -> Int? {
        guard dates.count >= 2 else { return nil }
        let cal = Calendar.current
        var hourCounts: [Int: Int] = [:]
        for date in dates {
            let hour = cal.component(.hour, from: date)
            hourCounts[hour, default: 0] += 1
        }
        return hourCounts.max(by: { $0.value < $1.value })?.key
    }

    // MARK: - Cross-Pillar Signals

    /// Generate cross-pillar insight signals from a place visit.
    /// These are used by PatternEngine / AI Coach to connect dots.
    static func crossPillarSignals(
        place: FrequentLocation,
        recentSpend: Double?
    ) -> [PlaceSignal] {
        var signals: [PlaceSignal] = []
        let cat = place.inferredType?.lowercased() ?? ""
        let tags = place.pillarTags ?? []

        // Wealth signals
        if tags.contains("wealth") {
            if let spent = recentSpend ?? place.totalSpent, spent > 0 {
                signals.append(.spending(merchant: place.label ?? "Unknown", amount: spent))
            }
        }

        // Health signals
        if tags.contains("health") {
            if cat == "gym" {
                signals.append(.workout(location: place.label ?? "Gym"))
            }
            if cat == "restaurant" {
                signals.append(.mealOut(restaurant: place.label ?? "Restaurant",
                                       popularItems: place.popularItems ?? []))
            }
            if cat == "park" {
                signals.append(.outdoorActivity(location: place.label ?? "Park",
                                                durationMinutes: place.averageDurationMinutes))
            }
            if cat == "medical" {
                signals.append(.medicalVisit(location: place.label ?? "Clinic"))
            }
        }

        // Mind signals
        if tags.contains("mind") {
            let behaviorTag = place.behaviorTag ?? ""
            if behaviorTag.hasPrefix("routine_") {
                signals.append(.routineConfirmed(activity: behaviorTag, location: place.label ?? ""))
            }
            if behaviorTag == "nightlife" {
                signals.append(.nightlife(location: place.label ?? ""))
            }
        }

        return signals
    }

    // MARK: - Private Helpers

    private static func isSpendingCategory(_ cat: String) -> Bool {
        ["restaurant", "store", "gym", "medical", "transport", "travel"].contains(cat)
    }

    private static func isHealthCategory(_ cat: String, types: Set<String>) -> Bool {
        if ["gym", "restaurant", "medical", "park"].contains(cat) { return true }
        if types.containsAny(["gym", "spa", "hospital", "doctor", "pharmacy",
                               "park", "campground", "restaurant", "cafe",
                               "bakery", "food"]) { return true }
        return false
    }

    private static func isMindCategory(_ cat: String, types: Set<String>, visitCount: Int) -> Bool {
        // Routine places (3+ visits) always affect mind (stability/habit)
        if visitCount >= 3 { return true }
        // Education, worship, parks always mind-relevant
        if ["education", "worship", "park"].contains(cat) { return true }
        if types.containsAny(["library", "book_store", "school", "university",
                               "place_of_worship", "park"]) { return true }
        return false
    }
}

// MARK: - Place Signal (Cross-Pillar Events)

/// A signal emitted by PlaceIntelligence for other engines to consume.
/// PatternEngine, AI Coach, and NotificationEngine can act on these.
enum PlaceSignal {
    case spending(merchant: String, amount: Double)
    case workout(location: String)
    case mealOut(restaurant: String, popularItems: [String])
    case outdoorActivity(location: String, durationMinutes: Double)
    case medicalVisit(location: String)
    case routineConfirmed(activity: String, location: String)
    case nightlife(location: String)
}

// MARK: - Set Extension

private extension Set where Element == String {
    func containsAny(_ items: [String]) -> Bool {
        !self.isDisjoint(with: Set(items))
    }
}
