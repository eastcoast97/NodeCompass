import Foundation

/// Predicts end-of-month spending based on current pace.
struct SpendingPredictor {

    struct Prediction {
        let currentSpent: Double
        let projectedTotal: Double
        let dailyAverage: Double
        let remainingBudget: Double
        let daysLeft: Int
        let dailyBudgetRemaining: Double
        let isOverPace: Bool
        let percentOverUnder: Double     // negative = under, positive = over
        let projectedSavings: Double
    }

    static func predict() async -> Prediction {
        let cal = Calendar.current
        let now = Date()
        let dayOfMonth = cal.component(.day, from: now)
        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let daysLeft = daysInMonth - dayOfMonth

        let currentSpent = await MainActor.run { TransactionStore.shared.totalSpendThisMonth }
        let totalIncome = await MainActor.run { TransactionStore.shared.totalIncomeThisMonth }

        // Budget from goals, or 70% of income, or a default
        let budgetGoal = await GoalStore.shared.allGoals().first { $0.type == .spending }
        let monthlyBudget = budgetGoal?.targetValue ?? (totalIncome > 0 ? totalIncome * 0.7 : currentSpent * 1.2)

        let dailyAvg = dayOfMonth > 0 ? currentSpent / Double(dayOfMonth) : 0
        let projectedTotal = dailyAvg * Double(daysInMonth)

        let remainingBudget = max(0, monthlyBudget - currentSpent)
        let dailyBudgetRemaining = daysLeft > 0 ? remainingBudget / Double(daysLeft) : 0

        let expectedByNow = monthlyBudget * Double(dayOfMonth) / Double(daysInMonth)
        let isOverPace = currentSpent > expectedByNow * 1.05
        let percentOverUnder = expectedByNow > 0 ? ((currentSpent - expectedByNow) / expectedByNow) * 100 : 0

        let projectedSavings = max(0, totalIncome - projectedTotal)

        return Prediction(
            currentSpent: currentSpent,
            projectedTotal: projectedTotal,
            dailyAverage: dailyAvg,
            remainingBudget: remainingBudget,
            daysLeft: daysLeft,
            dailyBudgetRemaining: dailyBudgetRemaining,
            isOverPace: isOverPace,
            percentOverUnder: percentOverUnder,
            projectedSavings: projectedSavings
        )
    }
}
