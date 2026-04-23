import Foundation

// MARK: - User Profile

/// Accumulated intelligence about the user, rebuilt from events periodically by PatternEngine.
/// This is the "learned" representation — the app's understanding of who the user is.
struct UserProfile: Codable {
    var lastUpdated: Date

    // MARK: - Spending Intelligence
    var topMerchants: [MerchantProfile]
    var spendingByCategory: [String: SpendingStats]
    var monthlySpendTrend: [MonthlySpend]

    // MARK: - Location Intelligence
    var frequentLocations: [FrequentLocation]
    var locationRoutines: [DayOfWeekRoutine]

    // MARK: - Health Intelligence
    var averageDailySteps: Double
    var workoutFrequency: WorkoutFrequency?
    var typicalSleepWindow: SleepWindow?
    var outdoorMinutesPerDay: Double

    // MARK: - Food Intelligence
    var stapleFoods: [StapleFood]               // Learned repeated meals
    var averageMealsPerDay: Double
    var eatingOutFrequency: Double              // times per week
    var foodDeliveryFrequency: Double           // times per week
    var typicalMealTimes: MealSchedule?

    // MARK: - Screen Time
    var topApps: [AppUsageProfile]
    var dailyScreenTimeMinutes: Double

    // MARK: - Routines
    var dailyRoutines: [TimeBlock]

    static var empty: UserProfile {
        UserProfile(
            lastUpdated: Date(),
            topMerchants: [],
            spendingByCategory: [:],
            monthlySpendTrend: [],
            frequentLocations: [],
            locationRoutines: [],
            averageDailySteps: 0,
            workoutFrequency: nil,
            typicalSleepWindow: nil,
            outdoorMinutesPerDay: 0,
            stapleFoods: [],
            averageMealsPerDay: 0,
            eatingOutFrequency: 0,
            foodDeliveryFrequency: 0,
            typicalMealTimes: nil,
            topApps: [],
            dailyScreenTimeMinutes: 0,
            dailyRoutines: []
        )
    }
}

// MARK: - Spending Models

struct MerchantProfile: Codable, Identifiable {
    var id: String { merchant }
    let merchant: String
    let category: String
    var visitCount: Int
    var totalSpent: Double
    var averageAmount: Double
    var lastVisit: Date
    var typicalDayOfWeek: Int?       // 1=Sun...7=Sat
    var typicalTimeOfDay: Int?       // Hour 0-23
    var associatedLocationId: String?
}

struct SpendingStats: Codable {
    var totalThisMonth: Double
    var totalLastMonth: Double
    var averagePerTransaction: Double
    var transactionCount: Int
    var weekOverWeekChange: Double?   // Percentage (-0.15 = down 15%)
}

struct MonthlySpend: Codable, Identifiable {
    var id: String { month }
    let month: String                 // "2026-04"
    let total: Double
    let byCategory: [String: Double]
}

// MARK: - Location Models

struct FrequentLocation: Codable, Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    var label: String?                // "Home", "Office", "Gym" — user-editable
    var inferredType: String?         // "residence", "workplace", "restaurant", "gym"
    var visitCount: Int
    var averageDurationMinutes: Double
    var lastVisit: Date

    // MARK: - Enriched Place Intelligence (from Google Places)

    var googlePlaceId: String?        // For future detail lookups without re-searching
    var address: String?              // Full street address
    var googleTypes: [String]?        // Raw Google types: ["cannabis_store", "store", "point_of_interest"]
    var priceLevel: Int?              // 0=free, 1-4 (cheap→expensive)
    var rating: Double?               // 1.0 - 5.0 Google rating
    var editorialSummary: String?     // Google's description of the place
    var popularItems: [String]?       // Extracted from reviews (food/drink/service)

    // MARK: - Behavioral Intelligence

    var pillarTags: [String]?         // Which pillars this place affects: ["wealth", "health", "mind"]
    var behaviorTag: String?          // AI-inferred: "routine_coffee", "weekend_leisure", "impulse_buy", "fitness"
    var typicalVisitDay: Int?         // Most common day (1=Sun...7=Sat)
    var typicalVisitHour: Int?        // Most common hour (0-23)
    var totalSpent: Double?           // Correlated from transactions

    // MARK: - Visit History

    var visitDates: [Date]?           // Last N visit timestamps for pattern detection

    /// Distance in meters to another coordinate.
    func distance(to lat: Double, _ lon: Double) -> Double {
        let dLat = (lat - latitude) * .pi / 180
        let dLon = (lon - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(latitude * .pi / 180) * cos(lat * .pi / 180) *
                sin(dLon / 2) * sin(dLon / 2)
        return 6371000 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct DayOfWeekRoutine: Codable {
    let dayOfWeek: Int               // 1=Sun...7=Sat
    let blocks: [TimeBlock]
}

// MARK: - Health Models

struct WorkoutFrequency: Codable {
    var sessionsPerWeek: Double
    var preferredDays: [Int]
    var preferredTime: Int?           // Hour
    var dominantType: String          // "running", "strength", etc.
    var streakDays: Int
}

struct SleepWindow: Codable {
    var typicalBedtimeMinutes: Int    // Minutes from midnight (1380 = 11pm)
    var typicalWakeMinutes: Int
    var averageDurationHours: Double
}

// MARK: - Screen Time Models

struct AppUsageProfile: Codable, Identifiable {
    var id: String { bundleId }
    let bundleId: String
    let appName: String
    let category: String
    var dailyAverageMinutes: Double
}

// MARK: - Food Models

/// A food the user eats repeatedly — learned from food logs.
struct StapleFood: Codable, Identifiable {
    var id: String { name.lowercased() }
    let name: String                   // "Oats with banana", "Chicken biryani"
    let mealType: String               // "breakfast", "lunch", "dinner"
    var occurrences: Int
    var lastLogged: Date
    var isHomemade: Bool
    var caloriesEstimate: Int?
}

/// Typical meal times learned from logging patterns.
struct MealSchedule: Codable {
    var typicalBreakfastHour: Int?     // 0-23
    var typicalLunchHour: Int?
    var typicalDinnerHour: Int?
}

// MARK: - Routine Models

struct TimeBlock: Codable {
    let startHour: Int
    let endHour: Int
    let label: String                 // "Morning commute", "Work", "Lunch", "Gym"
    let confidence: Double            // 0.0 - 1.0
}
