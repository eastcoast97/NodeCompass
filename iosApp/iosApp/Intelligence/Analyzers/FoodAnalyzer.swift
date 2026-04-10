import Foundation

/// Analyzes food log events to produce nutrition and eating pattern insights.
/// Cross-references with spending, health, and location data.
struct FoodAnalyzer {

    static func analyze(events: [LifeEvent], profile: UserProfile) -> [Insight] {
        var insights: [Insight] = []

        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: Date())!

        let foodEvents = events.compactMap { event -> (date: Date, food: FoodLogEvent)? in
            guard event.timestamp >= twoWeeksAgo else { return nil }
            if case .foodLog(let f) = event.payload { return (event.timestamp, f) }
            return nil
        }

        guard foodEvents.count >= 3 else { return [] }

        // 1. Meals per day
        insights.append(contentsOf: mealsPerDayInsight(foodEvents: foodEvents))

        // 2. Home cooking vs eating out/delivery
        insights.append(contentsOf: cookingVsOutInsight(foodEvents: foodEvents))

        // 3. Frequent food items (staple detection)
        insights.append(contentsOf: stapleInsights(foodEvents: foodEvents))

        // 4. Home cooking streak
        if let streak = homeCookingStreak(foodEvents: foodEvents) {
            insights.append(streak)
        }

        // 5. Food delivery spending correlation
        insights.append(contentsOf: deliverySpendingInsight(events: events, foodEvents: foodEvents))

        // 6. Meal timing regularity
        if let timing = mealTimingInsight(foodEvents: foodEvents) {
            insights.append(timing)
        }

        // 7. Post-workout eating
        insights.append(contentsOf: postWorkoutEating(events: events, foodEvents: foodEvents))

        // 8. Calorie trends
        if let calInsight = calorieInsight(foodEvents: foodEvents) {
            insights.append(calInsight)
        }

        // 9. Variety score
        if let variety = varietyInsight(foodEvents: foodEvents) {
            insights.append(variety)
        }

        // 10. Macro imbalance (fat/carb/protein)
        insights.append(contentsOf: macroImbalanceInsights(foodEvents: foodEvents))

        // 11. Over-ordering frequency
        insights.append(contentsOf: overOrderingInsight(foodEvents: foodEvents))

        // 12. Weekly ordering trend (this week vs last)
        insights.append(contentsOf: weeklyOrderTrend(events: events, foodEvents: foodEvents))

        // 13. Biggest order of the week
        if let bigOrder = biggestOrderInsight(foodEvents: foodEvents) {
            insights.append(bigOrder)
        }

        // 14. Protein deficiency
        if let protein = proteinInsight(foodEvents: foodEvents) {
            insights.append(protein)
        }

        // 15. Fiber check
        if let fiber = fiberInsight(foodEvents: foodEvents) {
            insights.append(fiber)
        }

