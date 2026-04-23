import Foundation

/// Calculates a daily Life Score (0-100) from all pillars.
/// Wealth (30%) + Health (30%) + Food (20%) + Routine (20%)
///
/// Each sub-score is 0-100 independently, then weighted.
/// Scores are stored daily for trend tracking.
actor LifeScoreEngine {
    static let shared = LifeScoreEngine()

    private let storeKey = "life_scores"
    private var scores: [DailyScore] = []

    struct DailyScore: Codable, Identifiable {
        var id: String { dateKey }
        let dateKey: String          // "2026-04-10"
        let total: Int               // 0-100
        let wealth: Int
        let health: Int
        let food: Int
        let routine: Int
        let breakdown: ScoreBreakdown
        let calculatedAt: Date
    }

    struct ScoreBreakdown: Codable {
        // Wealth
        let budgetAdherence: Int     // Stayed under daily budget?
        let savingsRate: Int         // Income vs spend ratio
        let impulseControl: Int      // No unusual spikes?

        // Health
        let stepGoal: Int            // Hit step target?
        let sleepQuality: Int        // 7-9 hrs = perfect
        let workoutConsistency: Int  // Worked out today/recently?
        let activeCalories: Int      // Hit calorie burn target?

        // Food
        let homeCooking: Int         // Home-cooked vs eating out
        let mealConsistency: Int     // 3 meals logged?
        let nutritionBalance: Int    // Macros in range?

        // Routine
        let consistencyScore: Int    // Similar patterns to best days?
        let newPlaces: Int           // Explored somewhere new?
    }

    private init() {
        scores = loadScores()
    }

    // MARK: - Calculate Today's Score

    func calculateToday() async -> DailyScore {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let dateKey = Self.dateKey(for: today)

        // Get all the data we need
        let events = await EventStore.shared.events(since: cal.date(byAdding: .day, value: -30, to: today)!, source: nil)
        let profile = await UserProfileStore.shared.currentProfile()
        let goals = await GoalStore.shared.allGoals()
        // Today's events
        let todayEvents = events.filter { cal.isDateInToday($0.timestamp) }
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: today)!
        let weekEvents = events.filter { $0.timestamp >= oneWeekAgo }

        // === WEALTH (30%) ===
        let wealthResult = await calculateWealth(todayEvents: todayEvents, weekEvents: weekEvents, goals: goals)

        // === HEALTH (30%) ===
        let healthResult = await calculateHealth(todayEvents: todayEvents, weekEvents: weekEvents, profile: profile, goals: goals)

        // === FOOD (20%) ===
        let foodResult = await calculateFood(todayEvents: todayEvents, weekEvents: weekEvents, goals: goals)

        // === ROUTINE (20%) ===
        let routineResult = calculateRoutine(todayEvents: todayEvents, weekEvents: weekEvents, profile: profile)

        // Weighted total
        let wPart = Double(wealthResult.score) * 0.30
        let hPart = Double(healthResult.score) * 0.30
        let fPart = Double(foodResult.score) * 0.20
        let rPart = Double(routineResult.score) * 0.20
        let total = Int(wPart + hPart + fPart + rPart)

        let breakdown = ScoreBreakdown(
            budgetAdherence: wealthResult.budget,
            savingsRate: wealthResult.savings,
            impulseControl: wealthResult.impulse,
            stepGoal: healthResult.steps,
            sleepQuality: healthResult.sleep,
            workoutConsistency: healthResult.workout,
            activeCalories: healthResult.calories,
            homeCooking: foodResult.homeCooking,
            mealConsistency: foodResult.meals,
            nutritionBalance: foodResult.nutrition,
            consistencyScore: routineResult.consistency,
            newPlaces: routineResult.exploration
        )

        let score = DailyScore(
            dateKey: dateKey,
            total: min(100, max(0, total)),
            wealth: wealthResult.score,
            health: healthResult.score,
            food: foodResult.score,
            routine: routineResult.score,
            breakdown: breakdown,
            calculatedAt: Date()
        )

        // Store / update today's score
        scores.removeAll { $0.dateKey == dateKey }
        scores.append(score)
        saveScores()

        return score
    }

    // MARK: - History

    func todayScore() -> DailyScore? {
        let key = Self.dateKey(for: Date())
        return scores.first { $0.dateKey == key }
    }

    func recentScores(days: Int = 7) -> [DailyScore] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -days, to: Date())!
        return scores
            .filter { $0.calculatedAt >= cutoff }
            .sorted { $0.dateKey < $1.dateKey }
    }

    func averageScore(days: Int = 7) -> Int {
        let recent = recentScores(days: days)
        guard !recent.isEmpty else { return 0 }
        return recent.reduce(0) { $0 + $1.total } / recent.count
    }

    func trend() -> ScoreTrend {
        let thisWeek = averageScore(days: 7)
        let lastWeek = scores
            .filter {
                let cal = Calendar.current
                let d = cal.date(byAdding: .day, value: -14, to: Date())!
                let w = cal.date(byAdding: .day, value: -7, to: Date())!
                return $0.calculatedAt >= d && $0.calculatedAt < w
            }
        let lastWeekAvg = lastWeek.isEmpty ? thisWeek : lastWeek.reduce(0) { $0 + $1.total } / lastWeek.count
        let diff = thisWeek - lastWeekAvg
        if diff > 3 { return .improving(diff) }
        if diff < -3 { return .declining(abs(diff)) }
        return .stable
    }

    enum ScoreTrend {
        case improving(Int)
        case declining(Int)
        case stable
    }

    // MARK: - Wealth Calculation

    private struct WealthScore {
        let score: Int; let budget: Int; let savings: Int; let impulse: Int
    }

    private func calculateWealth(todayEvents: [LifeEvent], weekEvents: [LifeEvent], goals: [Goal]) async -> WealthScore {
        let cal = Calendar.current
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        let dayOfMonth = cal.component(.day, from: Date())

        let (monthlySpend, monthlyIncome) = await MainActor.run {
            (TransactionStore.shared.totalSpendThisMonth, TransactionStore.shared.totalIncomeThisMonth)
        }

        // Factor in subscription costs — separate recurring from discretionary
        let subMonthly = await SubscriptionManager.shared.monthlyTotal()
        let discretionarySpend = max(0, monthlySpend - subMonthly)

        // Budget adherence: are we on track for the month?
        // Subscriptions are expected charges, so only budget discretionary spending
        let budgetGoal = goals.first { $0.type == .spending }
        let monthlyBudget = budgetGoal?.targetValue ?? (monthlyIncome > 0 ? monthlyIncome * 0.7 : 50000)
        let discretionaryBudget = max(0, monthlyBudget - subMonthly)
        let expectedSpendByNow = discretionaryBudget * (Double(dayOfMonth) / Double(daysInMonth))
        let budgetRatio = expectedSpendByNow > 0 ? discretionarySpend / expectedSpendByNow : 1.0
        let budgetScore: Int
        if budgetRatio <= 0.8 { budgetScore = 100 }       // Under budget
        else if budgetRatio <= 1.0 { budgetScore = 80 }   // On track
        else if budgetRatio <= 1.2 { budgetScore = 50 }   // Slightly over
        else { budgetScore = max(0, 30 - Int((budgetRatio - 1.2) * 50)) }

        // Savings rate
        let savingsScore: Int
        if monthlyIncome > 0 {
            let rate = (monthlyIncome - monthlySpend) / monthlyIncome
            savingsScore = min(100, max(0, Int(rate * 200))) // 50% savings = 100
        } else {
            savingsScore = 50 // No income data, neutral
        }

        // Impulse control: today's spending vs daily average (excludes subscriptions)
        let todaySpend = todayEvents.compactMap { e -> Double? in
            if case .transaction(let t) = e.payload, !t.isCredit { return t.amount }
            return nil
        }.reduce(0, +)
        let avgDailySpend = dayOfMonth > 0 ? discretionarySpend / Double(dayOfMonth) : 0
        let impulseScore: Int
        if avgDailySpend == 0 { impulseScore = 80 }
        else if todaySpend <= avgDailySpend * 0.5 { impulseScore = 100 }
        else if todaySpend <= avgDailySpend { impulseScore = 80 }
        else if todaySpend <= avgDailySpend * 2 { impulseScore = 50 }
        else { impulseScore = 20 }

        let total = (budgetScore + savingsScore + impulseScore) / 3
        return WealthScore(score: total, budget: budgetScore, savings: savingsScore, impulse: impulseScore)
    }

    // MARK: - Health Calculation

    private struct HealthScore {
        let score: Int; let steps: Int; let sleep: Int; let workout: Int; let calories: Int
    }

    private func calculateHealth(todayEvents: [LifeEvent], weekEvents: [LifeEvent], profile: UserProfile, goals: [Goal]) async -> HealthScore {
        let health = HealthCollector.shared
        let steps = await health.todaySteps()
        let sleepHrs = await health.lastNightSleepHours()
        let cals = await health.todayActiveCalories()
        let workoutStats = await health.recentWorkoutStats()

        // Step goal
        let stepTarget = goals.first { $0.type == .steps }?.targetValue ?? 8000
        let stepScore = min(100, Int(Double(steps) / stepTarget * 100))

        // Sleep (7-9 hrs = perfect)
        let sleepScore: Int
        if sleepHrs >= 7 && sleepHrs <= 9 { sleepScore = 100 }
        else if sleepHrs >= 6 && sleepHrs <= 10 { sleepScore = 70 }
        else if sleepHrs >= 5 { sleepScore = 40 }
        else if sleepHrs > 0 { sleepScore = 20 }
        else { sleepScore = 0 }

        // Workout — combine HealthKit data with Place Intelligence gym visits
        // If user has a routine gym place with 3+ visits, validate workout streak
        let gymPlaces = profile.frequentLocations.filter {
            $0.behaviorTag?.contains("fitness") == true || $0.inferredType == "gym"
        }
        let weeklyGymVisits = gymPlaces.reduce(0) { total, loc in
            let recentVisits = (loc.visitDates ?? []).filter {
                $0.timeIntervalSinceNow > -7 * 86400
            }.count
            return total + recentVisits
        }
        // Boost workout score if place intelligence confirms gym attendance
        var workoutScore: Int
        if workoutStats.streak >= 3 { workoutScore = 100 }
        else if workoutStats.streak >= 1 { workoutScore = 70 }
        else if workoutStats.perWeek >= 3 { workoutScore = 60 }
        else if workoutStats.perWeek >= 1 { workoutScore = 40 }
        else { workoutScore = 10 }
        // Gym visit bonus: if Place Intelligence sees gym visits even without HealthKit workout data
        if weeklyGymVisits > 0 && workoutStats.perWeek == 0 {
            workoutScore = max(workoutScore, min(60, weeklyGymVisits * 20))
        }

        // Active calories
        let calTarget = goals.first { $0.type == .calories }?.targetValue ?? 400
        let calScore = min(100, Int(Double(cals) / calTarget * 100))

        let total = (stepScore + sleepScore + workoutScore + calScore) / 4
        return HealthScore(score: total, steps: stepScore, sleep: sleepScore, workout: workoutScore, calories: calScore)
    }

    // MARK: - Food Calculation

    private struct FoodScore {
        let score: Int; let homeCooking: Int; let meals: Int; let nutrition: Int
    }

    private func calculateFood(todayEvents: [LifeEvent], weekEvents: [LifeEvent], goals: [Goal]) async -> FoodScore {
        let todayEntries = await FoodStore.shared.entriesForToday()
        let loggedMeals = todayEntries.filter { !$0.items.isEmpty }.count

        // Meal consistency (3 meals = perfect)
        let mealScore: Int
        if loggedMeals >= 3 { mealScore = 100 }
        else if loggedMeals == 2 { mealScore = 70 }
        else if loggedMeals == 1 { mealScore = 40 }
        else { mealScore = 10 }

        // Home cooking ratio (this week)
        let weekFoodEvents = weekEvents.compactMap { e -> FoodLogEvent? in
            if case .foodLog(let f) = e.payload { return f }
            return nil
        }
        let homeMeals = weekFoodEvents.filter { $0.source == .manual || $0.source == .stapleSuggestion }.count
        let totalMeals = max(1, weekFoodEvents.count)
        let homeRatio = Double(homeMeals) / Double(totalMeals)
        let homeCookTarget = goals.first { $0.type == .homeCooking }?.targetValue ?? 60 // 60% default
        let homeCookScore = min(100, Int(homeRatio * 100 / homeCookTarget * 100))

        // Nutrition balance (if macros tracked)
        let todayMacros = todayEntries.compactMap { $0.totalMacros }
        let nutritionScore: Int
        if todayMacros.isEmpty {
            nutritionScore = 50 // Neutral if no data
        } else {
            let totalProtein = todayMacros.reduce(0.0) { $0 + $1.protein }
            let totalCarbs = todayMacros.reduce(0.0) { $0 + $1.carbs }
            let totalFat = todayMacros.reduce(0.0) { $0 + $1.fat }
            // Simple balance check: protein should be 20-35% of macros
            let totalGrams = totalProtein + totalCarbs + totalFat
            if totalGrams > 0 {
                let proteinPct = totalProtein / totalGrams * 100
                if proteinPct >= 20 && proteinPct <= 35 { nutritionScore = 100 }
                else if proteinPct >= 15 { nutritionScore = 70 }
                else { nutritionScore = 40 }
            } else {
                nutritionScore = 50
            }
        }

        let total = (mealScore + homeCookScore + nutritionScore) / 3
        return FoodScore(score: total, homeCooking: homeCookScore, meals: mealScore, nutrition: nutritionScore)
    }

    // MARK: - Routine Calculation

    private struct RoutineScore {
        let score: Int; let consistency: Int; let exploration: Int
    }

    private func calculateRoutine(todayEvents: [LifeEvent], weekEvents: [LifeEvent], profile: UserProfile) -> RoutineScore {
        // Consistency: did the user follow their typical patterns?
        let todayLocations = todayEvents.compactMap { e -> LocationEvent? in
            if case .locationVisit(let l) = e.payload { return l }
            return nil
        }

        // Did they visit their usual spots?
        // Weight routine places higher than non-routine places
        var consistencyPoints = 0
        for loc in todayLocations {
            if let match = profile.frequentLocations.first(where: { freq in
                freq.distance(to: loc.latitude, loc.longitude) < 200
            }) {
                // Routine places (3+ visits with behavior tag) score more
                if match.behaviorTag?.hasPrefix("routine") == true || match.behaviorTag?.hasPrefix("daily") == true {
                    consistencyPoints += 2  // Routine place = double weight
                } else {
                    consistencyPoints += 1  // Known but not routine
                }
            }
        }

        let totalConsistencyPoints = consistencyPoints

        let consistencyScore: Int
        if totalConsistencyPoints >= 5 { consistencyScore = 100 }
        else if totalConsistencyPoints >= 3 { consistencyScore = 80 }
        else if totalConsistencyPoints >= 1 { consistencyScore = 60 }
        else { consistencyScore = 40 }

        // Exploration: visited somewhere new this week?
        let weekLocations = weekEvents.compactMap { e -> LocationEvent? in
            if case .locationVisit(let l) = e.payload { return l }
            return nil
        }
        let newPlaces = weekLocations.filter { loc in
            !profile.frequentLocations.contains { freq in
                freq.distance(to: loc.latitude, loc.longitude) < 200
            }
        }.count

        let explorationScore: Int
        if newPlaces >= 3 { explorationScore = 100 }
        else if newPlaces >= 1 { explorationScore = 70 }
        else { explorationScore = 40 }

        let total = (consistencyScore * 7 + explorationScore * 3) / 10 // 70/30 split
        return RoutineScore(score: total, consistency: consistencyScore, exploration: explorationScore)
    }

    // MARK: - Persistence

    private static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func loadScores() -> [DailyScore] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([DailyScore].self, from: data) else { return [] }
        // Keep last 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        return decoded.filter { $0.calculatedAt >= cutoff }
    }

    private func saveScores() {
        if let data = try? JSONEncoder().encode(scores) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
