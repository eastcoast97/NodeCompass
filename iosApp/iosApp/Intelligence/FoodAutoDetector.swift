import Foundation
import UserNotifications

/// Smart food detection engine that fuses bank transactions, location data,
/// and user eating habits to auto-log meals with minimal user input.
///
/// Intelligence tiers (highest to lowest confidence):
/// 1. Transaction with line items → auto-log with calories, confirm via notification
/// 2. Transaction + location match → high confidence, suggest past orders or common items
/// 3. Transaction only (food merchant) → suggest based on spending habits
/// 4. Location only (restaurant) → suggest based on past visits
/// 5. Unknown merchant/place → generic "Log a meal?" prompt
struct FoodAutoDetector {

    // MARK: - Email Order Detection (Transaction Path)

    /// Called after an email receipt is stored as a transaction.
    /// Smart routing based on available data:
    /// - Has line items → auto-log with calorie estimates
    /// - No items + user history → suggest past orders
    /// - No items + no history → prompt to log
    /// - Group order detected → adjust portions
    static func checkEmailOrder(
        transaction: StoredTransaction,
        restaurantName: String? = nil,
        restaurantAddress: String? = nil
    ) {
        let merchant = transaction.merchant.lowercased()
        let foodMerchants = ["swiggy", "zomato", "uber eats", "doordash", "grubhub",
                             "deliveroo", "postmates", "dunzo", "blinkit",
                             "dominos", "domino's", "pizza hut", "mcdonald",
                             "kfc", "burger king", "subway", "starbucks",
                             "chipotle", "wendy", "taco bell", "panda express",
                             "chick-fil-a", "popeyes", "five guys", "shake shack",
                             "haldiram", "saravana", "a2b", "chai point",
                             "third wave", "blue tokai", "cafe coffee day", "ccd"]

        let isFoodMerchant = foodMerchants.contains { merchant.contains($0) }

        let foodCategories = ["food & dining", "food", "restaurants", "fast food",
                              "coffee shops", "cafes"]
        let isFoodCategory = foodCategories.contains { transaction.category.lowercased().contains($0) }

        let isConfirmedFoodOrder = restaurantName != nil
        let displayName = restaurantName ?? transaction.merchant

        let lineItems = transaction.lineItems ?? []

        guard isConfirmedFoodOrder || isFoodMerchant || isFoodCategory else {
            // Non-food merchant — check if line items contain food keywords
            if !lineItems.isEmpty {
                let foodItems = FoodStore.filterFoodItems(lineItems: lineItems, merchant: transaction.merchant)
                guard !foodItems.isEmpty else { return }
                handleWithLineItems(
                    merchant: displayName,
                    address: restaurantAddress,
                    lineItems: foodItems,
                    totalAmount: foodItems.reduce(0) { $0 + $1.amount * Double($1.quantity) },
                    transactionId: transaction.id,
                    date: transaction.date
                )
            }
            return
        }

        if !lineItems.isEmpty {
            // TIER 1: We have actual items — auto-log with calories
            handleWithLineItems(
                merchant: displayName,
                address: restaurantAddress,
                lineItems: lineItems,
                totalAmount: transaction.amount,
                transactionId: transaction.id,
                date: transaction.date
            )
        } else {
            // TIER 3: Food merchant but no line items — use intelligence
            handleWithoutLineItems(
                merchant: displayName,
                address: restaurantAddress,
                amount: transaction.amount,
                transactionId: transaction.id,
                date: transaction.date
            )
        }
    }

    // MARK: - TIER 1: Has Line Items → Auto-Log

