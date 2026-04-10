import Foundation

/// Persistent store for food log entries.
/// Handles storage, staple learning, and auto-detection from emails/location.
actor FoodStore {
    static let shared = FoodStore()

    private(set) var entries: [FoodLogEntry] = []
    private let fileName = "food_log.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
        cleanupBadEntries()
        deduplicatePendingEntries()
    }

    /// Remove duplicate pending food log entries (same transactionId or same amount+date).
    private func deduplicatePendingEntries() {
        var seenTxnIds = Set<String>()
        var indicesToRemove: [Int] = []

        for (idx, entry) in entries.enumerated() {
            if let txnId = entry.transactionId {
                if seenTxnIds.contains(txnId) {
                    indicesToRemove.append(idx)
                } else {
                    seenTxnIds.insert(txnId)
                }
            }
        }

        if !indicesToRemove.isEmpty {
            for idx in indicesToRemove.reversed() {
                entries.remove(at: idx)
            }
            saveToDisk()
        }
    }

    /// Remove entries where items are addresses (from bad LLM parsing).
    /// Also convert entries with address-items into pending entries (empty items).
    private func cleanupBadEntries() {
        var changed = false
        for i in entries.indices {
            let entry = entries[i]
            guard !entry.items.isEmpty else { continue }

            // Check if items look like addresses
            let validItems = entry.items.filter { item in
                !SwiftEmailReceiptParser.looksLikeAddress(item.name)
            }

            if validItems.count < entry.items.count {
                // Some items were addresses — replace with only valid ones (or empty)
                let updated = FoodLogEntry(
                    mealType: entry.mealType,
                    items: validItems,
                    source: entry.source,
                    locationName: entry.locationName,
                    totalCaloriesEstimate: validItems.isEmpty ? nil : entry.totalCaloriesEstimate,
                    totalMacros: validItems.isEmpty ? nil : entry.totalMacros,
                    totalSpent: entry.totalSpent,
                    transactionId: entry.transactionId,
                    portionNote: entry.portionNote
                )
                entries[i] = updated
                changed = true
            }
        }
        if changed { saveToDisk() }
    }

    // MARK: - Core Data Model (on-disk)

    struct FoodLogEntry: Codable, Identifiable {
        let id: String
        let timestamp: Date
        let mealType: String
        let items: [FoodItem]
        let source: FoodSource
        let locationName: String?
        let locationAddress: String?
        let totalCaloriesEstimate: Int?
        let totalMacros: Macros?
        let totalSpent: Double?
        let transactionId: String?
        let portionNote: String?

        enum CodingKeys: String, CodingKey {
            case id, timestamp, mealType, items, source, locationName, locationAddress
            case totalCaloriesEstimate, totalMacros, totalSpent, transactionId, portionNote
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            timestamp = try c.decode(Date.self, forKey: .timestamp)
            mealType = try c.decode(String.self, forKey: .mealType)
            items = try c.decode([FoodItem].self, forKey: .items)
            source = try c.decode(FoodSource.self, forKey: .source)
            locationName = try c.decodeIfPresent(String.self, forKey: .locationName)
            locationAddress = try c.decodeIfPresent(String.self, forKey: .locationAddress)
            totalCaloriesEstimate = try c.decodeIfPresent(Int.self, forKey: .totalCaloriesEstimate)
            totalMacros = try c.decodeIfPresent(Macros.self, forKey: .totalMacros)
            totalSpent = try c.decodeIfPresent(Double.self, forKey: .totalSpent)
            transactionId = try c.decodeIfPresent(String.self, forKey: .transactionId)
            portionNote = try c.decodeIfPresent(String.self, forKey: .portionNote)
        }

        init(
            mealType: String,
            items: [FoodItem],
            source: FoodSource,
            locationName: String? = nil,
            locationAddress: String? = nil,
            totalCaloriesEstimate: Int? = nil,
            totalMacros: Macros? = nil,
            totalSpent: Double? = nil,
            transactionId: String? = nil,
            portionNote: String? = nil
        ) {
            self.id = UUID().uuidString
            self.timestamp = Date()
            self.mealType = mealType
            self.items = items
            self.source = source
            self.locationName = locationName
            self.locationAddress = locationAddress
            self.totalCaloriesEstimate = totalCaloriesEstimate
            self.totalMacros = totalMacros
            self.totalSpent = totalSpent
            self.transactionId = transactionId
            self.portionNote = portionNote
        }
    }

    // MARK: - Add Entry

    func addEntry(_ entry: FoodLogEntry) {
        entries.append(entry)
        saveToDisk()

        // Also store as LifeEvent
        // Aggregate macros from items
        let totalMacros = entry.items.compactMap { $0.macros }.reduce(Macros.zero, +)

        let foodEvent = FoodLogEvent(
            mealType: entry.mealType,
            items: entry.items,
            source: entry.source,
            locationName: entry.locationName,
            totalCaloriesEstimate: entry.totalCaloriesEstimate,
            totalMacros: totalMacros == .zero ? nil : totalMacros,
            totalSpent: entry.totalSpent,
            transactionId: entry.transactionId,
            portionNote: entry.portionNote
        )
        let lifeEvent = LifeEvent(
            timestamp: entry.timestamp,
            source: entry.source == .manual || entry.source == .stapleSuggestion ? .manual : .email,
            payload: .foodLog(foodEvent)
        )
        Task { await EventStore.shared.append(lifeEvent) }
    }

    // MARK: - Queries

    func entriesForToday() -> [FoodLogEntry] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        return entries.filter { $0.timestamp >= startOfDay }
    }

    func entriesForWeek() -> [FoodLogEntry] {
        let startOfWeek = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return entries.filter { $0.timestamp >= startOfWeek }
    }

    func entries(for date: Date) -> [FoodLogEntry] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start)!
        return entries.filter { $0.timestamp >= start && $0.timestamp < end }
    }

    func entries(since date: Date) -> [FoodLogEntry] {
        entries.filter { $0.timestamp >= date }
    }

    /// Find a food log entry by its linked transaction ID.
    func entryForTransaction(id: String) -> FoodLogEntry? {
        entries.first { $0.transactionId == id }
    }

    /// Pending food logs — detected food orders where the user hasn't added items yet.
    func pendingEntries() -> [FoodLogEntry] {
        entries.filter { $0.items.isEmpty && $0.source == .emailOrder }
    }

    /// Update a pending entry with actual food items.
    func completePendingEntry(id: String, items: [FoodItem], mealType: String, portionNote: String?) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        let old = entries[idx]
        let totalCal = items.compactMap { $0.caloriesEstimate }.reduce(0, +)
        let totalMacros = items.compactMap { $0.macros }.reduce(Macros.zero, +)

        let updated = FoodLogEntry(
            mealType: mealType,
            items: items,
            source: old.source,
            locationName: old.locationName,
            totalCaloriesEstimate: totalCal > 0 ? totalCal : nil,
            totalMacros: totalMacros == .zero ? nil : totalMacros,
            totalSpent: old.totalSpent,
            transactionId: old.transactionId,
            portionNote: portionNote
        )
        entries[idx] = updated
        saveToDisk()
    }

    var todayMealTypes: Set<String> {
        Set(entriesForToday().map { $0.mealType })
    }

    var todayCalories: Int {
        entriesForToday().compactMap { $0.totalCaloriesEstimate }.reduce(0, +)
    }

    // MARK: - Staple Food Detection

    /// Analyze logs to find staple foods (items eaten 3+ times in last 30 days).
    func detectStapleFoods() -> [StapleFood] {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let recentEntries = entries.filter { $0.timestamp >= thirtyDaysAgo }

        // Count item occurrences by name + meal type
        var itemCounts: [String: (count: Int, mealType: String, lastDate: Date, isHomemade: Bool, calories: Int?)] = [:]

        for entry in recentEntries {
            for item in entry.items {
                let key = item.name.lowercased()
                if let existing = itemCounts[key] {
                    itemCounts[key] = (
                        existing.count + item.quantity,
                        entry.mealType,
                        max(existing.lastDate, entry.timestamp),
                        item.isHomemade || existing.isHomemade,
                        item.caloriesEstimate ?? existing.calories
                    )
                } else {
                    itemCounts[key] = (item.quantity, entry.mealType, entry.timestamp, item.isHomemade, item.caloriesEstimate)
                }
            }
        }

        return itemCounts
            .filter { $0.value.count >= 3 }
            .map { key, value in
                StapleFood(
                    name: key.capitalized,
                    mealType: value.mealType,
                    occurrences: value.count,
                    lastLogged: value.lastDate,
                    isHomemade: value.isHomemade,
                    caloriesEstimate: value.calories
                )
            }
            .sorted { $0.occurrences > $1.occurrences }
    }

    /// Get staple food suggestions for a given meal type and time.
    func stapleSuggestions(for mealType: String) -> [StapleFood] {
        detectStapleFoods().filter { $0.mealType == mealType }.prefix(5).map { $0 }
    }

    /// Get past food items ordered from a specific restaurant (by locationName).
    /// Returns unique item names sorted by frequency, most common first.
    func pastItemsFromRestaurant(_ restaurant: String) -> [String] {
        let lowerRestaurant = restaurant.lowercased()
        let matchingEntries = entries.filter {
            $0.locationName?.lowercased() == lowerRestaurant && !$0.items.isEmpty
        }
        // Count item occurrences
        var counts: [String: Int] = [:]
        for entry in matchingEntries {
            for item in entry.items {
                let key = item.name.lowercased()
                counts[key, default: 0] += 1
            }
        }
        return counts
            .sorted { $0.value > $1.value }
            .map { $0.key.capitalized }
    }

    // MARK: - Bulk Order Detection

    /// Given line items from an email order, detect which are likely bulk (qty > 1)
    /// and return items that need portion confirmation.
    static func detectBulkItems(lineItems: [LineItem]) -> [LineItem] {
        lineItems.filter { $0.quantity > 1 }
    }

    /// Given line items, determine which look like food vs non-food.
    static func filterFoodItems(lineItems: [LineItem], merchant: String) -> [LineItem] {
        let foodMerchants = ["swiggy", "zomato", "uber eats", "doordash", "grubhub",
                             "deliveroo", "postmates", "instacart", "dunzo", "blinkit"]
        let isFoodMerchant = foodMerchants.contains { merchant.lowercased().contains($0) }

        if isFoodMerchant {
            // All items from food delivery are food
            return lineItems
        }

        // For mixed merchants (Amazon, Flipkart), filter by food keywords
        let foodKeywords = ["chicken", "burger", "pizza", "rice", "noodle", "biryani",
                            "sandwich", "salad", "wrap", "taco", "curry", "dal", "roti",
                            "dosa", "idli", "paneer", "fish", "prawn", "egg", "milk",
                            "juice", "coffee", "tea", "smoothie", "cake", "ice cream",
                            "chocolate", "snack", "chips", "bread", "fruit", "vegetable"]
        return lineItems.filter { item in
            foodKeywords.contains { item.name.lowercased().contains($0) }
        }
    }

    // MARK: - Auto-Log from Email Orders

    /// Create a food log entry from parsed email receipt (Uber Eats, Swiggy, etc.)
    func createFromEmailOrder(
        merchant: String,
        address: String? = nil,
        lineItems: [LineItem],
        totalAmount: Double,
        transactionId: String,
        userPortions: [String: Int]? = nil // item name → how many user ate (for bulk)
    ) -> FoodLogEntry {
        let foodItems = lineItems.map { item -> FoodItem in
            let qty = userPortions?[item.name] ?? item.quantity
            return FoodItem(
                name: item.name,
                quantity: qty,
                caloriesEstimate: estimateCalories(for: item.name, quantity: qty),
                isHomemade: false
            )
        }

        let mealType = inferMealType(from: Date())
        let totalCal = foodItems.compactMap { $0.caloriesEstimate }.reduce(0, +)
        let totalMacros = foodItems.compactMap { $0.macros }.reduce(Macros.zero, +)

        return FoodLogEntry(
            mealType: mealType,
            items: foodItems,
            source: .emailOrder,
            locationName: merchant,
            locationAddress: address,
            totalCaloriesEstimate: totalCal > 0 ? totalCal : nil,
            totalMacros: totalMacros == .zero ? nil : totalMacros,
            totalSpent: totalAmount,
            transactionId: transactionId
        )
    }

    // MARK: - Auto-Log from Location

    /// Create a pending food log from a restaurant GPS visit.
    func createFromLocationVisit(restaurantName: String, arrivalDate: Date) -> FoodLogEntry {
        let mealType = inferMealType(from: arrivalDate)
        return FoodLogEntry(
            mealType: mealType,
            items: [], // user will add items
            source: .locationPrompt,
            locationName: restaurantName
        )
    }

    // MARK: - Helpers

    func inferMealType(from date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return "breakfast"
        case 11..<15: return "lunch"
        case 15..<17: return "snack"
        case 17..<22: return "dinner"
        default: return "snack"
        }
    }

    /// Rough calorie estimate based on food name and quantity.
    private func estimateCalories(for name: String, quantity: Int) -> Int? {
        let lower = name.lowercased()
        let baseCalories: Int?

        if lower.contains("burger") { baseCalories = 450 }
        else if lower.contains("pizza") { baseCalories = 300 }
        else if lower.contains("biryani") { baseCalories = 500 }
        else if lower.contains("chicken") && lower.contains("rice") { baseCalories = 550 }
        else if lower.contains("chicken") { baseCalories = 350 }
        else if lower.contains("salad") { baseCalories = 200 }
        else if lower.contains("sandwich") { baseCalories = 350 }
        else if lower.contains("wrap") { baseCalories = 400 }
        else if lower.contains("taco") { baseCalories = 200 }
        else if lower.contains("curry") || lower.contains("dal") { baseCalories = 300 }
        else if lower.contains("roti") || lower.contains("naan") { baseCalories = 120 }
        else if lower.contains("dosa") { baseCalories = 250 }
        else if lower.contains("idli") { baseCalories = 80 }
        else if lower.contains("paneer") { baseCalories = 350 }
        else if lower.contains("rice") { baseCalories = 250 }
        else if lower.contains("noodle") || lower.contains("pasta") { baseCalories = 400 }
        else if lower.contains("fries") || lower.contains("chips") { baseCalories = 320 }
        else if lower.contains("ice cream") { baseCalories = 250 }
        else if lower.contains("cake") { baseCalories = 350 }
        else if lower.contains("coffee") || lower.contains("latte") { baseCalories = 150 }
        else if lower.contains("smoothie") || lower.contains("shake") { baseCalories = 300 }
        else if lower.contains("juice") { baseCalories = 120 }
        else if lower.contains("tea") { baseCalories = 50 }
        else if lower.contains("egg") { baseCalories = 90 }
        else if lower.contains("oat") { baseCalories = 300 }
        else if lower.contains("bread") || lower.contains("toast") { baseCalories = 150 }
        else if lower.contains("fish") || lower.contains("prawn") { baseCalories = 300 }
        else if lower.contains("soup") { baseCalories = 180 }
        else { baseCalories = nil }

        guard let base = baseCalories else { return nil }
        return base * quantity
    }

    // MARK: - Clear

    func clearAll() {
        entries = []
        saveToDisk()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private func saveToDisk() {
        do {
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try decoder.decode([FoodLogEntry].self, from: data)
        } catch {
        }
    }
}
