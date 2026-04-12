import Foundation

/// Central configuration for all tunable thresholds, ratios, and constants
/// used across the Intelligence layer. Previously scattered across 12+ engines
/// as magic numbers, now centralized for easy tuning.
enum Config {

    // MARK: - Life Score Weighting
    /// Pillar weights in the total Life Score. Must sum to 1.0.
    enum LifeScoreWeights {
        static let wealth: Double = 0.30
        static let health: Double = 0.30
        static let food: Double = 0.20
        static let routine: Double = 0.20
    }

    // MARK: - Wealth Thresholds
    enum Wealth {
        /// Budget ratio (spent/budget) that scores 100.
        static let perfectBudgetRatio: Double = 0.8
        /// Budget ratio that still scores 80.
        static let goodBudgetRatio: Double = 1.0
        /// Budget ratio that scores 50.
        static let warningBudgetRatio: Double = 1.2
        /// Tolerance for "under budget" classification.
        static let underBudgetTolerance: Double = 1.05
        /// Savings rate that scores 100.
        static let perfectSavingsRate: Double = 0.5
        /// Ghost subscription detection minimum occurrences.
        static let ghostMinOccurrences: Int = 2
    }

    // MARK: - Health Thresholds
    enum Health {
        static let idealStepsPerDay: Double = 10_000
        static let lowStepsWarning: Double = 5_000
        static let idealSleepHoursMin: Double = 7.0
        static let idealSleepHoursMax: Double = 9.0
        static let sleepWarningMin: Double = 6.5
        static let athleticRestingHR: Int = 60
        static let healthyRestingHR: Int = 80
        static let idealWorkoutsPerWeek: Double = 4.0
        static let minWorkoutStreakDays: Int = 3
        /// Minimum sleep session length to count as sleep (filter out naps).
        static let minSleepSessionMinutes: Double = 60
        /// Max gap between sleep samples to merge into one session.
        static let sleepSessionMergeGapSeconds: TimeInterval = 30 * 60
    }

    // MARK: - Food Thresholds
    enum Food {
        static let idealMealsPerDay: Double = 3.0
        static let lowMealsWarning: Double = 2.5
        static let highMealsWarning: Double = 4.5
        static let idealHomeCookingRatio: Double = 0.6
        static let lowCaloriesWarning: Int = 1200
        static let highCaloriesWarning: Int = 2500
        static let lowProteinWarningGrams: Double = 40
        static let highProteinGrams: Double = 100
        static let lowFiberWarningGrams: Double = 15
        static let idealFiberGrams: Double = 27
        /// Ideal macro split (should sum to 1.0).
        static let idealProteinRatio: Double = 0.30
        static let idealCarbsRatio: Double = 0.40
        static let idealFatRatio: Double = 0.30
        /// Staple food detection: minimum occurrences in window.
        static let stapleMinOccurrences: Int = 3
        static let stapleLookbackDays: Int = 30
    }

    // MARK: - Location
    enum Location {
        /// Grid cell size in degrees (roughly 50m).
        static let gridCellMultiplier: Double = 200
        /// Cooldown between quick-visit checks.
        static let quickVisitThrottleSeconds: TimeInterval = 120
        /// Cooldown between duplicate food notifications for same place.
        static let foodNotificationCooldownSeconds: TimeInterval = 3600
        /// Max frequent locations kept in profile.
        static let maxFrequentLocations: Int = 50
        /// Radius in meters for "same place" clustering.
        static let sameLocationRadiusMeters: Double = 100
        /// Google Places Nearby Search radius (meters).
        static let googlePlacesRadius: Int = 50
    }

    // MARK: - Notifications / Nudges
    enum Notifications {
        /// Max notifications per day (except urgent).
        static let maxPerDay: Int = 3
        /// Minimum gap between notifications.
        static let minGapSeconds: TimeInterval = 2 * 3600
        /// Per-type cooldown.
        static let typeCooldownSeconds: TimeInterval = 12 * 3600
        /// Delivery log retention (must be >= typeCooldownSeconds).
        static let deliveryLogRetentionSeconds: TimeInterval = 14 * 24 * 3600
    }

    // MARK: - Mood Correlations
    enum Mood {
        /// Minimum entries required before any correlation is computed.
        static let minEntriesForCorrelation: Int = 5
        /// Minimum entries per category (e.g., "with sleep data") for a correlation.
        static let minCategoryEntries: Int = 3
        /// Mood delta (1-5 scale) considered a strong effect.
        static let strongEffectDelta: Double = 0.5
        /// Mood delta considered a moderate effect.
        static let moderateEffectDelta: Double = 0.3
        /// Number of entries for 100% confidence.
        static let maxConfidenceEntries: Double = 10
        static let activeStepsThreshold: Int = 8000
        static let sedentaryStepsThreshold: Int = 4000
        static let goodSleepHours: Double = 7
        static let badSleepHours: Double = 6
        static let highSpendMultiplier: Double = 1.5
    }

    // MARK: - Anomaly Detection
    enum Anomaly {
        /// Z-score threshold for flagging an anomaly.
        static let zScoreThreshold: Double = 2.0
        /// Z-score threshold for urgent priority.
        static let urgentZScoreThreshold: Double = 3.0
        /// Multiplier above mean to flag a first-time merchant.
        static let firstTimeMerchantMultiplier: Double = 1.5
    }

    // MARK: - Spending Trends
    enum Spending {
        /// Week-over-week change percentage to flag as notable.
        static let weeklyChangeThreshold: Double = 0.20
        /// Category spike threshold (multiplier above average).
        static let categorySpikeMultiplier: Double = 2.0
        /// Shopping spending threshold (% of total) to flag.
        static let shoppingRatioThreshold: Double = 0.15
        /// Food delivery spending threshold (% of total) to flag.
        static let foodDeliveryRatioThreshold: Double = 0.15
        /// Default budget fallback as % of income.
        static let defaultBudgetIncomeRatio: Double = 0.7
        /// Default budget conservative multiplier on current pace.
        static let conservativePaceBudgetMultiplier: Double = 1.2
        /// Pace tolerance for "over pace" classification.
        static let paceToleranceMultiplier: Double = 1.05
    }

    // MARK: - Data Retention
    enum DataRetention {
        /// EventStore rolling window.
        static let eventStoreMonths: Int = 6
        /// LifeScore history.
        static let lifeScoreHistoryDays: Int = 90
    }

    // MARK: - Unit Conversions
    enum Units {
        /// Centimeters to inches.
        static let cmPerInch: Double = 2.54
        /// Kilograms to pounds.
        static let kgPerPound: Double = 0.453_592_37
        /// Pounds per kilogram (more precise than 2.205).
        static let lbsPerKg: Double = 2.204_622_62
        /// Step to meters average (adult walking).
        static let metersPerStep: Double = 0.8
        /// Meters per kilometer.
        static let metersPerKm: Double = 1000
    }

    // MARK: - UI Timings
    enum UI {
        /// Dashboard reload debounce after transaction changes.
        static let dashboardReloadDebounceSeconds: TimeInterval = 0.5
        /// Pattern engine debounce between analysis runs.
        static let patternEngineDebounceSeconds: TimeInterval = 60
        /// Cache lifetime for nudge generation results.
        static let nudgeCacheSeconds: TimeInterval = 5 * 60
    }

    // MARK: - Currency Formatting
    enum Currency {
        /// How many unique currencies to show in a multi-currency portfolio.
        static let maxPortfolioCurrencies: Int = 5
    }
}