    /// Items are known — create food log with calorie estimates automatically.
    /// User gets a rich notification showing what was logged.
    private static func handleWithLineItems(
        merchant: String,
        address: String?,
        lineItems: [LineItem],
        totalAmount: Double,
        transactionId: String,
        date: Date
    ) {
        let bulkItems = FoodStore.detectBulkItems(lineItems: lineItems)

        Task {
            let existing = await FoodStore.shared.entryForTransaction(id: transactionId)
            guard existing == nil else { return }

            // Check for group order: if total is 2x+ the user's average at this merchant
            let avgSpend = await FoodStore.shared.averageSpendAt(merchant)
            let isLikelyGroupOrder = avgSpend != nil && totalAmount > avgSpend! * 2.0
            let visitCount = await FoodStore.shared.visitCountAt(merchant)

            let entry = await FoodStore.shared.createFromEmailOrder(
                merchant: merchant,
                address: address,
                lineItems: lineItems,
                totalAmount: totalAmount,
                transactionId: transactionId
            )
            await FoodStore.shared.addEntry(entry)

            // Build smart notification
            let itemNames = lineItems.prefix(3).map { $0.name }.joined(separator: ", ")
            let calories = entry.totalCaloriesEstimate

            if isLikelyGroupOrder {
                // Group order — ask about portions
                let avgStr = avgSpend != nil ? String(format: "%.0f", avgSpend!) : "?"
                sendFoodNotification(
                    title: "Group order at \(merchant)?",
                    body: "₹\(String(format: "%.0f", totalAmount)) is \(String(format: "%.0f", totalAmount / (avgSpend ?? totalAmount)))x your usual ₹\(avgStr). Items: \(itemNames). Tap to adjust what you ate.",
                    identifier: "food_group_\(transactionId)"
                )
            } else if !bulkItems.isEmpty {
                let bulkNames = bulkItems.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
                sendFoodNotification(
                    title: "Bulk order from \(merchant)",
                    body: "Ordered \(bulkNames). How many did you eat? Tap to update portions.",
                    identifier: "food_bulk_\(transactionId)"
                )
            } else {
                // Normal order — auto-logged with details
                var body = "Auto-logged: \(itemNames)"
                if let cal = calories, cal > 0 {
                    body += " (~\(cal) cal)"
                }
                body += ". Tap to edit."

                sendFoodNotification(
                    title: "🍽️ Meal logged from \(merchant)",
                    body: body,
                    identifier: "food_auto_\(transactionId)"
                )
            }
        }
    }

    // MARK: - TIER 3: No Line Items → Smart Suggestion

    /// No receipt items available — use past habits and spending to suggest.
    private static func handleWithoutLineItems(
        merchant: String,
        address: String?,
        amount: Double,
        transactionId: String,
        date: Date
    ) {
        Task {
            let existing = await FoodStore.shared.entryForTransaction(id: transactionId)
            guard existing == nil else { return }

            let pastItems = await FoodStore.shared.topItemsWithNutrition(at: merchant, limit: 3)
            let avgSpend = await FoodStore.shared.averageSpendAt(merchant)
            let visitCount = await FoodStore.shared.visitCountAt(merchant)
            let mealType = await FoodStore.shared.inferMealType(from: date)

            // Check for group order
            let isLikelyGroupOrder = avgSpend != nil && amount > avgSpend! * 2.0

            if isLikelyGroupOrder {
                // Group order — create pending, ask user
                let entry = FoodStore.FoodLogEntry(
                    mealType: mealType,
                    items: [],
                    source: .emailOrder,
                    locationName: merchant,
                    locationAddress: address,
                    totalSpent: amount,
                    transactionId: transactionId
                )
                await FoodStore.shared.addEntry(entry)

                let avgStr = avgSpend != nil ? String(format: "%.0f", avgSpend!) : "?"
                sendFoodNotification(
                    title: "Group order at \(merchant)?",
                    body: "₹\(String(format: "%.0f", amount)) is more than your usual ₹\(avgStr). What did you eat? Tap to log your portion.",
                    identifier: "food_group_\(transactionId)"
                )
            } else if !pastItems.isEmpty && visitCount >= 2 {
                // Has history — suggest what they usually order
                let topItem = pastItems[0]
                let calStr = topItem.calories != nil ? " (~\(topItem.calories!) cal)" : ""
                let suggestion = pastItems.map { $0.name }.joined(separator: ", ")

                // Auto-log the most likely order based on habits
                let suggestedFoodItems = pastItems.map { item in
                    FoodItem(
                        name: item.name,
                        amount: 1,
                        unit: .qty,
                        caloriesEstimate: item.calories ?? NutritionDatabase.lookup(item.name)?.caloriesPerServing,
                        isHomemade: false
                    )
                }
                let totalCal = suggestedFoodItems.compactMap { $0.caloriesEstimate }.reduce(0, +)

                let entry = FoodStore.FoodLogEntry(
                    mealType: mealType,
                    items: suggestedFoodItems,
                    source: .autoDetected,
                    locationName: merchant,
                    locationAddress: address,
                    totalCaloriesEstimate: totalCal > 0 ? totalCal : nil,
                    totalSpent: amount,
                    transactionId: transactionId
                )
                await FoodStore.shared.addEntry(entry)

                sendFoodNotification(
                    title: "Had \(topItem.name) at \(merchant)?",
                    body: "Based on your past visits, we logged \(suggestion)\(calStr). Tap to edit if different.",
                    identifier: "food_habit_\(transactionId)"
                )
            } else {
                // No history — generic prompt
                let entry = FoodStore.FoodLogEntry(
                    mealType: mealType,
                    items: [],
                    source: .emailOrder,
                    locationName: merchant,
                    locationAddress: address,
                    totalSpent: amount,
                    transactionId: transactionId
                )
                await FoodStore.shared.addEntry(entry)

                sendFoodNotification(
                    title: "Ate at \(merchant)?",
                    body: "₹\(String(format: "%.0f", amount)) charge detected. Tap to log what you had.",
                    identifier: "food_pending_\(transactionId)"
                )
            }
        }
    }

