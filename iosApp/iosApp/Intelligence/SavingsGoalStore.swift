import Foundation

/// Manages smart savings goals with progress tracking and projections.
/// Calculates progress from actual income minus spending since goal creation.
actor SavingsGoalStore {
    static let shared = SavingsGoalStore()

    private let storeKey = "savings_goals"
    private var goals: [SavingsGoal] = []

    // MARK: - Models

    struct SavingsGoal: Codable, Identifiable {
        let id: String
        var name: String           // "Vacation to Bali"
        var targetAmount: Double   // 500000
        var deadline: Date?
        var icon: String           // SF Symbol
        var createdAt: Date
        var isCompleted: Bool
    }

    struct SavingsProgress: Identifiable {
        let id: String
        let goal: SavingsGoal
        let currentSaved: Double       // calculated from income - spending
        let percentage: Double
        let isOnTrack: Bool
        let projectedCompletion: Date?
        let monthlyRequired: Double    // to hit target by deadline
        let dailySuggested: Double     // daily budget to stay on track
    }

    private init() {
        goals = loadGoals()
    }

    // MARK: - Public API

    func allGoals() -> [SavingsGoal] {
        goals
    }

    func addGoal(name: String, target: Double, deadline: Date?, icon: String) {
        let goal = SavingsGoal(
            id: UUID().uuidString,
            name: name,
            targetAmount: target,
            deadline: deadline,
            icon: icon,
            createdAt: Date(),
            isCompleted: false
        )
        goals.append(goal)
        saveGoals()
    }

    func deleteGoal(id: String) {
        goals.removeAll { $0.id == id }
        saveGoals()
    }

    func markComplete(id: String) {
        guard let idx = goals.firstIndex(where: { $0.id == id }) else { return }
        goals[idx].isCompleted = true
        saveGoals()
    }

    func progressForAll() async -> [SavingsProgress] {
        let transactions = await MainActor.run { TransactionStore.shared.transactions }
        let cal = Calendar.current

        return goals.map { goal in
            // Filter transactions since goal was created
            let sinceCreation = transactions.filter { $0.date >= goal.createdAt }
            let totalIncome = sinceCreation
                .filter { $0.type.uppercased() == "CREDIT" }
                .reduce(0.0) { $0 + $1.amount }
            let totalSpend = sinceCreation
                .filter { $0.type.uppercased() == "DEBIT" }
                .reduce(0.0) { $0 + $1.amount }

            let currentSaved = max(0, totalIncome - totalSpend)
            let percentage = goal.targetAmount > 0 ? min(1.0, currentSaved / goal.targetAmount) : 0
            let remaining = max(0, goal.targetAmount - currentSaved)

            // Calculate savings rate per day
            let daysSinceCreation = max(1, cal.dateComponents([.day], from: goal.createdAt, to: Date()).day ?? 1)
            let dailySavingsRate = currentSaved / Double(daysSinceCreation)

            // Projected completion
            var projectedCompletion: Date? = nil
            if dailySavingsRate > 0 && remaining > 0 {
                let daysNeeded = Int(remaining / dailySavingsRate)
                projectedCompletion = cal.date(byAdding: .day, value: daysNeeded, to: Date())
            }

            // Monthly required and on-track check
            var monthlyRequired: Double = 0
            var isOnTrack = false

            if let deadline = goal.deadline {
                let monthsRemaining = max(1.0, Double(cal.dateComponents([.day], from: Date(), to: deadline).day ?? 30) / 30.0)
                monthlyRequired = remaining / monthsRemaining

                // Check if current pace would reach target by deadline
                if let projected = projectedCompletion {
                    isOnTrack = projected <= deadline
                } else if currentSaved >= goal.targetAmount {
                    isOnTrack = true
                }
            } else {
                // No deadline: always "on track" if saving anything
                monthlyRequired = dailySavingsRate * 30
                isOnTrack = dailySavingsRate > 0
            }

            let dailySuggested = monthlyRequired / 30.0

            return SavingsProgress(
                id: goal.id,
                goal: goal,
                currentSaved: currentSaved,
                percentage: percentage,
                isOnTrack: isOnTrack,
                projectedCompletion: projectedCompletion,
                monthlyRequired: monthlyRequired,
                dailySuggested: dailySuggested
            )
        }
    }

    func clearAll() {
        goals = []
        UserDefaults.standard.removeObject(forKey: storeKey)
    }

    // MARK: - Persistence

    private func loadGoals() -> [SavingsGoal] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([SavingsGoal].self, from: data) else { return [] }
        return decoded
    }

    private func saveGoals() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
