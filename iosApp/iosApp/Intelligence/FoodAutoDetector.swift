import Foundation
import UserNotifications

/// Automatically detects food-related events from email orders and location visits.
/// Creates food log entries (pending user confirmation for GPS, auto-logged for email orders).
struct FoodAutoDetector {

    // MARK: - Email Order Detection

    /// Called after an email receipt is stored as a transaction.
    /// Checks if the merchant is a food delivery service and creates a food log entry.
    /// `restaurantName` and `restaurantAddress` override the merchant name when available
    /// (e.g., "Ernesto's" instead of "Uber Eats").
    static func checkEmailOrder(
        transaction: StoredTransaction,
        restaurantName: String? = nil,
        restaurantAddress: String? = nil
    ) {
        let merchant = transaction.merchant.lowercased()
        let foodMerchants = ["swiggy", "zomato", "uber eats", "doordash", "grubhub",
                             "deliveroo", "postmates", "dunzo", "blinkit",
                             "dominos", "domino's", "pizza hut", "mcdonald",
                             "kfc", "burger king", "subway", "starbucks"]

        let isFoodMerchant = foodMerchants.contains { merchant.contains($0) }

        // Also check category
        let foodCategories = ["food & dining", "food", "restaurants", "fast food"]
        let isFoodCategory = foodCategories.contains { transaction.category.lowercased().contains($0) }

        // If restaurantName was explicitly passed, the caller already identified this
        // as a food delivery order — trust it (the merchant may be a restaurant name
        // like "Ernesto's" that won't match generic food delivery app lists).
        let isConfirmedFoodOrder = restaurantName != nil

        // Use the real restaurant name if extracted, otherwise fall back to merchant
        let displayName = restaurantName ?? transaction.merchant

        let lineItems = transaction.lineItems ?? []

        if lineItems.isEmpty {
            // No items found in email — common for Uber Eats, Swiggy etc.
            guard isConfirmedFoodOrder || isFoodMerchant || isFoodCategory else { return }
            createPendingFoodLog(
                merchant: displayName,
                address: restaurantAddress,
                totalAmount: transaction.amount,
                transactionId: transaction.id,
                date: transaction.date
            )
            return
        }

        guard isConfirmedFoodOrder || isFoodMerchant || isFoodCategory else {
            // For non-food merchants, check if line items contain food keywords
            let foodItems = FoodStore.filterFoodItems(lineItems: lineItems, merchant: transaction.merchant)
            guard !foodItems.isEmpty else { return }
            createFoodLogFromEmail(
                merchant: displayName,
                address: restaurantAddress,
                lineItems: foodItems,
                totalAmount: foodItems.reduce(0) { $0 + $1.amount * Double($1.quantity) },
                transactionId: transaction.id,
                date: transaction.date
            )
            return
        }

        // Full food order with items — log all items
        createFoodLogFromEmail(
            merchant: displayName,
            address: restaurantAddress,
            lineItems: lineItems,
            totalAmount: transaction.amount,
            transactionId: transaction.id,
            date: transaction.date
        )
    }

    // MARK: - Pending Food Log (no items detected)

    private static func createPendingFoodLog(
        merchant: String,
        address: String?,
        totalAmount: Double,
        transactionId: String,
        date: Date
    ) {
        Task {
            let existing = await FoodStore.shared.entryForTransaction(id: transactionId)
            guard existing == nil else { return }

            let mealType = await FoodStore.shared.inferMealType(from: date)

            let entry = FoodStore.FoodLogEntry(
                mealType: mealType,
                items: [],
                source: .emailOrder,
                locationName: merchant,
                locationAddress: address,
                totalCaloriesEstimate: nil,
                totalMacros: nil,
                totalSpent: totalAmount,
                transactionId: transactionId
            )
            await FoodStore.shared.addEntry(entry)

            sendFoodNotification(
                title: "Looks like you ordered from \(merchant)",
                body: "$\(String(format: "%.2f", totalAmount)) order detected — would you like to log the meal?",
                identifier: "food_pending_\(transactionId)"
            )
        }
    }

    // MARK: - Full Food Log (items detected)

    private static func createFoodLogFromEmail(
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

            let entry = await FoodStore.shared.createFromEmailOrder(
                merchant: merchant,
                address: address,
                lineItems: lineItems,
                totalAmount: totalAmount,
                transactionId: transactionId
            )
            await FoodStore.shared.addEntry(entry)

            if !bulkItems.isEmpty {
                let itemNames = bulkItems.map { "\($0.quantity)x \($0.name)" }.joined(separator: ", ")
                sendFoodNotification(
                    title: "Bulk order from \(merchant)",
                    body: "Ordered \(itemNames). How many did you eat? Tap to update portions.",
                    identifier: "food_bulk_\(transactionId)"
                )
            }
        }
    }

    // MARK: - Location Visit Detection

    static func checkLocationVisit(placeName: String, category: String?, arrivalDate: Date) {
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
                            "mexican", "italian"].contains { lower.contains($0) }
        }

        guard isRestaurant else { return }

        Task {
            let recentEntries = await FoodStore.shared.entries(since: arrivalDate.addingTimeInterval(-7200))

            // Skip if there's already a recent email order (delivery detected)
            let hasRecentEmailLog = recentEntries.contains { $0.source == .emailOrder }
            guard !hasRecentEmailLog else { return }

            // Skip if there's already a recent location-based entry for the same place
            let hasRecentLocationLog = recentEntries.contains { entry in
                entry.source == .locationPrompt &&
                entry.locationName?.lowercased() == placeName.lowercased()
            }
            guard !hasRecentLocationLog else { return }

            let entry = await FoodStore.shared.createFromLocationVisit(
                restaurantName: placeName,
                arrivalDate: arrivalDate
            )
            await FoodStore.shared.addEntry(entry)

            sendFoodNotification(
                title: "Ate at \(placeName)?",
                body: "Looks like you visited \(placeName). Tap to log what you ate.",
                identifier: "food_location_\(entry.id)"
            )
        }
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

        UNUserNotificationCenter.current().add(request)
    }
}