    // MARK: - TIER 2: Location + Transaction Fusion

    /// Called when we have BOTH a location visit AND a matching transaction.
    /// Highest-confidence auto-log path — both signals confirm the visit.
    static func handleLocationTransactionFusion(
        placeName: String,
        category: String?,
        transaction: StoredTransaction,
        arrivalDate: Date
    ) {
        let lineItems = transaction.lineItems ?? []
        let displayName = placeName

        Task {
            let existing = await FoodStore.shared.entryForTransaction(id: transaction.id)
            guard existing == nil else { return }

            if !lineItems.isEmpty {
                // Best case: location + transaction + items
                handleWithLineItems(
                    merchant: displayName,
                    address: nil,
                    lineItems: lineItems,
                    totalAmount: transaction.amount,
                    transactionId: transaction.id,
                    date: arrivalDate
                )
            } else {
                // Location + transaction but no items — suggest from habits
                let pastItems = await FoodStore.shared.topItemsWithNutrition(at: displayName, limit: 3)
                let mealType = await FoodStore.shared.inferMealType(from: arrivalDate)
                let avgSpend = await FoodStore.shared.averageSpendAt(displayName)
                let isLikelyGroupOrder = avgSpend != nil && transaction.amount > avgSpend! * 2.0

                if !pastItems.isEmpty {
                    // Smart suggestion: "You usually have Coffee at Starbucks"
                    let suggestedItems = pastItems.map { item in
                        FoodItem(
                            name: item.name,
                            amount: 1,
                            unit: .qty,
                            caloriesEstimate: item.calories ?? NutritionDatabase.lookup(item.name)?.caloriesPerServing,
                            isHomemade: false
                        )
                    }
                    let totalCal = suggestedItems.compactMap { $0.caloriesEstimate }.reduce(0, +)

                    let entry = FoodStore.FoodLogEntry(
                        mealType: mealType,
                        items: isLikelyGroupOrder ? [] : suggestedItems,
                        source: .autoDetected,
                        locationName: displayName,
                        totalCaloriesEstimate: isLikelyGroupOrder ? nil : (totalCal > 0 ? totalCal : nil),
                        totalSpent: transaction.amount,
                        transactionId: transaction.id
                    )
                    await FoodStore.shared.addEntry(entry)

                    let topItem = pastItems[0]
                    let calStr = topItem.calories != nil ? " (~\(topItem.calories!) cal)" : ""

                    if isLikelyGroupOrder {
                        sendFoodNotification(
                            title: "Group \(mealType) at \(displayName)?",
                            body: "₹\(String(format: "%.0f", transaction.amount)) is higher than usual. What did you have? Tap to log your portion.",
                            identifier: "food_fusion_group_\(transaction.id)"
                        )
                    } else {
                        sendFoodNotification(
                            title: "Had \(topItem.name) at \(displayName)?\(calStr)",
                            body: "We see you're here and a ₹\(String(format: "%.0f", transaction.amount)) charge came through. Logged your usual — tap to edit.",
                            identifier: "food_fusion_\(transaction.id)"
                        )
                    }
                } else {
                    // First visit but we have transaction confirmation
                    let entry = FoodStore.FoodLogEntry(
                        mealType: mealType,
                        items: [],
                        source: .autoDetected,
                        locationName: displayName,
                        totalSpent: transaction.amount,
                        transactionId: transaction.id
                    )
                    await FoodStore.shared.addEntry(entry)

                    sendFoodNotification(
                        title: "🍽️ \(mealType.capitalized) at \(displayName)?",
                        body: "₹\(String(format: "%.0f", transaction.amount)) charge + your location confirms a visit. Tap to log what you had.",
                        identifier: "food_fusion_new_\(transaction.id)"
                    )
                }
            }
        }
    }

