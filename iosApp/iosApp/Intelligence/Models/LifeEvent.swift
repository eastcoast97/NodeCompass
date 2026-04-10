import Foundation

// MARK: - Life Event (Core Envelope)

/// A single event in the user's life timeline.
/// Envelope pattern: common metadata + typed payload.
struct LifeEvent: Codable, Identifiable {
    let id: String
    let timestamp: Date
    let source: EventSource
    let payload: EventPayload
    var metadata: EventMetadata?
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        timestamp: Date,
        source: EventSource,
        payload: EventPayload,
        metadata: EventMetadata? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.payload = payload
        self.metadata = metadata
        self.createdAt = createdAt
    }

    /// Key for deduplication — same key means same real-world event.
    var deduplicationKey: String {
        switch payload {
        case .transaction(let t):
            return "txn_\(t.transactionId)"
        case .locationVisit(let l):
            let latBucket = Int(l.latitude * 1000)
            let lonBucket = Int(l.longitude * 1000)
            let timeBucket = Int(timestamp.timeIntervalSince1970 / 300)
            return "loc_\(latBucket)_\(lonBucket)_\(timeBucket)"
        case .workout(let w):
            let timeBucket = Int(timestamp.timeIntervalSince1970 / 60)
            return "workout_\(w.activityType)_\(timeBucket)"
        case .healthSample(let h):
            let timeBucket = Int(timestamp.timeIntervalSince1970 / 3600)
            return "health_\(h.metric)_\(timeBucket)"
        case .screenTime(let s):
            let timeBucket = Int(timestamp.timeIntervalSince1970 / 3600)
            return "screen_\(s.bundleId ?? "total")_\(timeBucket)"
        case .foodLog(let f):
            let timeBucket = Int(timestamp.timeIntervalSince1970 / 1800) // 30-min buckets
            return "food_\(f.mealType)_\(timeBucket)"
        }
    }
}

// MARK: - Event Source

enum EventSource: String, Codable {
    case bank
    case email
    case location
    case healthKit
    case screenTime
    case manual
    case inferred
}

// MARK: - Event Payload (typed union)

enum EventPayload: Codable {
    case transaction(TransactionEvent)
    case locationVisit(LocationEvent)
    case workout(WorkoutEvent)
    case healthSample(HealthSampleEvent)
    case screenTime(ScreenTimeEvent)
    case foodLog(FoodLogEvent)

    private enum CodingKeys: String, CodingKey {
        case type, data
    }

    private enum PayloadType: String, Codable {
        case transaction, locationVisit, workout, healthSample, screenTime, foodLog
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .transaction(let v):
            try container.encode(PayloadType.transaction, forKey: .type)
            try container.encode(v, forKey: .data)
        case .locationVisit(let v):
            try container.encode(PayloadType.locationVisit, forKey: .type)
            try container.encode(v, forKey: .data)
        case .workout(let v):
            try container.encode(PayloadType.workout, forKey: .type)
            try container.encode(v, forKey: .data)
        case .healthSample(let v):
            try container.encode(PayloadType.healthSample, forKey: .type)
            try container.encode(v, forKey: .data)
        case .screenTime(let v):
            try container.encode(PayloadType.screenTime, forKey: .type)
            try container.encode(v, forKey: .data)
        case .foodLog(let v):
            try container.encode(PayloadType.foodLog, forKey: .type)
            try container.encode(v, forKey: .data)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .transaction:
            self = .transaction(try container.decode(TransactionEvent.self, forKey: .data))
        case .locationVisit:
            self = .locationVisit(try container.decode(LocationEvent.self, forKey: .data))
        case .workout:
            self = .workout(try container.decode(WorkoutEvent.self, forKey: .data))
        case .healthSample:
            self = .healthSample(try container.decode(HealthSampleEvent.self, forKey: .data))
        case .screenTime:
            self = .screenTime(try container.decode(ScreenTimeEvent.self, forKey: .data))
        case .foodLog:
            self = .foodLog(try container.decode(FoodLogEvent.self, forKey: .data))
        }
    }
}

// MARK: - Payload Types

/// References a StoredTransaction by ID — no data duplication.
struct TransactionEvent: Codable {
    let transactionId: String
    let amount: Double
    let merchant: String
    let category: String
    let isCredit: Bool
}

struct LocationEvent: Codable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let arrivalDate: Date
    let departureDate: Date?
    let resolvedPlaceName: String?
    let resolvedCategory: String?    // "restaurant", "gym", "office", etc.
}

