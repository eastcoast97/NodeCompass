import Foundation

/// The differentiator — correlates events across data sources to produce
/// insights no single source could generate alone.
///
/// Examples:
/// - GPS at Chipotle + $12.50 charge → "You spent $12.50 at Chipotle on Market St"
/// - Gym visit + workout + smoothie purchase → "Morning gym → post-workout smoothie at Juice Bar"
/// - Late dinner + poor sleep → "Eating after 9 PM correlates with 40 min less sleep"
/// - Low step days + more delivery orders → "Sedentary days = 2x food delivery spending"
/// - Workout days + better sleep → "You sleep 30 min longer on workout days"
struct CrossSourceAnalyzer {

    static func analyze(events: [LifeEvent], profile: UserProfile) -> [Insight] {
        var insights: [Insight] = []

        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: Date())!
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        // Partition events by type for efficient cross-referencing
        let recentEvents = events.filter { $0.timestamp >= twoWeeksAgo }

        let transactions = recentEvents.compactMap { e -> (date: Date, txn: TransactionEvent)? in
            if case .transaction(let t) = e.payload { return (e.timestamp, t) }
            return nil
        }
        let locations = recentEvents.compactMap { e -> (date: Date, loc: LocationEvent)? in
            if case .locationVisit(let l) = e.payload { return (e.timestamp, l) }
            return nil
        }
        let workouts = recentEvents.compactMap { e -> (date: Date, w: WorkoutEvent)? in
            if case .workout(let w) = e.payload { return (e.timestamp, w) }
            return nil
        }
        let healthSamples = recentEvents.compactMap { e -> (date: Date, h: HealthSampleEvent)? in
            if case .healthSample(let h) = e.payload { return (e.timestamp, h) }
            return nil
        }
        let foodLogs = recentEvents.compactMap { e -> (date: Date, f: FoodLogEvent)? in
            if case .foodLog(let f) = e.payload { return (e.timestamp, f) }
            return nil
        }

        // 1. Location + Transaction correlation
        insights.append(contentsOf: locationSpendingCorrelation(
            transactions: transactions, locations: locations
        ))

        // 2. Workout → Post-workout spending pattern
        insights.append(contentsOf: workoutSpendingPattern(
            workouts: workouts, transactions: transactions
        ))

        // 3. Late eating + poor sleep correlation
        insights.append(contentsOf: lateEatingSleepCorrelation(
            foodLogs: foodLogs, healthSamples: healthSamples
        ))

        // 4. Sedentary days = more delivery
        insights.append(contentsOf: sedentaryDeliveryCorrelation(
            healthSamples: healthSamples, foodLogs: foodLogs, transactions: transactions
        ))

        // 5. Workout days = better sleep
        insights.append(contentsOf: workoutSleepCorrelation(
            workouts: workouts, healthSamples: healthSamples
        ))

        // 6. Weekend vs weekday spending + eating patterns
        insights.append(contentsOf: weekendVsWeekdayPattern(
            transactions: transactions, foodLogs: foodLogs
        ))

        // 7. Gym + restaurant pattern (gym then eat out)
        insights.append(contentsOf: gymThenEatOutPattern(
            locations: locations, workouts: workouts, foodLogs: foodLogs, transactions: transactions
        ))

        // 8. Spending velocity alert (burning through money fast)
        if let velocity = spendingVelocityInsight(transactions: transactions) {
            insights.append(velocity)
        }

        // 9. Mood proxy: activity + spending + sleep combined score
        insights.append(contentsOf: weeklyLifeScoreInsight(
            healthSamples: healthSamples, workouts: workouts,
            foodLogs: foodLogs, transactions: transactions
        ))