    // MARK: - TIER 4: Location Visit Only (No Transaction Yet)

    /// GPS detected a restaurant visit — check for matching transaction,
    /// suggest based on habits, Google Place data, or send generic prompt.
    static func checkLocationVisit(placeName: String, category: String?, arrivalDate: Date,
                                   placeDetails: PlaceResolver.PlaceDetails? = nil) {
        let restaurantCategories = ["restaurant", "food", "cafe", "coffee", "bakery",
                                     "fast food", "bar", "pub", "diner", "pizzeria"]

        let isRestaurant: Bool
        if let cat = category?.lowercased() {
            isRestaurant = restaurantCategories.contains { cat.contains($0) }
        } else {
            let lower = placeName.lowercased()
            isRestaurant = restaurantCategories.contains { lower.contains($0) } ||
                           ["kitchen", "grill", "bistro", "eatery", "dhaba", "biryani",
                            "pizza", "burger", "sushi", "thai", "chinese", "indian",
                            "mexican", "italian", "starbucks", "cafe", "coffee",
                            "tea", "bakery", "juice", "smoothie"].contains { lower.contains($0) }
        }

        guard isRestaurant else { return }

        Task {
            let recentEntries = await FoodStore.shared.entries(since: arrivalDate.addingTimeInterval(-7200))

            // Skip if there's already a recent email order
            let hasRecentEmailLog = recentEntries.contains { $0.source == .emailOrder || $0.source == .autoDetected }
            guard !hasRecentEmailLog else { return }

            // Skip if there's already a location-based entry for the same place
            let hasRecentLocationLog = recentEntries.contains { entry in
                (entry.source == .locationPrompt || entry.source == .autoDetected) &&
                entry.locationName?.lowercased() == placeName.lowercased()
            }
            guard !hasRecentLocationLog else { return }

            // Check for a matching recent transaction
            let recentTransaction = await findMatchingTransaction(
                placeName: placeName,
                since: arrivalDate.addingTimeInterval(-7200)
            )

            if let txn = recentTransaction {
                // TIER 2: Location + Transaction — highest confidence
                handleLocationTransactionFusion(
                    placeName: placeName,
                    category: category,
                    transaction: txn,
                    arrivalDate: arrivalDate
                )
                return
            }

            // TIER 4: Location only, NO transaction — SUGGEST only, never auto-log.
            // Nothing gets written to FoodStore until a transaction confirms the purchase.
            let pastItems = await FoodStore.shared.topItemsWithNutrition(at: placeName, limit: 3)
            let mealType = await FoodStore.shared.inferMealType(from: arrivalDate)

            if !pastItems.isEmpty {
                // Has history — suggest what they usually get
                let topItem = pastItems[0]
                let calStr = topItem.calories != nil ? " (~\(topItem.calories!) cal)" : ""
                let suggestion = pastItems.prefix(2).map { $0.name }.joined(separator: ", ")

                sendFoodNotification(
                    title: "Having \(topItem.name) at \(placeName)?",
                    body: "You usually get \(suggestion)\(calStr). Tap to log if you're eating.",
                    identifier: "food_suggest_habit_\(UUID().uuidString.prefix(8))"
                )
            } else if let details = placeDetails, !details.popularItems.isEmpty {
                // First visit — Google reviews tell us what's popular
                let topItems = Array(details.popularItems.prefix(3))
                let suggestion = topItems.joined(separator: ", ")
                let topCal = NutritionDatabase.lookup(topItems[0])?.caloriesPerServing
                let calStr = topCal != nil ? " (~\(topCal!) cal)" : ""

                sendFoodNotification(
                    title: "At \(placeName) — having \(topItems[0])?",
                    body: "Popular here: \(suggestion)\(calStr). Tap to log your meal.",
                    identifier: "food_suggest_google_\(UUID().uuidString.prefix(8))"
                )
            } else if let details = placeDetails, let summary = details.editorialSummary {
                // No popular items from reviews, but we have editorial summary
                let guess = guessFromEditorialSummary(summary, placeName: placeName, mealType: mealType)

                if let guess = guess {
                    let calStr = guess.calories != nil ? " ~\(guess.calories!) cal" : ""
                    sendFoodNotification(
                        title: "\(guess.emoji) \(guess.item) at \(placeName)?",
                        body: "\(String(summary.prefix(60))). Tap to log if you're eating.",
                        identifier: "food_suggest_editorial_\(UUID().uuidString.prefix(8))"
                    )
                } else {
                    sendFoodNotification(
                        title: "Eating at \(placeName)?",
                        body: "\(String(summary.prefix(80))). Tap to log what you had.",
                        identifier: "food_suggest_summary_\(UUID().uuidString.prefix(8))"
                    )
                }
            } else {
                // No Google data, no history — guess from place name
                let guess = guessLikelyItem(placeName: placeName, mealType: mealType)

                if let guess = guess {
                    let calStr = guess.calories != nil ? " ~\(guess.calories!) cal" : ""
                    sendFoodNotification(
                        title: "\(guess.emoji) \(guess.item) at \(placeName)?",
                        body: "Looks like you're at \(placeName). Tap to log if you're eating.",
                        identifier: "food_suggest_guess_\(UUID().uuidString.prefix(8))"
                    )
                } else {
                    sendFoodNotification(
                        title: "At \(placeName)?",
                        body: "Tap to log a meal if you're eating here.",
                        identifier: "food_suggest_\(UUID().uuidString.prefix(8))"
                    )
                }
            }
        }
    }

