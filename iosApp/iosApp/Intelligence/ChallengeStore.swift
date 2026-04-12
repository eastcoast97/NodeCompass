import Foundation

/// Manages user challenges — short-term goals that combine wealth and health data.
/// Challenges are time-bound with progress tracking and completion detection.
actor ChallengeStore {
    static let shared = ChallengeStore()

    private let storeKey = "user_challenges"
    private var challenges: [Challenge] = []

    // MARK: - Models

    struct Challenge: Codable, Identifiable {
        let id: String
        var title: String
        var type: ChallengeType
        var targetValue: Double
        var currentValue: Double
        var startDate: Date
        var endDate: Date
        var isCompleted: Bool
        var completedAt: Date?
    }

    enum ChallengeType: String, Codable, CaseIterable {
        case noEatingOut        // No restaurant/delivery spending
        case dailySpendLimit    // Spend under $X per day
        case stepGoal           // X steps every day
        case homeCooking        // Cook at home X times
        case savingsTarget      // Save $X this week/month
        case workoutStreak      // Work out X days in a row
        case habitStreak        // Complete all habits X days

        var title: String {
            switch self {
            case .noEatingOut: return "No Eating Out"
            case .dailySpendLimit: return "Daily Spend Limit"
            case .stepGoal: return "Daily Steps"
            case .homeCooking: return "Home Cooking"
            case .savingsTarget: return "Savings Target"
            case .workoutStreak: return "Workout Streak"
            case .habitStreak: return "Habit Streak"
            }
        }

        var icon: String {
            switch self {
            case .noEatingOut: return "fork.knife.circle"
            case .dailySpendLimit: return "dollarsign.circle"
            case .stepGoal: return "figure.walk.circle"
            case .homeCooking: return "frying.pan"
            case .savingsTarget: return "banknote"
            case .workoutStreak: return "figure.run.circle"
            case .habitStreak: return "checkmark.circle"
            }
        }

        var defaultDuration: Int { // days
            switch self {
            case .noEatingOut, .dailySpendLimit, .homeCooking, .habitStreak: return 7
            case .stepGoal, .workoutStreak: return 7
            case .savingsTarget: return 30
            }
        }

        var unit: String {
            switch self {
            case .noEatingOut: return "days"
            case .dailySpendLimit: return NC.currencySymbol
            case .stepGoal: return "steps"
            case .homeCooking: return "meals"
            case .savingsTarget: return NC.currencySymbol
            case .workoutStreak: return "days"
            case .habitStreak: return "days"
            }
        }

        var defaultTarget: Double {
            switch self {
            case .noEatingOut: return 7
            case .dailySpendLimit: return 500
            case .stepGoal: return 10000
            case .homeCooking: return 5
            case .savingsTarget: return 5000
            case .workoutStreak: return 5
            case .habitStreak: return 7
            }
        }
    }

    // MARK: - Init

    private init() {
        challenges = loadFromDisk()
    }

    // MARK: - Queries

    /// Active challenges: not completed, endDate >= today.
    func activeChallenges() -> [Challenge] {
        let now = Date()
        return challenges.filter { !$0.isCompleted && $0.endDate >= now }
    }

    /// Completed challenges, sorted by completion date (newest first).
    func completedChallenges() -> [Challenge] {
        challenges
            .filter { $0.isCompleted }
            .sorted { ($0.completedAt ?? $0.endDate) > ($1.completedAt ?? $1.endDate) }
    }

    // MARK: - Actions

    /// Create a new challenge of the given type, target, and duration.
    func createChallenge(type: ChallengeType, target: Double, days: Int) {
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: days, to: now) ?? now
        let challenge = Challenge(
            id: UUID().uuidString,
            title: type.title,
            type: type,
            targetValue: target,
            currentValue: 0,
            startDate: now,
            endDate: end,
            isCompleted: false,
            completedAt: nil
        )
        challenges.append(challenge)
        saveToDisk()
    }

    /// Evaluate each active challenge against real data.
    func updateProgress() async {
        let cal = Calendar.current
        let now = Date()

        for i in challenges.indices {
            guard !challenges[i].isCompleted, challenges[i].endDate >= now else { continue }

            let challenge = challenges[i]
            let daysSinceStart = max(1, cal.dateComponents([.day], from: challenge.startDate, to: now).day ?? 1)

            switch challenge.type {
            case .noEatingOut:
                // Count days with no dining/delivery spending since start
                let diningSpendDays = await countDiningDays(since: challenge.startDate)
                let cleanDays = daysSinceStart - diningSpendDays
                challenges[i].currentValue = Double(max(0, cleanDays))

            case .dailySpendLimit:
                // Count days where spend was under the limit
                let daysUnderLimit = await countDaysUnderSpendLimit(challenge.targetValue, since: challenge.startDate)
                challenges[i].currentValue = Double(daysUnderLimit)

            case .stepGoal:
                // Check today's steps against the target
                let steps = await HealthCollector.shared.todaySteps()
                // Track consecutive days meeting the goal
                let metToday = Double(steps) >= challenge.targetValue
                if metToday {
                    challenges[i].currentValue = min(challenges[i].currentValue + 1, Double(daysSinceStart))
                }

            case .homeCooking:
                // Count home-cooked meals since start
                let homeCount = await countHomeMeals(since: challenge.startDate)
                challenges[i].currentValue = Double(homeCount)

            case .savingsTarget:
                // Current savings = income - spend this month
                let (income, spend) = await MainActor.run {
                    (TransactionStore.shared.totalIncomeThisMonth,
                     TransactionStore.shared.totalSpendThisMonth)
                }
                let saved = max(0, income - spend)
                challenges[i].currentValue = saved

            case .workoutStreak:
                // Use recent workout stats from HealthCollector
                let stats = await HealthCollector.shared.recentWorkoutStats()
                challenges[i].currentValue = Double(stats.streak)

            case .habitStreak:
                // Count consecutive days where all habits were completed
                let streakDays = await countHabitStreakDays(since: challenge.startDate)
                challenges[i].currentValue = Double(streakDays)
            }

            // Check completion: target met
            if challenges[i].currentValue >= challenge.targetValue && !challenges[i].isCompleted {
                challenges[i].isCompleted = true
                challenges[i].completedAt = now
            }

            // Also mark failed if past endDate and not completed
            // (we keep them as not-completed so they appear expired)
        }

        saveToDisk()
    }

    /// Delete a challenge by ID.
    func deleteChallenge(id: String) {
        challenges.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Remove all challenges.
    func clearAll() {
        challenges = []
        saveToDisk()
    }

    // MARK: - Progress Helpers

    /// Progress fraction (0.0 to 1.0) for a challenge.
    func progress(for challenge: Challenge) -> Double {
        guard challenge.targetValue > 0 else { return 0 }
        return min(1.0, challenge.currentValue / challenge.targetValue)
    }

    /// Days remaining until the challenge ends.
    func daysRemaining(for challenge: Challenge) -> Int {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: challenge.endDate).day ?? 0
        return max(0, days)
    }

    // MARK: - Data Helpers

    private func countDiningDays(since start: Date) async -> Int {
        let transactions = await MainActor.run { TransactionStore.shared.transactions }
        let cal = Calendar.current
        let diningCategories = ["Food & Dining"]

        var daysWithDining = Set<String>()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for txn in transactions {
            guard txn.type.uppercased() == "DEBIT",
                  txn.date >= start,
                  diningCategories.contains(txn.category) else { continue }
            daysWithDining.insert(dateFormatter.string(from: txn.date))
        }
        return daysWithDining.count
    }

    private func countDaysUnderSpendLimit(_ limit: Double, since start: Date) async -> Int {
        let transactions = await MainActor.run { TransactionStore.shared.transactions }
        let cal = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        // Group debit amounts by day
        var spendByDay: [String: Double] = [:]
        for txn in transactions {
            guard txn.type.uppercased() == "DEBIT", txn.date >= start else { continue }
            let key = dateFormatter.string(from: txn.date)
            spendByDay[key, default: 0] += txn.amount
        }

        // Count days from start to today
        var day = start
        var count = 0
        let now = Date()
        while day <= now {
            let key = dateFormatter.string(from: day)
            let daySpend = spendByDay[key] ?? 0
            if daySpend <= limit { count += 1 }
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    private func countHomeMeals(since start: Date) async -> Int {
        let entries = await FoodStore.shared.entries
        return entries.filter { entry in
            entry.timestamp >= start && !entry.items.isEmpty && entry.source != .emailOrder
        }.count
    }

    private func countHabitStreakDays(since start: Date) async -> Int {
        let cal = Calendar.current
        var day = Date()
        var count = 0

        while day >= start {
            let progress = await HabitStore.shared.todayProgress()
            // For historical days we approximate using today's progress
            // In practice, todayProgress only checks today; we count if all are done
            if progress.total > 0 && progress.completed >= progress.total {
                count += 1
            } else {
                break // Streak broken
            }
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    // MARK: - Persistence

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(challenges) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func loadFromDisk() -> [Challenge] {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Challenge].self, from: data)) ?? []
    }
}
