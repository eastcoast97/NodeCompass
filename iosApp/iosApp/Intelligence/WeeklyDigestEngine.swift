import Foundation

/// Generates a weekly digest summarizing the user's week across all pillars.
/// Scheduled for Sunday evening. Shows score trend, spending highlights,
/// health summary, and food patterns.
actor WeeklyDigestEngine {
    static let shared = WeeklyDigestEngine()

    private let storeKey = "weekly_digests"
    private var digests: [WeeklyDigest] = []

    struct WeeklyDigest: Codable, Identifiable {
        var id: String { weekKey }
        let weekKey: String              // "2026-W15"
        let generatedAt: Date

        // Score
        let avgScore: Int
        let scoreTrend: Int              // +/- vs last week
        let bestDay: String?             // "Tuesday"
        let bestDayScore: Int

        // Wealth
        let totalSpent: Double
        let spentVsLastWeek: Double      // % change
        let topCategory: String
        let topCategoryAmount: Double
        let savedAmount: Double

        // Health
        let avgSteps: Int
        let totalWorkouts: Int
        let avgSleep: Double
        let bestWorkoutDay: String?

        // Food
        let homeMeals: Int
        let totalMeals: Int
        let avgCalories: Int
        let topStaple: String?

        // Highlights (3-5 notable things)
        let highlights: [String]
    }

    private init() {
        digests = loadDigests()
    }

    // MARK: - Generate This Week's Digest

    func generateCurrentWeekDigest() async -> WeeklyDigest {
        let cal = Calendar.current
        let today = Date()
        let weekKey = Self.weekKey(for: today)

        // If already generated today, return cached
        if let existing = digests.first(where: { $0.weekKey == weekKey }) {
            return existing
        }

        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        let lastWeekStart = cal.date(byAdding: .day, value: -7, to: weekStart)!

        // Gather data
        let events = await EventStore.shared.events(since: lastWeekStart)
        let thisWeekEvents = events.filter { $0.timestamp >= weekStart }
        let lastWeekEvents = events.filter { $0.timestamp >= lastWeekStart && $0.timestamp < weekStart }

        // --- SCORES ---
        let scores = await LifeScoreEngine.shared.recentScores(days: 7)
        let avgScore = scores.isEmpty ? 0 : scores.reduce(0) { $0 + $1.total } / scores.count
        let lastWeekScores = await LifeScoreEngine.shared.recentScores(days: 14)
            .filter { $0.calculatedAt < weekStart }
        let lastWeekAvg = lastWeekScores.isEmpty ? avgScore : lastWeekScores.reduce(0) { $0 + $1.total } / lastWeekScores.count
        let scoreTrend = avgScore - lastWeekAvg

        let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let bestScore = scores.max(by: { $0.total < $1.total })
        let bestDayNum = bestScore.flatMap { s in
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: s.dateKey).map { cal.component(.weekday, from: $0) }
        }
        let bestDay = bestDayNum.map { dayNames[($0 - 1) % 7] }
        let bestDayScore = bestScore?.total ?? 0

        // --- WEALTH ---
        let thisWeekTxns = thisWeekEvents.compactMap { e -> TransactionEvent? in
            if case .transaction(let t) = e.payload { return t }
            return nil
        }
        let lastWeekTxns = lastWeekEvents.compactMap { e -> TransactionEvent? in
            if case .transaction(let t) = e.payload { return t }
            return nil
        }

        let thisWeekSpend = thisWeekTxns.filter { !$0.isCredit }.reduce(0.0) { $0 + $1.amount }
        let lastWeekSpend = lastWeekTxns.filter { !$0.isCredit }.reduce(0.0) { $0 + $1.amount }
        let spentChange = lastWeekSpend > 0 ? ((thisWeekSpend - lastWeekSpend) / lastWeekSpend) * 100 : 0

        let thisWeekIncome = thisWeekTxns.filter { $0.isCredit }.reduce(0.0) { $0 + $1.amount }
        let savedAmount = max(0, thisWeekIncome - thisWeekSpend)

        let categorySpends = Dictionary(grouping: thisWeekTxns.filter { !$0.isCredit }, by: { $0.category })
            .mapValues { $0.reduce(0.0) { $0 + $1.amount } }
        let topCat = categorySpends.max(by: { $0.value < $1.value })

        // --- HEALTH ---
        let healthSamples = thisWeekEvents.compactMap { e -> HealthSampleEvent? in
            if case .healthSample(let h) = e.payload { return h }
            return nil
        }
        let stepDays = healthSamples.filter { $0.metric == "steps" }
        let avgSteps = stepDays.isEmpty ? 0 : Int(stepDays.reduce(0.0) { $0 + $1.value } / Double(stepDays.count))

        let workoutEvents = thisWeekEvents.filter {
            if case .workout = $0.payload { return true }
            return false
        }
        let totalWorkouts = workoutEvents.count

        let sleepSamples = healthSamples.filter { $0.metric == "sleepAnalysis" }
        let avgSleep = sleepSamples.isEmpty ? 0 : sleepSamples.reduce(0.0) { $0 + $1.value } / Double(sleepSamples.count)

        // Count workouts per weekday, pick the day with the most workouts.
        // Previously used `workoutDays.first!` which crashes on empty arrays and
        // also picked an arbitrary day rather than the actual best.
        let workoutDays = workoutEvents.map { cal.component(.weekday, from: $0.timestamp) }
        let bestWorkoutDay: String? = {
            guard !workoutDays.isEmpty else { return nil }
            let counts = Dictionary(grouping: workoutDays, by: { $0 }).mapValues { $0.count }
            guard let topWeekday = counts.max(by: { $0.value < $1.value })?.key else { return nil }
            let index = (topWeekday - 1) % 7
            guard index >= 0 && index < dayNames.count else { return nil }
            return dayNames[index]
        }()

        // --- FOOD ---
        let foodEvents = thisWeekEvents.compactMap { e -> FoodLogEvent? in
            if case .foodLog(let f) = e.payload { return f }
            return nil
        }
        let totalMeals = foodEvents.count
        let homeMeals = foodEvents.filter { $0.source == .manual || $0.source == .stapleSuggestion }.count
        let totalCalories = foodEvents.reduce(0) { $0 + ($1.totalCaloriesEstimate ?? 0) }
        // Estimate days from week events timestamps
        let foodDays = Set(thisWeekEvents.filter { if case .foodLog = $0.payload { return true }; return false }
            .map { cal.startOfDay(for: $0.timestamp) }).count
        let avgCalories = foodDays > 0 ? totalCalories / foodDays : 0

        // Top staple
        let allItemNames = foodEvents.flatMap { $0.items.map { $0.name } }
        let itemCounts = Dictionary(grouping: allItemNames, by: { $0.lowercased() }).mapValues { $0.count }
        let topStaple = itemCounts.max(by: { $0.value < $1.value })?.key

        // --- HIGHLIGHTS ---
        var highlights: [String] = []
        if scoreTrend > 3 {
            highlights.append("Life Score up \(scoreTrend) points from last week")
        } else if scoreTrend < -3 {
            highlights.append("Life Score dipped \(abs(scoreTrend)) points — room to bounce back")
        }
        if spentChange < -10 {
            highlights.append("Spending down \(Int(abs(spentChange)))% vs last week")
        } else if spentChange > 20 {
            highlights.append("Spending up \(Int(spentChange))% — \(topCat?.key ?? "various") led the charge")
        }

        // Subscription cost awareness
        let subMonthly = await SubscriptionManager.shared.monthlyTotal()
        if subMonthly > 0 && thisWeekSpend > 0 {
            let subWeekly = subMonthly / 4.33
            let subPct = Int(subWeekly / thisWeekSpend * 100)
            if subPct >= 20 {
                highlights.append("Subscriptions account for ~\(subPct)% of weekly spend")
            }
        }

        if totalWorkouts >= 4 {
            highlights.append("Crushed it with \(totalWorkouts) workouts this week")
        } else if totalWorkouts == 0 {
            highlights.append("No workouts logged — fresh start next week?")
        }
        if homeMeals > totalMeals / 2 && totalMeals > 0 {
            highlights.append("Home-cooked majority: \(homeMeals) of \(totalMeals) meals")
        }
        if avgSteps >= 10000 {
            highlights.append("Averaging \(avgSteps.formatted()) steps — above 10K target")
        }

        // Place intelligence highlight — top spending place
        let profile = await UserProfileStore.shared.currentProfile()
        let topSpendingPlace = profile.frequentLocations
            .filter { $0.pillarTags?.contains("wealth") == true && $0.label != nil }
            .sorted { ($0.totalSpent ?? 0) > ($1.totalSpent ?? 0) }
            .first
        if let place = topSpendingPlace, let name = place.label, (place.totalSpent ?? 0) > 0 {
            highlights.append("Top spending spot: \(name) (\(place.visitCount) visits)")
        }

        // Routine consistency highlight
        let routinePlaces = profile.frequentLocations.filter { $0.behaviorTag?.hasPrefix("routine") == true }
        if routinePlaces.count >= 3 {
            highlights.append("Maintained \(routinePlaces.count) regular routines")
        }

        // Mood highlight
        let weekMood = await MoodStore.shared.averageMood(days: 7)
        if weekMood >= 4.0 {
            highlights.append("Great week mood-wise — averaging \(String(format: "%.1f", weekMood))/5")
        } else if weekMood > 0 && weekMood <= 2.5 {
            highlights.append("Tough week mood-wise — be gentle with yourself")
        }

        // Cap at 6 highlights
        let finalHighlights = Array(highlights.prefix(6))

        let digest = WeeklyDigest(
            weekKey: weekKey,
            generatedAt: Date(),
            avgScore: avgScore,
            scoreTrend: scoreTrend,
            bestDay: bestDay,
            bestDayScore: bestDayScore,
            totalSpent: thisWeekSpend,
            spentVsLastWeek: spentChange,
            topCategory: topCat?.key ?? "Other",
            topCategoryAmount: topCat?.value ?? 0,
            savedAmount: savedAmount,
            avgSteps: avgSteps,
            totalWorkouts: totalWorkouts,
            avgSleep: avgSleep,
            bestWorkoutDay: bestWorkoutDay,
            homeMeals: homeMeals,
            totalMeals: totalMeals,
            avgCalories: avgCalories,
            topStaple: topStaple,
            highlights: finalHighlights
        )

        digests.removeAll { $0.weekKey == weekKey }
        digests.append(digest)
        saveDigests()

        return digest
    }

    func allDigests() -> [WeeklyDigest] {
        digests.sorted { $0.weekKey > $1.weekKey }
    }

    func latestDigest() -> WeeklyDigest? {
        digests.max(by: { $0.weekKey < $1.weekKey })
    }

    func clearAll() {
        digests = []
        saveDigests()
    }

    // MARK: - Persistence

    private static func weekKey(for date: Date) -> String {
        let cal = Calendar.current
        let year = cal.component(.yearForWeekOfYear, from: date)
        let week = cal.component(.weekOfYear, from: date)
        return String(format: "%d-W%02d", year, week)
    }

    private func loadDigests() -> [WeeklyDigest] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([WeeklyDigest].self, from: data) else { return [] }
        return decoded
    }

    private func saveDigests() {
        if let data = try? JSONEncoder().encode(digests) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
