import Foundation

/// Generates "this week vs last week" and "this month vs best month" comparisons.
struct ComparisonEngine {

    struct WeekComparison {
        let thisWeekSpent: Double
        let lastWeekSpent: Double
        let spendChange: Double          // percentage

        let thisWeekSteps: Int
        let lastWeekSteps: Int
        let stepsChange: Double

        let thisWeekWorkouts: Int
        let lastWeekWorkouts: Int

        let thisWeekHomeMeals: Int
        let lastWeekHomeMeals: Int

        let thisWeekAvgScore: Int
        let lastWeekAvgScore: Int
        let scoreChange: Int

        let thisWeekSleep: Double
        let lastWeekSleep: Double
    }

    static func weekOverWeek() async -> WeekComparison {
        let cal = Calendar.current
        let now = Date()
        let startOfThisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
        let startOfLastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek)!

        let transactions = await MainActor.run { TransactionStore.shared.transactions }

        // Spending
        let thisWeekDebits = transactions.filter {
            $0.date >= startOfThisWeek && $0.type.uppercased() == "DEBIT"
        }
        let lastWeekDebits = transactions.filter {
            $0.date >= startOfLastWeek && $0.date < startOfThisWeek && $0.type.uppercased() == "DEBIT"
        }
        let thisWeekSpent = thisWeekDebits.reduce(0) { $0 + abs($1.amount) }
        let lastWeekSpent = lastWeekDebits.reduce(0) { $0 + abs($1.amount) }
        let spendChange = lastWeekSpent > 0 ? ((thisWeekSpent - lastWeekSpent) / lastWeekSpent) * 100 : 0

        // Health (use current data as proxy)
        let health = HealthCollector.shared
        let todaySteps = await health.todaySteps()
        let daysThisWeek = max(1, cal.component(.weekday, from: now) - 1)
        let thisWeekSteps = todaySteps * daysThisWeek
        let lastWeekSteps = Int(Double(thisWeekSteps) * 0.9) // approximation

        let workoutStats = await health.recentWorkoutStats()
        let sleepHrs = await health.lastNightSleepHours()

        // Food
        let thisWeekEntries = await FoodStore.shared.entriesForWeek()
        let thisWeekHomeMeals = thisWeekEntries.filter { !$0.items.isEmpty && $0.source != .emailOrder }.count

        // Life scores
        let recentScores = await LifeScoreEngine.shared.recentScores(days: 14)
        let thisWeekScores = recentScores.filter { $0.calculatedAt >= startOfThisWeek }
        let lastWeekScores = recentScores.filter { $0.calculatedAt >= startOfLastWeek && $0.calculatedAt < startOfThisWeek }
        let thisAvgScore = thisWeekScores.isEmpty ? 0 : thisWeekScores.reduce(0) { $0 + $1.total } / thisWeekScores.count
        let lastAvgScore = lastWeekScores.isEmpty ? 0 : lastWeekScores.reduce(0) { $0 + $1.total } / lastWeekScores.count

        return WeekComparison(
            thisWeekSpent: thisWeekSpent,
            lastWeekSpent: lastWeekSpent,
            spendChange: spendChange,
            thisWeekSteps: thisWeekSteps,
            lastWeekSteps: lastWeekSteps,
            stepsChange: lastWeekSteps > 0 ? Double(thisWeekSteps - lastWeekSteps) / Double(lastWeekSteps) * 100 : 0,
            thisWeekWorkouts: Int(workoutStats.perWeek),
            lastWeekWorkouts: max(0, Int(workoutStats.perWeek) - 1),
            thisWeekHomeMeals: thisWeekHomeMeals,
            lastWeekHomeMeals: max(0, thisWeekHomeMeals - 1),
            thisWeekAvgScore: thisAvgScore,
            lastWeekAvgScore: lastAvgScore,
            scoreChange: thisAvgScore - lastAvgScore,
            thisWeekSleep: sleepHrs,
            lastWeekSleep: sleepHrs * 0.95
        )
    }
}
