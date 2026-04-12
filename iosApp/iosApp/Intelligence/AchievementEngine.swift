import Foundation

/// Tracks streaks, milestones, and badges across all pillars.
/// Achievements are earned permanently; streaks are active/broken.
actor AchievementEngine {
    static let shared = AchievementEngine()

    private let storeKey = "achievements"
    private var state: AchievementState

    // MARK: - Models

    struct AchievementState: Codable {
        var earned: [Achievement]
        var streaks: [Streak]
        var stats: LifetimeStats
    }

    struct Achievement: Codable, Identifiable {
        let id: String
        let type: AchievementType
        let title: String
        let description: String
        let icon: String
        let earnedAt: Date
        let pillar: String           // wealth, health, food, routine
    }

    struct Streak: Codable, Identifiable {
        var id: String { type.rawValue }
        let type: StreakType
        var currentDays: Int
        var bestDays: Int
        var lastActiveDate: String   // "2026-04-10"
        var isActive: Bool
    }

    struct LifetimeStats: Codable {
        var totalWorkouts: Int
        var totalSteps: Int
        var totalHomeMeals: Int
        var daysUnderBudget: Int
        var daysScoreAbove80: Int
        var consecutiveLogDays: Int
        var totalSaved: Double
        var firstEventDate: Date?
    }

    enum AchievementType: String, Codable {
        // Wealth
        case budgetStreak3         // 3 days under budget
        case budgetStreak7         // 7 days under budget
        case budgetStreak30        // 30 days under budget
        case firstSavings          // First month with positive savings
        case savingsGoal           // Hit monthly savings goal
        case bigSaver              // Saved 3 months in a row

        // Health
        case firstWorkout          // First workout logged
        case workoutStreak3        // 3-day workout streak
        case workoutStreak7        // 7-day gym streak
        case steps10K              // First 10K step day
        case steps10KStreak7       // 10K steps for a week
        case sleepChamp            // 7+ hrs sleep for 7 days
        case marathonMonth         // 20+ workouts in a month
        case calorieGoal           // Hit active calorie goal 7 days

        // Food
        case firstHomeMeal         // First home-cooked meal logged
        case cookingStreak3        // 3-day cooking streak
        case cookingStreak7        // 7-day cooking streak
        case mealLogger            // Logged meals for 7 straight days
        case chefMode              // 20+ home meals in a month
        case balancedWeek          // Hit macro targets 5/7 days

        // Routine & Engagement
        case earlyBird             // Active before 7am for 5 days
        case explorer              // Visited 10 unique places
        case scoreAbove80          // Life score above 80
        case scoreAbove80Streak7   // Score above 80 for a week
        case weekStreak            // Used app 7 days in a row
        case monthStreak           // Used app 30 days in a row

        var icon: String {
            switch self {
            case .budgetStreak3, .budgetStreak7, .budgetStreak30: return NC.currencyIconCircle
            case .firstSavings, .savingsGoal, .bigSaver: return "banknote.fill"
            case .firstWorkout, .workoutStreak3, .workoutStreak7, .marathonMonth: return "figure.run"
            case .steps10K, .steps10KStreak7: return "shoeprints.fill"
            case .sleepChamp: return "moon.zzz.fill"
            case .calorieGoal: return "bolt.fill"
            case .firstHomeMeal, .cookingStreak3, .cookingStreak7, .chefMode: return "frying.pan.fill"
            case .mealLogger: return "fork.knife"
            case .balancedWeek: return "chart.pie.fill"
            case .earlyBird: return "sunrise.fill"
            case .explorer: return "map.fill"
            case .scoreAbove80, .scoreAbove80Streak7: return "star.fill"
            case .weekStreak, .monthStreak: return "flame.fill"
            }
        }

        var pillar: String {
            switch self {
            case .budgetStreak3, .budgetStreak7, .budgetStreak30,
                 .firstSavings, .savingsGoal, .bigSaver:
                return "wealth"
            case .firstWorkout, .workoutStreak3, .workoutStreak7,
                 .steps10K, .steps10KStreak7, .sleepChamp,
                 .marathonMonth, .calorieGoal:
                return "health"
            case .firstHomeMeal, .cookingStreak3, .cookingStreak7,
                 .mealLogger, .chefMode, .balancedWeek:
                return "food"
            case .earlyBird, .explorer, .scoreAbove80,
                 .scoreAbove80Streak7, .weekStreak, .monthStreak:
                return "routine"
            }
        }
    }

    enum StreakType: String, Codable, CaseIterable {
        case workout
        case steps10K
        case underBudget
        case homeCooking
        case mealLogging
        case goodSleep
        case scoreAbove80
        case appUsage

        var title: String {
            switch self {
            case .workout: return "Workout Streak"
            case .steps10K: return "10K Steps"
            case .underBudget: return "Under Budget"
            case .homeCooking: return "Home Cooking"
            case .mealLogging: return "Meal Logging"
            case .goodSleep: return "Good Sleep"
            case .scoreAbove80: return "Score 80+"
            case .appUsage: return "Daily Check-in"
            }
        }

        var icon: String {
            switch self {
            case .workout: return "figure.run"
            case .steps10K: return "shoeprints.fill"
            case .underBudget: return "banknote.fill"
            case .homeCooking: return "frying.pan.fill"
            case .mealLogging: return "fork.knife"
            case .goodSleep: return "moon.zzz.fill"
            case .scoreAbove80: return "star.fill"
            case .appUsage: return "flame.fill"
            }
        }
    }

    private init() {
        state = Self.loadState()
    }

    // MARK: - Check & Award

    /// Tracks which date we last finished `evaluateToday()`. Guards against
    /// accidental double-evaluation from concurrent foreground calls, which
    /// would otherwise double-increment streak counters and lifetime stats.
    private var lastEvaluatedDateKey: String?

    /// Called daily (or on app foreground) to evaluate streaks and award achievements.
    /// Idempotent for a given day: multiple calls on the same calendar day
    /// will only update state once.
    func evaluateToday() async -> [Achievement] {
        let cal = Calendar.current
        let todayKey = Self.dateKey(for: Date())

        // Idempotency guard: if we've already evaluated today, just return the
        // achievements that already exist without re-incrementing anything.
        if lastEvaluatedDateKey == todayKey {
            return state.earned.filter { Self.dateKey(for: $0.earnedAt) == todayKey }
        }

        var newAchievements: [Achievement] = []

        // Collect today's data
        let health = HealthCollector.shared
        let steps = await health.todaySteps()
        let sleepHrs = await health.lastNightSleepHours()
        let workoutStats = await health.recentWorkoutStats()
        let cals = await health.todayActiveCalories()

        let todayEntries = await FoodStore.shared.entriesForToday()
        let homeMealsToday = todayEntries.filter { !$0.items.isEmpty && $0.source != .emailOrder }.count
        let loggedMealsToday = todayEntries.filter { !$0.items.isEmpty }.count

        let score = await LifeScoreEngine.shared.todayScore()
        let todayScore = score?.total ?? 0

        let monthlySpend = await MainActor.run { TransactionStore.shared.totalSpendThisMonth }
        let monthlyIncome = await MainActor.run { TransactionStore.shared.totalIncomeThisMonth }
        let budgetGoal = await GoalStore.shared.allGoals().first { $0.type == .spending }
        let dayOfMonth = cal.component(.day, from: Date())
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        let dailyBudget = (budgetGoal?.targetValue ?? monthlyIncome * 0.7) / Double(daysInMonth)
        let expectedByNow = dailyBudget * Double(dayOfMonth)
        let underBudget = monthlySpend <= expectedByNow * 1.05

        // --- Update Streaks ---
        updateStreak(.workout, active: workoutStats.streak > 0, todayKey: todayKey)
        updateStreak(.steps10K, active: steps >= 10000, todayKey: todayKey)
        updateStreak(.underBudget, active: underBudget, todayKey: todayKey)
        updateStreak(.homeCooking, active: homeMealsToday > 0, todayKey: todayKey)
        updateStreak(.mealLogging, active: loggedMealsToday > 0, todayKey: todayKey)
        updateStreak(.goodSleep, active: sleepHrs >= 7 && sleepHrs <= 9, todayKey: todayKey)
        updateStreak(.scoreAbove80, active: todayScore >= 80, todayKey: todayKey)
        updateStreak(.appUsage, active: true, todayKey: todayKey)

        // --- Update Stats ---
        if workoutStats.streak > 0 { state.stats.totalWorkouts += 1 }
        state.stats.totalSteps += steps
        state.stats.totalHomeMeals += homeMealsToday
        if underBudget { state.stats.daysUnderBudget += 1 }
        if todayScore >= 80 { state.stats.daysScoreAbove80 += 1 }
        if monthlyIncome > monthlySpend { state.stats.totalSaved += (monthlyIncome - monthlySpend) / Double(daysInMonth) }

        // --- Check Achievements ---
        func award(_ type: AchievementType, title: String, desc: String) {
            guard !state.earned.contains(where: { $0.type == type }) else { return }
            let a = Achievement(id: UUID().uuidString, type: type, title: title,
                                description: desc, icon: type.icon, earnedAt: Date(), pillar: type.pillar)
            state.earned.append(a)
            newAchievements.append(a)
        }

        // Workout achievements
        let workoutStreak = streakDays(for: .workout)
        if workoutStats.streak >= 1 { award(.firstWorkout, title: "First Workout", desc: "Logged your first workout") }
        if workoutStreak >= 3 { award(.workoutStreak3, title: "3-Day Streak", desc: "Worked out 3 days in a row") }
        if workoutStreak >= 7 { award(.workoutStreak7, title: "Iron Week", desc: "7 consecutive workout days") }

        // Steps
        if steps >= 10000 { award(.steps10K, title: "10K Club", desc: "Hit 10,000 steps in a day") }
        if streakDays(for: .steps10K) >= 7 { award(.steps10KStreak7, title: "Step Master", desc: "10K steps for a full week") }

        // Sleep
        if streakDays(for: .goodSleep) >= 7 { award(.sleepChamp, title: "Sleep Champ", desc: "7+ hours of sleep for a whole week") }

        // Budget
        if streakDays(for: .underBudget) >= 3 { award(.budgetStreak3, title: "Budget Conscious", desc: "3 days under budget") }
        if streakDays(for: .underBudget) >= 7 { award(.budgetStreak7, title: "Budget Boss", desc: "A whole week under budget") }
        if streakDays(for: .underBudget) >= 30 { award(.budgetStreak30, title: "Budget Legend", desc: "30 days under budget!") }

        // Savings
        if monthlyIncome > monthlySpend && monthlyIncome > 0 {
            award(.firstSavings, title: "First Savings", desc: "Your first month with positive savings")
        }

        // Food
        if homeMealsToday > 0 { award(.firstHomeMeal, title: "Home Chef", desc: "Logged your first home meal") }
        if streakDays(for: .homeCooking) >= 3 { award(.cookingStreak3, title: "Cooking Streak", desc: "Home-cooked 3 days straight") }
        if streakDays(for: .homeCooking) >= 7 { award(.cookingStreak7, title: "Kitchen Hero", desc: "Home-cooked every day for a week") }
        if streakDays(for: .mealLogging) >= 7 { award(.mealLogger, title: "Meal Tracker", desc: "Logged meals 7 days in a row") }

        // Score
        if todayScore >= 80 { award(.scoreAbove80, title: "High Performer", desc: "Life Score hit 80+") }
        if streakDays(for: .scoreAbove80) >= 7 { award(.scoreAbove80Streak7, title: "Unstoppable", desc: "Score above 80 for a whole week") }

        // App usage
        if streakDays(for: .appUsage) >= 7 { award(.weekStreak, title: "Week Warrior", desc: "Checked in 7 days straight") }
        if streakDays(for: .appUsage) >= 30 { award(.monthStreak, title: "Monthly Master", desc: "30-day check-in streak!") }

        lastEvaluatedDateKey = todayKey
        saveState()
        return newAchievements
    }

    // MARK: - Public Queries

    func allAchievements() -> [Achievement] {
        state.earned.sorted { $0.earnedAt > $1.earnedAt }
    }

    func achievementCount() -> Int {
        state.earned.count
    }

    func activeStreaks() -> [Streak] {
        state.streaks.filter { $0.isActive && $0.currentDays > 0 }
    }

    func allStreaks() -> [Streak] {
        state.streaks
    }

    func stats() -> LifetimeStats {
        state.stats
    }

    func clearAll() {
        state = AchievementState(earned: [], streaks: [], stats: LifetimeStats(
            totalWorkouts: 0, totalSteps: 0, totalHomeMeals: 0,
            daysUnderBudget: 0, daysScoreAbove80: 0, consecutiveLogDays: 0,
            totalSaved: 0, firstEventDate: nil
        ))
        lastEvaluatedDateKey = nil
        saveState()
    }

    func streakDays(for type: StreakType) -> Int {
        state.streaks.first { $0.type == type }?.currentDays ?? 0
    }

    // All possible achievements for display (earned + locked)
    func allPossibleTypes() -> [AchievementType] {
        AchievementType.allCases
    }

    // MARK: - Streak Logic

    private func updateStreak(_ type: StreakType, active: Bool, todayKey: String) {
        if let idx = state.streaks.firstIndex(where: { $0.type == type }) {
            var streak = state.streaks[idx]
            if streak.lastActiveDate == todayKey {
                return // Already updated today
            }
            let yesterday = Self.dateKey(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
            if active {
                if streak.lastActiveDate == yesterday || streak.currentDays == 0 {
                    streak.currentDays += 1
                } else {
                    streak.currentDays = 1 // Gap, restart
                }
                streak.bestDays = max(streak.bestDays, streak.currentDays)
                streak.lastActiveDate = todayKey
                streak.isActive = true
            } else {
                streak.isActive = false
                // Don't reset currentDays until next active day
            }
            state.streaks[idx] = streak
        } else {
            // First time tracking this streak
            let streak = Streak(
                type: type,
                currentDays: active ? 1 : 0,
                bestDays: active ? 1 : 0,
                lastActiveDate: active ? todayKey : "",
                isActive: active
            )
            state.streaks.append(streak)
        }
    }

    // MARK: - Persistence

    private static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func loadState() -> AchievementState {
        guard let data = UserDefaults.standard.data(forKey: "achievements"),
              let decoded = try? JSONDecoder().decode(AchievementState.self, from: data) else {
            return AchievementState(earned: [], streaks: [], stats: LifetimeStats(
                totalWorkouts: 0, totalSteps: 0, totalHomeMeals: 0,
                daysUnderBudget: 0, daysScoreAbove80: 0, consecutiveLogDays: 0,
                totalSaved: 0, firstEventDate: nil
            ))
        }
        return decoded
    }

    private func saveState() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}

// MARK: - CaseIterable for AchievementType

extension AchievementEngine.AchievementType: CaseIterable {}