        return insights
    }

    // MARK: - 1. Location + Spending

    /// Match GPS visits to transactions within a time window.
    /// "You spent $38.22 at Ernesto's on Salem St"
    private static func locationSpendingCorrelation(
        transactions: [(date: Date, txn: TransactionEvent)],
        locations: [(date: Date, loc: LocationEvent)]
    ) -> [Insight] {
        var insights: [Insight] = []
        var matched = Set<String>()

        for loc in locations {
            guard let placeName = loc.loc.resolvedPlaceName,
                  let category = loc.loc.resolvedCategory,
                  ["restaurant", "cafe", "food", "bar", "fast_food", "bakery"].contains(where: { category.lowercased().contains($0) })
            else { continue }

            // Find transactions within 2 hours of the visit
            let window: TimeInterval = 7200
            for txn in transactions {
                guard !txn.txn.isCredit,
                      abs(txn.date.timeIntervalSince(loc.date)) < window,
                      !matched.contains(txn.txn.transactionId)
                else { continue }

                // Match merchant name loosely with place name
                let txnMerchant = txn.txn.merchant.lowercased()
                let place = placeName.lowercased()
                let isMatch = txnMerchant.contains(place) || place.contains(txnMerchant) ||
                              levenshteinSimilarity(txnMerchant, place) > 0.5

                // Also match food-related categories
                let foodCategories = ["food", "dining", "restaurant", "cafe"]
                let isFoodTxn = foodCategories.contains(where: { txn.txn.category.lowercased().contains($0) })

                if isMatch || (isFoodTxn && abs(txn.date.timeIntervalSince(loc.date)) < 3600) {
                    matched.insert(txn.txn.transactionId)
                    insights.append(Insight(
                        type: .locationCorrelation,
                        title: "\(NC.currencySymbol)\(Int(txn.txn.amount)) at \(placeName)",
                        body: "You visited \(placeName) and spent \(NC.currencySymbol)\(String(format: "%.2f", txn.txn.amount)). Matched from your location and bank transaction.",
                        priority: .low,
                        category: "spending",
                        relatedEventIds: [txn.txn.transactionId]
                    ))
                }
            }
        }

        // Only return the 3 most recent
        return Array(insights.prefix(3))
    }

    // MARK: - 2. Workout → Post-Workout Spending

    /// "After your gym sessions, you tend to spend $15 on food within an hour"
    private static func workoutSpendingPattern(
        workouts: [(date: Date, w: WorkoutEvent)],
        transactions: [(date: Date, txn: TransactionEvent)]
    ) -> [Insight] {
        guard workouts.count >= 3 else { return [] }

        var postWorkoutSpends: [(merchant: String, amount: Double)] = []

        for workout in workouts {
            let workoutEnd = workout.date.addingTimeInterval(workout.w.durationMinutes * 60)
            let window = workoutEnd.addingTimeInterval(5400) // 1.5 hours after workout ends

            for txn in transactions {
                guard !txn.txn.isCredit,
                      txn.date > workoutEnd && txn.date <= window
                else { continue }

                let foodCats = ["food", "dining", "restaurant", "cafe", "smoothie", "juice"]
                if foodCats.contains(where: { txn.txn.category.lowercased().contains($0) }) ||
                   foodCats.contains(where: { txn.txn.merchant.lowercased().contains($0) }) {
                    postWorkoutSpends.append((txn.txn.merchant, txn.txn.amount))
                }
            }
        }

        guard postWorkoutSpends.count >= 2 else { return [] }

        let avgSpend = postWorkoutSpends.map { $0.amount }.reduce(0, +) / Double(postWorkoutSpends.count)
        let topMerchant = Dictionary(grouping: postWorkoutSpends, by: { $0.merchant })
            .max(by: { $0.value.count < $1.value.count })?.key ?? "food spots"

        return [Insight(
            type: .locationCorrelation,
            title: "Post-workout spending: ~\(NC.currencySymbol)\(Int(avgSpend))",
            body: "After \(postWorkoutSpends.count) of your \(workouts.count) workouts, you grabbed food — often at \(topMerchant). That's ~\(NC.currencySymbol)\(Int(avgSpend)) per session.",
            priority: .medium,
            category: "spending"
        )]
    }

    // MARK: - 3. Late Eating + Poor Sleep

    /// "On nights you eat after 9 PM, you sleep 40 min less"
    private static func lateEatingSleepCorrelation(
        foodLogs: [(date: Date, f: FoodLogEvent)],
        healthSamples: [(date: Date, h: HealthSampleEvent)]
    ) -> [Insight] {
        let cal = Calendar.current

        let dinners = foodLogs.filter { $0.f.mealType == "dinner" || $0.f.mealType == "snack" }
        let sleepSamples = healthSamples.filter { $0.h.metric == "sleepAnalysis" && $0.h.value > 3 } // > 3 hours

        guard dinners.count >= 5, sleepSamples.count >= 5 else { return [] }

        // Group by day
        var lateDinnerSleep: [Double] = []
        var earlyDinnerSleep: [Double] = []

        for sleep in sleepSamples {
            let sleepDay = cal.startOfDay(for: sleep.date)
            let prevEvening = sleepDay.addingTimeInterval(-86400) // day before

            // Find dinner on the evening before this sleep
            let eveningMeals = dinners.filter {
                let mealDay = cal.startOfDay(for: $0.date)
                return mealDay == prevEvening || mealDay == sleepDay
            }

            guard let lastMeal = eveningMeals.max(by: { $0.date < $1.date }) else { continue }
            let mealHour = cal.component(.hour, from: lastMeal.date)

            if mealHour >= 21 { // 9 PM or later
                lateDinnerSleep.append(sleep.h.value)
            } else if mealHour >= 17 {
                earlyDinnerSleep.append(sleep.h.value)
            }
        }

        guard lateDinnerSleep.count >= 2, earlyDinnerSleep.count >= 2 else { return [] }

        let avgLate = lateDinnerSleep.reduce(0, +) / Double(lateDinnerSleep.count)
        let avgEarly = earlyDinnerSleep.reduce(0, +) / Double(earlyDinnerSleep.count)
        let diffMinutes = Int((avgEarly - avgLate) * 60)

        guard diffMinutes > 15 else { return [] }

        return [Insight(
            type: .eatingPattern,
            title: "Late eating costs you \(diffMinutes) min of sleep",
            body: "On nights you eat after 9 PM, you sleep ~\(String(format: "%.1f", avgLate))h vs \(String(format: "%.1f", avgEarly))h when you eat earlier. That's \(diffMinutes) fewer minutes of rest.",
            priority: .medium,
            category: "health"
        )]
    }

    // MARK: - 4. Sedentary Days = More Delivery

    /// "On low-activity days, you spend 2x more on food delivery"
    private static func sedentaryDeliveryCorrelation(
        healthSamples: [(date: Date, h: HealthSampleEvent)],
        foodLogs: [(date: Date, f: FoodLogEvent)],
        transactions: [(date: Date, txn: TransactionEvent)]
    ) -> [Insight] {
        let cal = Calendar.current

        // Daily step counts
        let stepsByDay = Dictionary(grouping: healthSamples.filter { $0.h.metric == "steps" }) {
            cal.startOfDay(for: $0.date)
        }.mapValues { $0.map { $0.h.value }.reduce(0, +) }

        guard stepsByDay.count >= 7 else { return [] }

        let avgSteps = stepsByDay.values.reduce(0, +) / Double(stepsByDay.count)
        let lowThreshold = avgSteps * 0.6

        // Food delivery spending by day
        let deliveryByDay = Dictionary(grouping: foodLogs.filter { $0.f.source == .emailOrder }) {
            cal.startOfDay(for: $0.date)
        }.mapValues { events in
            events.compactMap { $0.f.totalSpent }.reduce(0, +)
        }

        var lowDaySpend: [Double] = []
        var highDaySpend: [Double] = []

        for (day, steps) in stepsByDay {
            let spend = deliveryByDay[day] ?? 0
            if steps < lowThreshold {
                lowDaySpend.append(spend)
            } else {
                highDaySpend.append(spend)
            }
        }

        guard lowDaySpend.count >= 2, highDaySpend.count >= 2 else { return [] }

        let avgLowSpend = lowDaySpend.reduce(0, +) / Double(lowDaySpend.count)
        let avgHighSpend = highDaySpend.reduce(0, +) / Double(highDaySpend.count)

        guard avgHighSpend > 0, avgLowSpend > avgHighSpend * 1.3 else { return [] }

        let multiplier = avgLowSpend / avgHighSpend

        return [Insight(
            type: .eatingPattern,
            title: "Lazy days = \(String(format: "%.1f", multiplier))x more delivery",
            body: "On days you walk under \(Int(lowThreshold)) steps, you spend ~\(NC.currencySymbol)\(Int(avgLowSpend)) on food delivery vs \(NC.currencySymbol)\(Int(avgHighSpend)) on active days.",
            priority: .medium,
            category: "food"
        )]
    }

    // MARK: - 5. Workout Days = Better Sleep

    /// "You sleep 25 min longer on days you work out"
    private static func workoutSleepCorrelation(
        workouts: [(date: Date, w: WorkoutEvent)],
        healthSamples: [(date: Date, h: HealthSampleEvent)]
    ) -> [Insight] {
        let cal = Calendar.current

        let workoutDays = Set(workouts.map { cal.startOfDay(for: $0.date) })
        let sleepSamples = healthSamples.filter { $0.h.metric == "sleepAnalysis" && $0.h.value > 3 }

        guard sleepSamples.count >= 7, workoutDays.count >= 3 else { return [] }

        var workoutNightSleep: [Double] = []
        var restNightSleep: [Double] = []

        for sleep in sleepSamples {
            // Sleep on the night after a workout day
            let prevDay = cal.startOfDay(for: sleep.date.addingTimeInterval(-43200)) // noon yesterday
            if workoutDays.contains(prevDay) {
                workoutNightSleep.append(sleep.h.value)
            } else {
                restNightSleep.append(sleep.h.value)
            }
        }

        guard workoutNightSleep.count >= 2, restNightSleep.count >= 2 else { return [] }

        let avgWorkout = workoutNightSleep.reduce(0, +) / Double(workoutNightSleep.count)
        let avgRest = restNightSleep.reduce(0, +) / Double(restNightSleep.count)
        let diffMinutes = Int((avgWorkout - avgRest) * 60)

        guard diffMinutes > 10 else { return [] }

        return [Insight(
            type: .healthPattern,
            title: "Workouts add \(diffMinutes) min to your sleep",
            body: "On days you exercise, you sleep ~\(String(format: "%.1f", avgWorkout))h vs \(String(format: "%.1f", avgRest))h on rest days. Your body recovers better when you're active.",
            priority: .low,
            category: "health"
        )]
    }

    // MARK: - 6. Weekend vs Weekday Patterns

    /// "You spend 2.5x more on weekends and eat out 3x more"
    private static func weekendVsWeekdayPattern(
        transactions: [(date: Date, txn: TransactionEvent)],
        foodLogs: [(date: Date, f: FoodLogEvent)]
    ) -> [Insight] {
        let cal = Calendar.current

        let weekdayTxns = transactions.filter {
            let wd = cal.component(.weekday, from: $0.date)
            return wd >= 2 && wd <= 6 && !$0.txn.isCredit
        }
        let weekendTxns = transactions.filter {
            let wd = cal.component(.weekday, from: $0.date)
            return (wd == 1 || wd == 7) && !$0.txn.isCredit
        }

        guard weekdayTxns.count >= 5, weekendTxns.count >= 2 else { return [] }

        // Normalize to per-day
        let weekdayDays = max(1, Set(weekdayTxns.map { cal.startOfDay(for: $0.date) }).count)
        let weekendDays = max(1, Set(weekendTxns.map { cal.startOfDay(for: $0.date) }).count)

        let weekdayAvg = weekdayTxns.map { $0.txn.amount }.reduce(0, +) / Double(weekdayDays)
        let weekendAvg = weekendTxns.map { $0.txn.amount }.reduce(0, +) / Double(weekendDays)

        guard weekdayAvg > 0 else { return [] }

        let ratio = weekendAvg / weekdayAvg

        guard ratio > 1.5 || ratio < 0.6 else { return [] }

        var insights: [Insight] = []

        if ratio > 1.5 {
            insights.append(Insight(
                type: .spendingTrend,
                title: "Weekends cost \(String(format: "%.1f", ratio))x more",
                body: "You spend ~\(NC.currencySymbol)\(Int(weekendAvg))/day on weekends vs \(NC.currencySymbol)\(Int(weekdayAvg))/day on weekdays. That's where most of your budget goes.",
                priority: .medium,
                category: "spending"
            ))
        }

        // Weekend food delivery vs weekday
        let weekdayDelivery = foodLogs.filter {
            let wd = cal.component(.weekday, from: $0.date)
            return wd >= 2 && wd <= 6 && $0.f.source == .emailOrder
        }
        let weekendDelivery = foodLogs.filter {
            let wd = cal.component(.weekday, from: $0.date)
            return (wd == 1 || wd == 7) && $0.f.source == .emailOrder
        }

        if weekdayDelivery.count >= 2 && weekendDelivery.count >= 2 {
            let wdPerDay = Double(weekdayDelivery.count) / Double(weekdayDays)
            let wePerDay = Double(weekendDelivery.count) / Double(weekendDays)
            if wePerDay > wdPerDay * 1.5 && wePerDay > 0.5 {
                insights.append(Insight(
                    type: .eatingPattern,
                    title: "Weekend = takeout mode",
                    body: "You order delivery \(String(format: "%.1f", wePerDay * 7))x/week on weekends vs \(String(format: "%.1f", wdPerDay * 7))x on weekdays. Meal prepping on Sunday could save you \(NC.currencySymbol)\(Int(weekendDelivery.compactMap { $0.f.totalSpent }.reduce(0, +) / Double(weekendDays) * 0.5))/weekend.",
                    priority: .low,
                    category: "food"
                ))
            }
        }

        return insights
    }

    // MARK: - 7. Gym → Eat Out Pattern

    /// "After gym visits, you eat out 70% of the time"
    private static func gymThenEatOutPattern(
        locations: [(date: Date, loc: LocationEvent)],
        workouts: [(date: Date, w: WorkoutEvent)],
        foodLogs: [(date: Date, f: FoodLogEvent)],
        transactions: [(date: Date, txn: TransactionEvent)]
    ) -> [Insight] {
        guard workouts.count >= 4 else { return [] }

        var ateOutAfterGym = 0
        var cookedAfterGym = 0

        for workout in workouts {
            let workoutEnd = workout.date.addingTimeInterval(workout.w.durationMinutes * 60)
            let window = workoutEnd.addingTimeInterval(7200) // 2 hours

            let postMeals = foodLogs.filter { $0.date > workoutEnd && $0.date <= window }

            for meal in postMeals {
                if meal.f.source == .emailOrder || meal.f.source == .locationPrompt {
                    ateOutAfterGym += 1
                } else {
                    cookedAfterGym += 1
                }
            }
        }

        let total = ateOutAfterGym + cookedAfterGym
        guard total >= 3 else { return [] }

        let outPercent = Int(Double(ateOutAfterGym) / Double(total) * 100)

        if outPercent >= 60 {
            return [Insight(
                type: .eatingPattern,
                title: "Post-gym = eating out \(outPercent)% of the time",
                body: "After \(total) gym sessions, you ate out \(ateOutAfterGym) times vs cooked \(cookedAfterGym) times. Prepping a post-workout meal could save money and calories.",
                priority: .low,
                category: "food"
            )]
        }

        return []
    }

    // MARK: - 8. Spending Velocity

    /// "You've already spent 80% of last month's total and it's only the 15th"
    private static func spendingVelocityInsight(
        transactions: [(date: Date, txn: TransactionEvent)]
    ) -> Insight? {
        let cal = Calendar.current
        let now = Date()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30

        guard dayOfMonth >= 7 && dayOfMonth <= 25 else { return nil } // Only useful mid-month

        let thisMonthSpend = transactions
            .filter { $0.date >= startOfMonth && !$0.txn.isCredit }
            .map { $0.txn.amount }
            .reduce(0, +)

        // Last month total
        let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfMonth)!
        let lastMonthSpend = transactions
            .filter { $0.date >= startOfLastMonth && $0.date < startOfMonth && !$0.txn.isCredit }
            .map { $0.txn.amount }
            .reduce(0, +)

        guard lastMonthSpend > 0 else { return nil }

        let percentUsed = (thisMonthSpend / lastMonthSpend) * 100
        let percentOfMonth = Double(dayOfMonth) / Double(daysInMonth) * 100

        // Alert if spending pace is significantly ahead
        if percentUsed > percentOfMonth * 1.3 && percentUsed > 60 {
            let projected = thisMonthSpend / Double(dayOfMonth) * Double(daysInMonth)
            return Insight(
                type: .spendingTrend,
                title: "\(Int(percentUsed))% of last month's budget used",
                body: "You've spent \(NC.currencySymbol)\(Int(thisMonthSpend)) in \(dayOfMonth) days — on track for \(NC.currencySymbol)\(Int(projected)) this month vs \(NC.currencySymbol)\(Int(lastMonthSpend)) last month. That's \(Int(projected / lastMonthSpend * 100 - 100))% more.",
                priority: percentUsed > 90 ? .high : .medium,
                category: "spending"
            )
        }

        return nil
    }

    // MARK: - 9. Weekly Life Score

    /// A composite insight summarizing the week across all pillars.
    private static func weeklyLifeScoreInsight(
        healthSamples: [(date: Date, h: HealthSampleEvent)],
        workouts: [(date: Date, w: WorkoutEvent)],
        foodLogs: [(date: Date, f: FoodLogEvent)],
        transactions: [(date: Date, txn: TransactionEvent)]
    ) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let weekWorkouts = workouts.filter { $0.date >= oneWeekAgo }
        let weekSteps = healthSamples.filter { $0.date >= oneWeekAgo && $0.h.metric == "steps" }
        let weekFood = foodLogs.filter { $0.date >= oneWeekAgo }
        let weekSpend = transactions.filter { $0.date >= oneWeekAgo && !$0.txn.isCredit }

        // Need data from at least 2 pillars to make a cross-source insight
        var pillarsWithData = 0
        if !weekWorkouts.isEmpty || !weekSteps.isEmpty { pillarsWithData += 1 }
        if !weekFood.isEmpty { pillarsWithData += 1 }
        if !weekSpend.isEmpty { pillarsWithData += 1 }

        guard pillarsWithData >= 2 else { return [] }

        // Build a summary
        var parts: [String] = []

        // Spending
        let totalSpend = weekSpend.map { $0.txn.amount }.reduce(0, +)
        if totalSpend > 0 {
            parts.append("spent \(NC.currencySymbol)\(Int(totalSpend))")
        }

        // Food
        let homeMeals = weekFood.filter { $0.f.source == .manual || $0.f.source == .stapleSuggestion }.count
        let outMeals = weekFood.filter { $0.f.source == .emailOrder || $0.f.source == .locationPrompt }.count
        if homeMeals + outMeals > 0 {
            parts.append("\(homeMeals + outMeals) meals (\(homeMeals) homemade)")
        }

        // Activity
        if weekWorkouts.count > 0 {
            parts.append("\(weekWorkouts.count) workouts")
        }

        let totalSteps = weekSteps.map { $0.h.value }.reduce(0, +)
        if totalSteps > 0 {
            parts.append("\(Int(totalSteps / 1000))k steps")
        }

        guard parts.count >= 2 else { return [] }

        let summary = parts.joined(separator: ", ")

        return [Insight(
            type: .routine,
            title: "Your week: \(summary)",
            body: "This is your 7-day snapshot across spending, food, and activity. NodeCompass is tracking your patterns to help you improve.",
            priority: .low,
            category: "summary"
        )]
    }

    // MARK: - String Similarity (Levenshtein)

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