struct WorkoutEvent: Codable {
    let activityType: String         // "running", "cycling", "strength", etc.
    let durationMinutes: Double
    let caloriesBurned: Double?
    let distanceMeters: Double?
}

struct HealthSampleEvent: Codable {
    let metric: String               // "steps", "heartRate", "sleepAnalysis"
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
}

struct ScreenTimeEvent: Codable {
    let bundleId: String?
    let appName: String?
    let category: String?            // "social", "entertainment", "productivity"
    let durationMinutes: Double
}

struct FoodLogEvent: Codable {
    let mealType: String             // "breakfast", "lunch", "dinner", "snack"
    let items: [FoodItem]
    let source: FoodSource           // how this entry was created
    let locationName: String?        // "Chipotle", "Home", etc.
    let totalCaloriesEstimate: Int?
    let totalMacros: Macros?         // aggregated protein, carbs, fat, fiber
    let totalSpent: Double?          // if linked to a transaction
    let transactionId: String?       // optional link to a StoredTransaction
    let portionNote: String?         // "2 out of 4 burgers", user-specified portion
}

struct FoodItem: Codable, Identifiable {
    let id: String
    let name: String
    let amount: Double               // quantity (1,2..) or weight (100g) or volume (200ml)
    let unit: FoodUnit               // qty, grams, ml
    let caloriesEstimate: Int?       // total for this item (amount * per-unit)
    let macros: Macros?              // protein, carbs, fat, fiber
    let isHomemade: Bool

    /// Backwards-compatible quantity (integer, for display/legacy)
    var quantity: Int { max(1, Int(amount)) }

    init(name: String, amount: Double = 1, unit: FoodUnit = .qty,
         caloriesEstimate: Int? = nil, macros: Macros? = nil, isHomemade: Bool = false) {
        self.id = UUID().uuidString
        self.name = name
        self.amount = amount
        self.unit = unit
        self.caloriesEstimate = caloriesEstimate
        self.macros = macros
        self.isHomemade = isHomemade
    }

    /// Legacy init for backwards compatibility (quantity as Int, no macros).
    init(name: String, quantity: Int, caloriesEstimate: Int? = nil, isHomemade: Bool = false) {
        self.id = UUID().uuidString
        self.name = name
        self.amount = Double(quantity)
        self.unit = NutritionDatabase.detectUnit(for: name)
        self.isHomemade = isHomemade
        // Auto-estimate nutrition from database
        if let est = NutritionDatabase.estimate(name: name, amount: Double(quantity), unit: self.unit) {
            self.caloriesEstimate = caloriesEstimate ?? est.calories
            self.macros = est.macros
        } else {
            self.caloriesEstimate = caloriesEstimate
            self.macros = nil
        }
    }

    // Custom decoding for backwards compatibility (old data may not have unit/macros/amount)
    enum CodingKeys: String, CodingKey {
        case id, name, amount, unit, caloriesEstimate, macros, isHomemade
        case quantity // legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isHomemade = try c.decode(Bool.self, forKey: .isHomemade)
        caloriesEstimate = try c.decodeIfPresent(Int.self, forKey: .caloriesEstimate)
        macros = try c.decodeIfPresent(Macros.self, forKey: .macros)
        unit = try c.decodeIfPresent(FoodUnit.self, forKey: .unit) ?? .qty
        // Try amount first, fall back to quantity (legacy)
        if let amt = try c.decodeIfPresent(Double.self, forKey: .amount) {
            amount = amt
        } else if let qty = try c.decodeIfPresent(Int.self, forKey: .quantity) {
            amount = Double(qty)
        } else {
            amount = 1
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(amount, forKey: .amount)
        try c.encode(unit, forKey: .unit)
        try c.encodeIfPresent(caloriesEstimate, forKey: .caloriesEstimate)
        try c.encodeIfPresent(macros, forKey: .macros)
        try c.encode(isHomemade, forKey: .isHomemade)
    }
}

enum FoodSource: String, Codable {
    case manual             // user typed it
    case emailOrder         // parsed from Uber Eats / DoorDash / Swiggy email
    case locationPrompt     // GPS detected restaurant, user confirmed
    case stapleSuggestion   // app suggested a learned staple, user confirmed
}

// MARK: - Event Metadata (enrichment added by PatternEngine)

struct EventMetadata: Codable {
    var correlatedEventIds: [String]?
    var inferredContext: String?       // "lunch at Chipotle", "morning gym session"
    var anomalyScore: Double?         // 0.0 = normal, 1.0 = very unusual
    var tags: [String]?
}
