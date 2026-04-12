import Foundation

/// Generates "Spotify Wrapped"-style monthly summaries.
actor MonthlyWrappedEngine {
    static let shared = MonthlyWrappedEngine()

    struct MonthlyWrapped: Codable {
        let monthKey: String              // "2026-04"
        let monthName: String             // "April 2026"

        // Wealth
        var totalSpent: Double
        var totalIncome: Double
        var totalSaved: Double
        var topMerchant: String
        var topMerchantVisits: Int
        var topMerchantSpent: Double
        var topCategory: String
        var topCategorySpent: Double
        var transactionCount: Int
        var ghostSubsFound: Int
        var ghostSubsCost: Double

        // Health
        var totalSteps: Int
        var avgDailySteps: Int
        var totalDistanceKm: Double
        var totalWorkouts: Int
        var totalActiveCalories: Int
        var avgSleepHours: Double
        var bestStepDay: String?
        var bestStepCount: Int
        var longestWorkoutStreak: Int

        // Food
        var totalMealsLogged: Int
        var homeMeals: Int
        var eatingOutCount: Int
        var topStapleFood: String?
        var avgDailyCalories: Int
        var cookingStreakBest: Int

        // Life Score
        var avgLifeScore: Int
        var bestScoreDay: String?
        var bestScore: Int
        var daysAbove80: Int

        // Achievements earned this month
        var achievementsEarned: Int

        // Fun facts
        var funFacts: [String]
    }

    func generateWrapped(for date: Date? = nil) async -> MonthlyWrapped {
        let cal = Calendar.current
        let targetDate = date ?? Date()
        let month = cal.component(.month, from: targetDate)
        let year = cal.component(.year, from: targetDate)
        let monthKey = String(format: "%04d-%02d", year, month)

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let monthName = formatter.string(from: targetDate)

        let daysInMonth = cal.range(of: .day, in: .month, for: targetDate)?.count ?? 30
        let dayOfMonth = cal.component(.day, from: targetDate)
        let daysElapsed = max(dayOfMonth, 1)

        // Wealth data
        let transactions = await MainActor.run { TransactionStore.shared.transactions }
        let monthTxns = transactions.filter {
            cal.component(.month, from: $0.date) == month &&
            cal.component(.year, from: $0.date) == year
        }
        let debits = monthTxns.filter { $0.type.uppercased() == "DEBIT" }
        let credits = monthTxns.filter { $0.type.uppercased() == "CREDIT" }
        let totalSpent = debits.reduce(0) { $0 + abs($1.amount) }
        let totalIncome = credits.reduce(0) { $0 + abs($1.amount) }

        // Top merchant
        var merchantCounts: [String: (count: Int, amount: Double)] = [:]
        for txn in debits {
            let name = txn.merchant
            let existing = merchantCounts[name] ?? (0, 0)
            merchantCounts[name] = (existing.count + 1, existing.amount + abs(txn.amount))
        }
        let topMerchant = merchantCounts.max(by: { $0.value.count < $1.value.count })

        // Top category
        var categorySums: [String: Double] = [:]
        for txn in debits {
            categorySums[txn.category, default: 0] += abs(txn.amount)
        }
        let topCategory = categorySums.max(by: { $0.value < $1.value })

        // Ghost subs
        let ghostSubs = await MainActor.run { TransactionStore.shared.ghostSubscriptions }

        // Health data
        let health = HealthCollector.shared
        let todaySteps = await health.todaySteps()
        let sleepHrs = await health.lastNightSleepHours()
        let workoutStats = await health.recentWorkoutStats()
        let activeCals = await health.todayActiveCalories()

        // Approximate monthly totals from daily averages
        let avgSteps = todaySteps > 0 ? todaySteps : 0
        let totalStepsEst = avgSteps * daysElapsed
        let distanceKm = Double(totalStepsEst) * 0.0008 // ~0.8m per step

        // Food data
        let foodEntries = await FoodStore.shared.entriesForMonth()
        let allMeals = foodEntries.filter { !$0.items.isEmpty }
        let homeMeals = allMeals.filter { $0.source != .emailOrder }
        let eatingOut = allMeals.filter { $0.source == .emailOrder }

        // Staple foods (case-insensitive grouping so "Chicken" and "chicken" merge)
        var foodCounts: [String: (display: String, count: Int)] = [:]
        for entry in allMeals {
            for item in entry.items {
                let key = item.name.lowercased()
                let existing = foodCounts[key] ?? (display: item.name.capitalized, count: 0)
                foodCounts[key] = (display: existing.display, count: existing.count + 1)
            }
        }
        let topStaple = foodCounts.max(by: { $0.value.count < $1.value.count })

        // Average daily calories from actual food log data (was hardcoded to 0).
        let totalCaloriesMonth = allMeals.reduce(0) { $0 + ($1.totalCaloriesEstimate ?? 0) }
        let mealDays = Set(allMeals.map { cal.startOfDay(for: $0.timestamp) }).count
        let avgDailyCalories = mealDays > 0 ? totalCaloriesMonth / mealDays : 0

        // Longest cooking streak: count consecutive days where at least one
        // home-cooked meal was logged. Was hardcoded to 0.
        let cookingStreakBest = computeLongestCookingStreak(entries: homeMeals, calendar: cal)

        // Life scores
        let scores = await LifeScoreEngine.shared.recentScores(days: daysElapsed)
        let avgScore = scores.isEmpty ? 0 : scores.reduce(0) { $0 + $1.total } / scores.count
        let bestScoreEntry = scores.max { $0.total < $1.total }
        let daysAbove80 = scores.filter { $0.total >= 80 }.count

        // Achievements
        let achievements = await AchievementEngine.shared.allAchievements()
        let thisMonthAchievements = achievements.filter {
            cal.component(.month, from: $0.earnedAt) == month &&
            cal.component(.year, from: $0.earnedAt) == year
        }

        // Fun facts
        var funFacts: [String] = []
        if totalStepsEst > 0 {
            funFacts.append("You walked \(String(format: "%.1f", distanceKm)) km this month — that's \(Int(distanceKm / 0.1)) football fields!")
        }
        if totalSpent > 0 && !debits.isEmpty {
            let avgTransaction = totalSpent / Double(debits.count)
            funFacts.append("Your average transaction was \(NC.money(avgTransaction))")
        }
        if homeMeals.count > eatingOut.count * 2 {
            funFacts.append("You cooked at home \(homeMeals.count)x — your kitchen is getting a workout!")
        }
        if let topMerch = topMerchant, topMerch.value.count >= 5 {
            funFacts.append("\(topMerch.key) saw you \(topMerch.value.count) times this month")
        }
        if daysAbove80 > daysElapsed / 2 {
            funFacts.append("You scored 80+ on \(daysAbove80) days — more than half the month!")
        }

        // Parse best score date from dateKey
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE, MMM d"
        let dateKeyFormatter = DateFormatter()
        dateKeyFormatter.dateFormat = "yyyy-MM-dd"
        let bestScoreDay: String? = bestScoreEntry.flatMap { entry in
            dateKeyFormatter.date(from: entry.dateKey).map { dayFormatter.string(from: $0) }
        }

        return MonthlyWrapped(
            monthKey: monthKey,
            monthName: monthName,
            totalSpent: totalSpent,
            totalIncome: totalIncome,
            totalSaved: max(0, totalIncome - totalSpent),
            topMerchant: topMerchant?.key ?? "—",
            topMerchantVisits: topMerchant?.value.count ?? 0,
            topMerchantSpent: topMerchant?.value.amount ?? 0,
            topCategory: topCategory?.key ?? "—",
            topCategorySpent: topCategory?.value ?? 0,
            transactionCount: debits.count,
            ghostSubsFound: ghostSubs.count,
            ghostSubsCost: ghostSubs.reduce(0) { $0 + $1.amount },
            totalSteps: totalStepsEst,
            avgDailySteps: avgSteps,
            totalDistanceKm: distanceKm,
            totalWorkouts: Int(workoutStats.perWeek * Double(daysElapsed) / 7),
            totalActiveCalories: activeCals * daysElapsed,
            avgSleepHours: sleepHrs,
            bestStepDay: nil,
            bestStepCount: avgSteps,
            longestWorkoutStreak: workoutStats.streak,
            totalMealsLogged: allMeals.count,
            homeMeals: homeMeals.count,
            eatingOutCount: eatingOut.count,
            topStapleFood: topStaple?.value.display,
            avgDailyCalories: avgDailyCalories,
            cookingStreakBest: cookingStreakBest,
            avgLifeScore: avgScore,
            bestScoreDay: bestScoreDay,
            bestScore: bestScoreEntry?.total ?? 0,
            daysAbove80: daysAbove80,
            achievementsEarned: thisMonthAchievements.count,
            funFacts: funFacts
        )
    }

    /// Longest consecutive-days cooking streak in the given entries.
    /// A "day" counts if at least one entry exists for that day.
    private func computeLongestCookingStreak(entries: [FoodStore.FoodLogEntry], calendar: Calendar) -> Int {
        let days = Set(entries.map { calendar.startOfDay(for: $0.timestamp) })
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()

        var best = 1
        var current = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let day = sorted[i]
            if let expectedNext = calendar.date(byAdding: .day, value: 1, to: prev),
               calendar.isDate(expectedNext, inSameDayAs: day) {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
}