        return insights
    }

    // MARK: - Meals Per Day

    private static func mealsPerDayInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: foodEvents) { cal.startOfDay(for: $0.date) }
        let avgMeals = Double(foodEvents.count) / max(Double(byDay.count), 1)

        guard byDay.count >= 3 else { return [] }

        return [Insight(
            type: .foodPattern,
            title: String(format: "%.1f meals/day", avgMeals),
            body: avgMeals < 2.5
                ? "You're averaging under 3 meals a day. Make sure you're eating enough."
                : avgMeals > 4
                ? "You're eating \(String(format: "%.0f", avgMeals)) times a day — mostly snacking?"
                : "You're logging a healthy \(String(format: "%.0f", avgMeals)) meals per day.",
            priority: .low,
            category: "food"
        )]
    }

    // MARK: - Cooking vs Eating Out

    private static func cookingVsOutInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        let homemade = foodEvents.filter { $0.food.source == .manual || $0.food.source == .stapleSuggestion }
        let outside = foodEvents.filter { $0.food.source == .emailOrder || $0.food.source == .locationPrompt }

        guard foodEvents.count >= 5 else { return [] }

        let homePercent = Double(homemade.count) / Double(foodEvents.count) * 100
        let outPercent = Double(outside.count) / Double(foodEvents.count) * 100

        var insights: [Insight] = []

        if outPercent > 60 {
            insights.append(Insight(
                type: .foodPattern,
                title: "\(Int(outPercent))% meals are outside food",
                body: "Only \(Int(homePercent))% of your meals are homemade. Cooking at home could save money and be healthier.",
                priority: .medium,
                category: "food"
            ))
        } else if homePercent > 70 {
            insights.append(Insight(
                type: .mealStreak,
                title: "\(Int(homePercent))% home-cooked meals!",
                body: "Great job cooking at home. That's \(homemade.count) out of \(foodEvents.count) meals.",
                priority: .low,
                category: "food"
            ))
        }

        return insights
    }

    // MARK: - Staple Food Detection

    private static func stapleInsights(foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        var itemCounts: [String: Int] = [:]
        for event in foodEvents {
            for item in event.food.items {
                let key = item.name.lowercased()
                itemCounts[key, default: 0] += item.quantity
            }
        }

        let staples = itemCounts.filter { $0.value >= 4 }.sorted { $0.value > $1.value }

        guard let top = staples.first else { return [] }

        return [Insight(
            type: .foodPattern,
            title: "Your staple: \(top.key.capitalized)",
            body: "You've had \(top.key.capitalized) \(top.value) times in 2 weeks.\(staples.count > 1 ? " Also frequent: \(staples.dropFirst().prefix(2).map { $0.key.capitalized }.joined(separator: ", "))." : "")",
            priority: .low,
            category: "food"
        )]
    }

    // MARK: - Home Cooking Streak

    private static func homeCookingStreak(foodEvents: [(date: Date, food: FoodLogEvent)]) -> Insight? {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: foodEvents) { cal.startOfDay(for: $0.date) }
            .mapValues { events -> Bool in
                let homeCount = events.filter { $0.food.source == .manual || $0.food.source == .stapleSuggestion }.count
                return homeCount > events.count / 2
            }

        let sortedDays = byDay.sorted { $0.key > $1.key }
        var streak = 0
        for (_, isHomemade) in sortedDays {
            if isHomemade { streak += 1 } else { break }
        }

        guard streak >= 3 else { return nil }

        return Insight(
            type: .mealStreak,
            title: "\(streak)-day home cooking streak!",
            body: "You've been cooking at home for \(streak) days straight. Your wallet and body thank you.",
            priority: streak >= 5 ? .medium : .low,
            category: "food"
        )
    }

    // MARK: - Delivery Spending

    private static func deliverySpendingInsight(events: [LifeEvent], foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: Date())!

        let deliverySpend = foodEvents
            .filter { $0.food.source == .emailOrder }
            .compactMap { $0.food.totalSpent }
            .reduce(0, +)

        let totalSpend = events.compactMap { event -> Double? in
            guard event.timestamp >= twoWeeksAgo else { return nil }
            if case .transaction(let t) = event.payload, !t.isCredit { return t.amount }
            return nil
        }.reduce(0, +)

        guard totalSpend > 0 && deliverySpend > 0 else { return [] }

        let percent = (deliverySpend / totalSpend) * 100

        guard percent >= 15 else { return [] }

        return [Insight(
            type: .foodSpending,
            title: "Food delivery is \(Int(percent))% of spending",
            body: "You've spent $\(Int(deliverySpend)) on food delivery in 2 weeks out of $\(Int(totalSpend)) total.",
            priority: percent >= 30 ? .medium : .low,
            category: "food"
        )]
    }

    // MARK: - Meal Timing

    private static func mealTimingInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> Insight? {
        let cal = Calendar.current

        let dinnerEvents = foodEvents.filter { $0.food.mealType == "dinner" }
        guard dinnerEvents.count >= 4 else { return nil }

        let dinnerHours = dinnerEvents.map { cal.component(.hour, from: $0.date) }
        let avgHour = dinnerHours.reduce(0, +) / dinnerHours.count
        let variance = dinnerHours.map { abs($0 - avgHour) }.reduce(0, +) / dinnerHours.count

        let timeStr = avgHour > 12 ? "\(avgHour - 12) PM" : "\(avgHour) AM"

        if avgHour >= 21 {
            return Insight(
                type: .foodPattern,
                title: "Late dinners — avg \(timeStr)",
                body: "Eating late can affect sleep quality and digestion. Try to eat before 9 PM.",
                priority: .medium,
                category: "food"
            )
        } else if variance > 2 {
            return Insight(
                type: .foodPattern,
                title: "Irregular dinner times",
                body: "Your dinner time varies by \(variance)+ hours. Consistent meal timing helps metabolism.",
                priority: .low,
                category: "food"
            )
        }

        return nil
    }

    // MARK: - Post-Workout Eating

    private static func postWorkoutEating(events: [LifeEvent], foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let workouts = events.compactMap { event -> Date? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .workout = event.payload { return event.timestamp }
            return nil
        }

        guard workouts.count >= 2 else { return [] }

        var fedAfter = 0
        var unfedAfter = 0
        for workoutDate in workouts {
            let window = workoutDate.addingTimeInterval(7200)
            let ateAfter = foodEvents.contains { $0.date > workoutDate && $0.date <= window }
            if ateAfter { fedAfter += 1 } else { unfedAfter += 1 }
        }

        if unfedAfter > fedAfter && unfedAfter >= 2 {
            return [Insight(
                type: .nutritionAlert,
                title: "Skipping post-workout meals",
                body: "You didn't eat within 2 hours of \(unfedAfter) out of \(workouts.count) workouts. Post-workout nutrition aids recovery.",
                priority: .medium,
                category: "food"
            )]
        }

        return []
    }

    // MARK: - Calorie Tracking

    private static func calorieInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> Insight? {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: foodEvents) { cal.startOfDay(for: $0.date) }

        let dailyCals = byDay.compactMap { (_, events) -> Int? in
            let total = events.compactMap { $0.food.totalCaloriesEstimate }.reduce(0, +)
            return total > 0 ? total : nil
        }

        guard dailyCals.count >= 3 else { return nil }

        let avg = dailyCals.reduce(0, +) / dailyCals.count

        if avg < 1200 {
            return Insight(
                type: .nutritionAlert,
                title: "Low calorie intake: ~\(avg) cal/day",
                body: "Your tracked calorie intake is low. Make sure you're logging all meals — or you may not be eating enough.",
                priority: .medium,
                category: "food"
            )
        } else if avg > 2500 {
            return Insight(
                type: .nutritionAlert,
                title: "High intake: ~\(avg) cal/day",
                body: "You're averaging \(avg) calories per day — that's on the higher side. Watch your portion sizes.",
                priority: .medium,
                category: "food"
            )
        }

        return nil
    }

    // MARK: - Variety Score

    private static func varietyInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> Insight? {
        let allItems = foodEvents.flatMap { $0.food.items.map { $0.name.lowercased() } }
        let uniqueItems = Set(allItems)

        guard allItems.count >= 10 else { return nil }

        let varietyScore = Double(uniqueItems.count) / Double(allItems.count)

        if varietyScore < 0.3 {
            return Insight(
                type: .nutritionAlert,
                title: "Low food variety",
                body: "You're eating only \(uniqueItems.count) different items across \(allItems.count) food entries. Try mixing in new foods for better nutrition.",
                priority: .low,
                category: "food"
            )
        }

        return nil
    }

    // MARK: - Macro Imbalance

    private static func macroImbalanceInsights(foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        var insights: [Insight] = []

        // Aggregate macros across all events
        var totalProtein: Double = 0
        var totalCarbs: Double = 0
        var totalFat: Double = 0
        var totalFiber: Double = 0
        var mealsWithMacros = 0

        for event in foodEvents {
            if let m = event.food.totalMacros, m != .zero {
                totalProtein += m.protein
                totalCarbs += m.carbs
                totalFat += m.fat
                totalFiber += m.fiber
                mealsWithMacros += 1
            }
        }

        guard mealsWithMacros >= 3 else { return [] }

        let totalMacroGrams = totalProtein + totalCarbs + totalFat
        guard totalMacroGrams > 0 else { return [] }

        let fatPercent = (totalFat / totalMacroGrams) * 100
        let carbPercent = (totalCarbs / totalMacroGrams) * 100
        let proteinPercent = (totalProtein / totalMacroGrams) * 100

        // Ideal macro split: ~30% protein, ~40% carbs, ~30% fat
        // Alert when significantly off balance

        // Too much fat (>40% of macros)
        if fatPercent > 40 {
            insights.append(Insight(
                type: .nutritionAlert,
                title: "High fat intake: \(Int(fatPercent))% of macros",
                body: "Fat makes up \(Int(fatPercent))% of your macronutrients (\(Int(totalFat))g over \(mealsWithMacros) meals). Try to keep it under 35% — swap fried foods for grilled or baked options.",
                priority: .medium,
                category: "food"
            ))
        }

        // Too many carbs (>55% of macros)
        if carbPercent > 55 {
            insights.append(Insight(
                type: .nutritionAlert,
                title: "Carb-heavy diet: \(Int(carbPercent))% of macros",
                body: "Carbs make up \(Int(carbPercent))% of your intake (\(Int(totalCarbs))g). Balance with more protein and healthy fats — try adding eggs, chicken, or lentils.",
                priority: .medium,
                category: "food"
            ))
        }

        // Too little protein (<20% of macros)
        if proteinPercent < 20 && totalMacroGrams > 100 {
            insights.append(Insight(
                type: .nutritionAlert,
                title: "Low protein: only \(Int(proteinPercent))% of macros",
                body: "You're getting \(Int(totalProtein))g protein across \(mealsWithMacros) meals (\(Int(proteinPercent))% of macros). Aim for 25-30% — add chicken, paneer, dal, eggs, or Greek yogurt.",
                priority: .medium,
                category: "food"
            ))
        }

        return insights
    }

    // MARK: - Over-Ordering

    private static func overOrderingInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let thisWeekOrders = foodEvents.filter {
            $0.date >= oneWeekAgo && $0.food.source == .emailOrder
        }

        guard thisWeekOrders.count >= 4 else { return [] }

        let totalSpent = thisWeekOrders.compactMap { $0.food.totalSpent }.reduce(0, +)
        let avgPerOrder = thisWeekOrders.compactMap { $0.food.totalSpent }.isEmpty
            ? 0
            : totalSpent / Double(thisWeekOrders.count)

        var insights: [Insight] = []

        // Too many orders in a week
        if thisWeekOrders.count >= 5 {
            insights.append(Insight(
                type: .foodSpending,
                title: "\(thisWeekOrders.count) food orders this week",
                body: "You've ordered \(thisWeekOrders.count) times in 7 days, spending $\(Int(totalSpent)). That's about $\(Int(avgPerOrder)) per order. Try cooking a few meals to save.",
                priority: .high,
                category: "food"
            ))
        } else {
            insights.append(Insight(
                type: .foodSpending,
                title: "\(thisWeekOrders.count) orders — $\(Int(totalSpent)) this week",
                body: "You've spent $\(Int(totalSpent)) on food delivery this week (~$\(Int(avgPerOrder))/order). That's \(thisWeekOrders.count) orders in 7 days.",
                priority: .medium,
                category: "food"
            ))
        }

        return insights
    }

    // MARK: - Weekly Order Trend

    private static func weeklyOrderTrend(events: [LifeEvent], foodEvents: [(date: Date, food: FoodLogEvent)]) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date())!

        let thisWeek = foodEvents.filter { $0.date >= oneWeekAgo && $0.food.source == .emailOrder }
        let lastWeek = foodEvents.filter { $0.date >= twoWeeksAgo && $0.date < oneWeekAgo && $0.food.source == .emailOrder }

        guard lastWeek.count >= 2 else { return [] }

        let thisWeekSpend = thisWeek.compactMap { $0.food.totalSpent }.reduce(0, +)
        let lastWeekSpend = lastWeek.compactMap { $0.food.totalSpent }.reduce(0, +)

        guard lastWeekSpend > 0 else { return [] }

        let changePercent = ((thisWeekSpend - lastWeekSpend) / lastWeekSpend) * 100

        if changePercent > 30 {
            return [Insight(
                type: .foodSpending,
                title: "Ordering \(Int(changePercent))% more than last week",
                body: "$\(Int(thisWeekSpend)) this week vs $\(Int(lastWeekSpend)) last week on food delivery. \(thisWeek.count) orders vs \(lastWeek.count).",
                priority: changePercent > 50 ? .high : .medium,
                category: "food"
            )]
        } else if changePercent < -30 && thisWeekSpend > 0 {
            return [Insight(
                type: .foodSpending,
                title: "Ordering \(Int(abs(changePercent)))% less — nice!",
                body: "$\(Int(thisWeekSpend)) this week vs $\(Int(lastWeekSpend)) last week. You're cutting back on delivery.",
                priority: .low,
                category: "food"
            )]
        }

        return []
    }

    // MARK: - Biggest Order

    private static func biggestOrderInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> Insight? {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let recentOrders = foodEvents.filter {
            $0.date >= oneWeekAgo && $0.food.source == .emailOrder && ($0.food.totalSpent ?? 0) > 0
        }

        guard recentOrders.count >= 3 else { return nil }

        let amounts = recentOrders.compactMap { $0.food.totalSpent }
        let avg = amounts.reduce(0, +) / Double(amounts.count)

        // Find orders significantly above average (1.5x+)
        if let biggest = recentOrders.max(by: { ($0.food.totalSpent ?? 0) < ($1.food.totalSpent ?? 0) }),
           let bigAmount = biggest.food.totalSpent, bigAmount > avg * 1.5, bigAmount > 30 {
            let restaurant = biggest.food.locationName ?? "a restaurant"
            return Insight(
                type: .foodSpending,
                title: "Big order: $\(Int(bigAmount)) from \(restaurant)",
                body: "That's \(String(format: "%.1f", bigAmount / avg))x your average order of $\(Int(avg)). Splurging is fine occasionally — just keep an eye on it.",
                priority: .low,
                category: "food"
            )
        }

        return nil
    }

    // MARK: - Protein Check

    private static func proteinInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> Insight? {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: foodEvents) { cal.startOfDay(for: $0.date) }

        let dailyProtein = byDay.compactMap { (_, events) -> Double? in
            let total = events.compactMap { $0.food.totalMacros?.protein }.reduce(0, +)
            return total > 0 ? total : nil
        }

        guard dailyProtein.count >= 3 else { return nil }

        let avgProtein = dailyProtein.reduce(0, +) / Double(dailyProtein.count)

        // WHO recommends ~0.8g/kg. For a 70kg person that's 56g.
        // Most fitness guidelines say 1.2-2g/kg for active people.
        if avgProtein < 40 {
            return Insight(
                type: .nutritionAlert,
                title: "Low protein: ~\(Int(avgProtein))g/day",
                body: "You're averaging only \(Int(avgProtein))g of protein per day. Most adults need 50-80g. Add eggs, chicken, lentils, paneer, or Greek yogurt.",
                priority: .medium,
                category: "food"
            )
        } else if avgProtein > 100 {
            return Insight(
                type: .foodPattern,
                title: "Strong protein intake: \(Int(avgProtein))g/day",
                body: "You're getting \(Int(avgProtein))g protein daily. Great for muscle maintenance and satiety.",
                priority: .low,
                category: "food"
            )
        }

        return nil
    }

    // MARK: - Fiber Check

    private static func fiberInsight(foodEvents: [(date: Date, food: FoodLogEvent)]) -> Insight? {
        let cal = Calendar.current
        let byDay = Dictionary(grouping: foodEvents) { cal.startOfDay(for: $0.date) }

        let dailyFiber = byDay.compactMap { (_, events) -> Double? in
            let total = events.compactMap { $0.food.totalMacros?.fiber }.reduce(0, +)
            return total > 0 ? total : nil
        }

        guard dailyFiber.count >= 3 else { return nil }

        let avgFiber = dailyFiber.reduce(0, +) / Double(dailyFiber.count)

        // Recommended: 25-30g/day
        if avgFiber < 15 {
            return Insight(
                type: .nutritionAlert,
                title: "Low fiber: ~\(Int(avgFiber))g/day",
                body: "You're getting \(Int(avgFiber))g of fiber daily (recommended: 25-30g). Add more vegetables, fruits, whole grains, or dal to your meals.",
                priority: .medium,
                category: "food"
            )
        }

        return nil
    }
}
