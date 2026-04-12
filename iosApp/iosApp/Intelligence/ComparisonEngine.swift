import Foundation

/// Generates "this week vs last week" comparisons using REAL historical data
/// from the EventStore and TransactionStore, not fabricated multipliers.
///
/// Previously: `lastWeekSteps = thisWeekSteps * 0.9` (fake data).
/// Now: queries actual events from last week, falls back to today's snapshot
/// only if no historical data exists (first week of use).
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

        /// True if we have enough historical data to make meaningful comparisons.
        /// False during the first week of use when there's no "last week" yet.
        let hasHistoricalBaseline: Bool
    }

    static func weekOverWeek() async -> WeekComparison {
        let cal = Calendar.current
        let now = Date()
        let startOfThisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))
            ?? cal.startOfDay(for: now)
        let startOfLastWeek = cal.date(byAdding: .weekOfYear, value: -1, to: startOfThisWeek)
            ?? startOfThisWeek.addingTimeInterval(-7 * 86_400)

        let transactions = await MainActor.run { TransactionStore.shared.transactions }

        // Spending — real data for both weeks
        let thisWeekDebits = transactions.filter {
            $0.date >= startOfThisWeek && $0.type.uppercased() == "DEBIT"
        }
        let lastWeekDebits = transactions.filter {
            $0.date >= startOfLastWeek && $0.date < startOfThisWeek && $0.type.uppercased() == "DEBIT"
        }
        let thisWeekSpent = thisWeekDebits.reduce(0) { $0 + abs($1.amount) }
        let lastWeekSpent = lastWeekDebits.reduce(0) { $0 + abs($1.amount) }
        let spendChange = lastWeekSpent > 0 ? ((thisWeekSpent - lastWeekSpent) / lastWeekSpent) * 100 : 0

        // Health — pull real events from EventStore for both weeks
        let thisWeekEvents = await EventStore.shared.events(from: startOfThisWeek, to: now, sources: nil)
        let lastWeekEvents = await EventStore.shared.events(from: startOfLastWeek, to: startOfThisWeek, sources: nil)

        let thisWeekSteps = sumSteps(from: thisWeekEvents)
        let lastWeekSteps = sumSteps(from: lastWeekEvents)

        let thisWeekWorkouts = countWorkouts(from: thisWeekEvents)
        let lastWeekWorkouts = countWorkouts(from: lastWeekEvents)

        let thisWeekSleep = avgSleep(from: thisWeekEvents)
        let lastWeekSleep = avgSleep(from: lastWeekEvents)

        // If we have NO historical data at all (first week), blend with today's live
        // snapshot so the UI has *some* baseline rather than zeros everywhere.
        let hasHistoricalBaseline = lastWeekEvents.count > 0 || !lastWeekDebits.isEmpty
        let effectiveThisWeekSteps: Int
        let effectiveLastWeekSteps: Int
        if thisWeekSteps == 0 && lastWeekSteps == 0 {
            // First launch — use today's live HealthKit as a preview only
            let todaySteps = await HealthCollector.shared.todaySteps()
            let daysElapsed = max(1, cal.component(.weekday, from: now) - 1)
            effectiveThisWeekSteps = todaySteps * daysElapsed
            effectiveLastWeekSteps = 0
        } else {
            effectiveThisWeekSteps = thisWeekSteps
            effectiveLastWeekSteps = lastWeekSteps
        }

        // Food
        let thisWeekEntries = await FoodStore.shared.entriesForWeek()
        let thisWeekHomeMeals = thisWeekEntries.filter {
            !$0.items.isEmpty && $0.source != .emailOrder
        }.count

        let lastWeekHomeMeals = lastWeekEvents.compactMap { event -> Bool? in
            if case .foodLog(let food) = event.payload {
                return food.source == .manual || food.source == .stapleSuggestion
            }
            return nil
        }.filter { $0 }.count

        // Life scores — real data
        let recentScores = await LifeScoreEngine.shared.recentScores(days: 14)
        let thisWeekScores = recentScores.filter { $0.calculatedAt >= startOfThisWeek }
        let lastWeekScores = recentScores.filter { $0.calculatedAt >= startOfLastWeek && $0.calculatedAt < startOfThisWeek }
        let thisAvgScore = thisWeekScores.isEmpty ? 0 : thisWeekScores.reduce(0) { $0 + $1.total } / thisWeekScores.count
        let lastAvgScore = lastWeekScores.isEmpty ? 0 : lastWeekScores.reduce(0) { $0 + $1.total } / lastWeekScores.count

        let stepsChange: Double
        if effectiveLastWeekSteps > 0 {
            stepsChange = Double(effectiveThisWeekSteps - effectiveLastWeekSteps) / Double(effectiveLastWeekSteps) * 100
        } else {
            stepsChange = 0
        }

        return WeekComparison(
            thisWeekSpent: thisWeekSpent,
            lastWeekSpent: lastWeekSpent,
            spendChange: spendChange,
            thisWeekSteps: effectiveThisWeekSteps,
            lastWeekSteps: effectiveLastWeekSteps,
            stepsChange: stepsChange,
            thisWeekWorkouts: thisWeekWorkouts,
            lastWeekWorkouts: lastWeekWorkouts,
            thisWeekHomeMeals: thisWeekHomeMeals,
            lastWeekHomeMeals: lastWeekHomeMeals,
            thisWeekAvgScore: thisAvgScore,
            lastWeekAvgScore: lastAvgScore,
            scoreChange: thisAvgScore - lastAvgScore,
            thisWeekSleep: thisWeekSleep,
            lastWeekSleep: lastWeekSleep,
            hasHistoricalBaseline: hasHistoricalBaseline
        )
    }

    // MARK: - Event Aggregators

    private static func sumSteps(from events: [LifeEvent]) -> Int {
        let total = events.compactMap { event -> Double? in
            if case .healthSample(let sample) = event.payload, sample.metric == "stepCount" {
                return sample.value
            }
            return nil
        }.reduce(0, +)
        return Int(total.rounded())
    }

    private static func countWorkouts(from events: [LifeEvent]) -> Int {
        events.filter {
            if case .workout = $0.payload { return true }
            return false
        }.count
    }

    private static func avgSleep(from events: [LifeEvent]) -> Double {
        let sleepSamples = events.compactMap { event -> Double? in
            if case .healthSample(let sample) = event.payload, sample.metric == "sleepAnalysis" {
                return sample.value
            }
            return nil
        }
        guard !sleepSamples.isEmpty else { return 0 }
        return sleepSamples.reduce(0, +) / Double(sleepSamples.count)
    }
}