    // MARK: - Transaction Matching

    /// Search recent transactions for one that matches a place name.
    private static func findMatchingTransaction(
        placeName: String,
        since: Date
    ) async -> StoredTransaction? {
        let transactions = await MainActor.run {
            TransactionStore.shared.transactions.filter {
                $0.date >= since && $0.type != "credit"
            }
        }

        let place = placeName.lowercased()
        return transactions.first { txn in
            let merchant = txn.merchant.lowercased()
            return merchant.contains(place) || place.contains(merchant) ||
                   levenshteinSimilarity(merchant, place) > 0.5
        }
    }

    // MARK: - Smart Guessing

    /// Guess what someone likely had based on the restaurant name/type and time of day.
    private static func guessLikelyItem(
        placeName: String, mealType: String
    ) -> (item: String, emoji: String, calories: Int?)? {
        let lower = placeName.lowercased()

        // Coffee shops
        if lower.contains("starbucks") || lower.contains("coffee") ||
           lower.contains("cafe") || lower.contains("blue tokai") ||
           lower.contains("third wave") || lower.contains("ccd") {
            return ("Coffee", "☕", 150)
        }

        // Tea places
        if lower.contains("chai") || lower.contains("tea") {
            return ("Tea", "🍵", 80)
        }

        // Pizza
        if lower.contains("domino") || lower.contains("pizza") {
            return ("Pizza", "🍕", 300)
        }

        // Burger joints
        if lower.contains("burger") || lower.contains("mcdonald") ||
           lower.contains("five guys") || lower.contains("shake shack") ||
           lower.contains("wendy") {
            return ("Burger & Fries", "🍔", 750)
        }

        // Fried chicken
        if lower.contains("kfc") || lower.contains("popeyes") ||
           lower.contains("chick-fil-a") {
            return ("Fried Chicken", "🍗", 450)
        }

        // Indian
        if lower.contains("biryani") || lower.contains("dhaba") {
            return mealType == "lunch" || mealType == "dinner"
                ? ("Biryani", "🍛", 500)
                : ("Snack", "🍛", 200)
        }

        // South Indian
        if lower.contains("dosa") || lower.contains("idli") ||
           lower.contains("saravana") || lower.contains("a2b") {
            return mealType == "breakfast"
                ? ("Dosa & Coffee", "🥞", 350)
                : ("South Indian Meal", "🍛", 450)
        }

        // Juice / Smoothie
        if lower.contains("juice") || lower.contains("smoothie") {
            return ("Fresh Juice", "🧃", 120)
        }

        // Bakery
        if lower.contains("bakery") || lower.contains("bread") {
            return ("Pastry", "🧁", 250)
        }

        // Ice cream
        if lower.contains("ice cream") || lower.contains("gelato") ||
           lower.contains("baskin") || lower.contains("naturals") {
            return ("Ice Cream", "🍦", 250)
        }

        // Subway
        if lower.contains("subway") {
            return ("Sub Sandwich", "🥪", 400)
        }

        // Generic restaurant by meal type
        switch mealType {
        case "breakfast": return ("Breakfast", "🍳", nil)
        case "lunch": return ("Lunch", "🍽️", nil)
        case "dinner": return ("Dinner", "🍽️", nil)
        default: return nil
        }
    }

    // MARK: - Editorial Summary Parsing

    /// Extract a food guess from Google's editorial summary.
    /// e.g. "Popular spot for biryani and kebabs" → Biryani
    private static func guessFromEditorialSummary(
        _ summary: String, placeName: String, mealType: String
    ) -> (item: String, emoji: String, calories: Int?)? {
        let lower = summary.lowercased()

        let foodMap: [(keyword: String, item: String, emoji: String, cal: Int)] = [
            ("biryani", "Biryani", "🍛", 500),
            ("butter chicken", "Butter Chicken", "🍛", 450),
            ("tandoori", "Tandoori", "🍗", 350),
            ("dosa", "Dosa", "🥞", 250),
            ("thali", "Thali", "🍛", 550),
            ("kebab", "Kebab", "🍢", 300),
            ("pizza", "Pizza", "🍕", 300),
            ("burger", "Burger", "🍔", 450),
            ("sushi", "Sushi", "🍣", 350),
            ("ramen", "Ramen", "🍜", 450),
            ("noodle", "Noodles", "🍜", 400),
            ("pasta", "Pasta", "🍝", 400),
            ("steak", "Steak", "🥩", 500),
            ("seafood", "Seafood", "🦐", 350),
            ("coffee", "Coffee", "☕", 150),
            ("tea", "Tea", "🍵", 80),
            ("bakery", "Pastry", "🧁", 250),
            ("ice cream", "Ice Cream", "🍦", 250),
            ("sandwich", "Sandwich", "🥪", 350),
            ("salad", "Salad", "🥗", 200),
            ("dim sum", "Dim Sum", "🥟", 400),
            ("taco", "Taco", "🌮", 200),
            ("breakfast", "Breakfast", "🍳", 400),
            ("brunch", "Brunch", "🍳", 500),
        ]

        for item in foodMap {
            if lower.contains(item.keyword) {
                return (item.item, item.emoji, item.cal)
            }
        }

        // Fall back to generic guess from place name
        return guessLikelyItem(placeName: placeName, mealType: mealType)
    }

    // MARK: - Notification Helper

    private static func sendFoodNotification(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "FOOD_LOG"

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    // MARK: - String Similarity

    private static func levenshteinSimilarity(_ s1: String, _ s2: String) -> Double {
        let a = Array(s1), b = Array(s2)
        let m = a.count, n = b.count
        guard m > 0 && n > 0 else { return 0 }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 0...m { dp[i][0] = i }
        for j in 0...n { dp[0][j] = j }

        for i in 1...m {
            for j in 1...n {
                dp[i][j] = a[i-1] == b[j-1]
                    ? dp[i-1][j-1]
                    : 1 + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            }
        }

        let maxLen = Double(max(m, n))
        return 1.0 - Double(dp[m][n]) / maxLen
    }
}
