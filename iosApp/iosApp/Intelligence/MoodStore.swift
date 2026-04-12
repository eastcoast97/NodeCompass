import Foundation

/// Tracks daily mood entries and correlates with life data.
actor MoodStore {
    static let shared = MoodStore()

    private let storeKey = "mood_entries"
    private var entries: [MoodEntry] = []

    struct MoodEntry: Codable, Identifiable {
        let id: String
        let date: Date
        let dateKey: String          // "2026-04-10"
        let mood: MoodLevel
        let note: String?
        let contextSnapshot: ContextSnapshot?
    }

    enum MoodLevel: Int, Codable, CaseIterable {
        case terrible = 1
        case bad = 2
        case okay = 3
        case good = 4
        case great = 5

        var emoji: String {
            switch self {
            case .terrible: return "😫"
            case .bad: return "😔"
            case .okay: return "😐"
            case .good: return "😊"
            case .great: return "🤩"
            }
        }

        var label: String {
            switch self {
            case .terrible: return "Terrible"
            case .bad: return "Bad"
            case .okay: return "Okay"
            case .good: return "Good"
            case .great: return "Great"
            }
        }

        var color: String {
            switch self {
            case .terrible: return "red"
            case .bad: return "orange"
            case .okay: return "yellow"
            case .good: return "teal"
            case .great: return "green"
            }
        }
    }

    /// Snapshot of context at mood log time — used for correlation.
    struct ContextSnapshot: Codable {
        var steps: Int
        var sleepHours: Double
        var workedOut: Bool
        var spentToday: Double
        var homeMeals: Int
        var lifeScore: Int
    }

    /// Correlation result.
    struct MoodCorrelation: Identifiable {
        var id: String { factor }
        let factor: String
        let icon: String
        let insight: String
        let impact: Impact
        let confidence: Double     // 0.0 to 1.0

        enum Impact: String {
            case positive, negative, neutral
        }
    }

    private init() {
        entries = loadEntries()
    }

    // MARK: - Log Mood

    func logMood(_ mood: MoodLevel, note: String? = nil) async {
        let todayKey = Self.dateKey(for: Date())

        // Capture context snapshot
        let health = HealthCollector.shared
        let steps = await health.todaySteps()
        let sleep = await health.lastNightSleepHours()
        let workoutStats = await health.recentWorkoutStats()
        let score = await LifeScoreEngine.shared.todayScore()
        let spend = await MainActor.run { TransactionStore.shared.totalSpendToday }
        let todayEntries = await FoodStore.shared.entriesForToday()
        let homeMeals = todayEntries.filter { !$0.items.isEmpty && $0.source != .emailOrder }.count

        let snapshot = ContextSnapshot(
            steps: steps,
            sleepHours: sleep,
            workedOut: workoutStats.streak > 0,
            spentToday: spend,
            homeMeals: homeMeals,
            lifeScore: score?.total ?? 0
        )

        // Remove existing entry for today (update)
        entries.removeAll { $0.dateKey == todayKey }

        let entry = MoodEntry(
            id: UUID().uuidString,
            date: Date(),
            dateKey: todayKey,
            mood: mood,
            note: note,
            contextSnapshot: snapshot
        )
        entries.append(entry)
        saveEntries()
    }

    // MARK: - Queries

    func todaysMood() -> MoodEntry? {
        let todayKey = Self.dateKey(for: Date())
        return entries.first { $0.dateKey == todayKey }
    }

    func recentEntries(days: Int = 30) -> [MoodEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return entries
            .filter { $0.date >= cutoff }
            .sorted { $0.date > $1.date }
    }

    func allEntries() -> [MoodEntry] {
        entries.sorted { $0.date > $1.date }
    }

    func clearAll() {
        entries = []
        saveEntries()
    }

    func averageMood(days: Int = 7) -> Double {
        let recent = recentEntries(days: days)
        guard !recent.isEmpty else { return 0 }
        return Double(recent.reduce(0) { $0 + $1.mood.rawValue }) / Double(recent.count)
    }

    func moodTrend() -> Int {
        let thisWeek = averageMood(days: 7)
        let lastWeek = averageMoodForRange(daysAgo: 14, to: 7)
        guard lastWeek > 0 else { return 0 }
        return Int((thisWeek - lastWeek) * 20) // scaled
    }

    func streakDays() -> Int {
        let sorted = entries.sorted { $0.date > $1.date }
        guard !sorted.isEmpty else { return 0 }
        var streak = 0
        let cal = Calendar.current
        var expectedDate = Date()
        for entry in sorted {
            if cal.isDate(entry.date, inSameDayAs: expectedDate) {
                streak += 1
                expectedDate = cal.date(byAdding: .day, value: -1, to: expectedDate)!
            } else {
                break
            }
        }
        return streak
    }

    // MARK: - Correlation Analysis

    func analyzeCorrelations() -> [MoodCorrelation] {
        let recent = recentEntries(days: 30)
        guard recent.count >= 5 else { return [] }

        var correlations: [MoodCorrelation] = []

        // Sleep correlation
        let withSleep = recent.filter { $0.contextSnapshot?.sleepHours ?? 0 > 0 }
        if withSleep.count >= 3 {
            let goodSleep = withSleep.filter { ($0.contextSnapshot?.sleepHours ?? 0) >= 7 }
            let badSleep = withSleep.filter { ($0.contextSnapshot?.sleepHours ?? 0) < 6 }
            let goodAvg = goodSleep.isEmpty ? 0 : Double(goodSleep.reduce(0) { $0 + $1.mood.rawValue }) / Double(goodSleep.count)
            let badAvg = badSleep.isEmpty ? 0 : Double(badSleep.reduce(0) { $0 + $1.mood.rawValue }) / Double(badSleep.count)
            if goodAvg > badAvg + 0.5 {
                correlations.append(MoodCorrelation(
                    factor: "Sleep", icon: "moon.zzz.fill",
                    insight: "You feel \(String(format: "%.0f", (goodAvg - badAvg) * 20))% better on days with 7+ hours of sleep",
                    impact: .positive, confidence: min(Double(withSleep.count) / 10, 1.0)
                ))
            }
        }

        // Exercise correlation
        let withWorkout = recent.filter { $0.contextSnapshot != nil }
        if withWorkout.count >= 3 {
            let exercised = withWorkout.filter { $0.contextSnapshot?.workedOut == true }
            let noExercise = withWorkout.filter { $0.contextSnapshot?.workedOut == false }
            let exAvg = exercised.isEmpty ? 0 : Double(exercised.reduce(0) { $0 + $1.mood.rawValue }) / Double(exercised.count)
            let noAvg = noExercise.isEmpty ? 0 : Double(noExercise.reduce(0) { $0 + $1.mood.rawValue }) / Double(noExercise.count)
            if exAvg > noAvg + 0.3 {
                correlations.append(MoodCorrelation(
                    factor: "Exercise", icon: "figure.run",
                    insight: "Working out lifts your mood — avg \(String(format: "%.1f", exAvg)) vs \(String(format: "%.1f", noAvg)) without",
                    impact: .positive, confidence: min(Double(withWorkout.count) / 10, 1.0)
                ))
            }
        }

        // Steps correlation
        let withSteps = recent.filter { ($0.contextSnapshot?.steps ?? 0) > 0 }
        if withSteps.count >= 3 {
            let activeDay = withSteps.filter { ($0.contextSnapshot?.steps ?? 0) >= 8000 }
            let sedentary = withSteps.filter { ($0.contextSnapshot?.steps ?? 0) < 4000 }
            let actAvg = activeDay.isEmpty ? 0 : Double(activeDay.reduce(0) { $0 + $1.mood.rawValue }) / Double(activeDay.count)
            let sedAvg = sedentary.isEmpty ? 0 : Double(sedentary.reduce(0) { $0 + $1.mood.rawValue }) / Double(sedentary.count)
            if actAvg > sedAvg + 0.3 {
                correlations.append(MoodCorrelation(
                    factor: "Activity", icon: "shoeprints.fill",
                    insight: "Active days (8K+ steps) correlate with better mood",
                    impact: .positive, confidence: min(Double(withSteps.count) / 10, 1.0)
                ))
            }
        }

        // Spending correlation — true median (average of two middle values for
        // even-length arrays, not just the lower midpoint)
        let withSpend = recent.filter { $0.contextSnapshot != nil }
        if withSpend.count >= Config.Mood.minCategoryEntries {
            let sorted = withSpend.map { $0.contextSnapshot?.spentToday ?? 0 }.sorted()
            let medianSpend: Double = {
                guard !sorted.isEmpty else { return 0 }
                let mid = sorted.count / 2
                if sorted.count % 2 == 0 {
                    return (sorted[mid - 1] + sorted[mid]) / 2
                } else {
                    return sorted[mid]
                }
            }()
            let highSpend = withSpend.filter { ($0.contextSnapshot?.spentToday ?? 0) > medianSpend * Config.Mood.highSpendMultiplier }
            let lowSpend = withSpend.filter { ($0.contextSnapshot?.spentToday ?? 0) <= medianSpend }
            let highAvg = highSpend.isEmpty ? 0 : Double(highSpend.reduce(0) { $0 + $1.mood.rawValue }) / Double(highSpend.count)
            let lowAvg = lowSpend.isEmpty ? 0 : Double(lowSpend.reduce(0) { $0 + $1.mood.rawValue }) / Double(lowSpend.count)
            if lowAvg > highAvg + Config.Mood.moderateEffectDelta {
                correlations.append(MoodCorrelation(
                    factor: "Spending", icon: NC.currencyIcon,
                    insight: "Your mood dips on heavy spending days",
                    impact: .negative,
                    confidence: min(Double(withSpend.count) / Config.Mood.maxConfidenceEntries, 1.0)
                ))
            }
        }

        // Home cooking correlation
        let withFood = recent.filter { $0.contextSnapshot != nil }
        if withFood.count >= 3 {
            let cooked = withFood.filter { ($0.contextSnapshot?.homeMeals ?? 0) > 0 }
            let noCooked = withFood.filter { ($0.contextSnapshot?.homeMeals ?? 0) == 0 }
            let cookAvg = cooked.isEmpty ? 0 : Double(cooked.reduce(0) { $0 + $1.mood.rawValue }) / Double(cooked.count)
            let noCookAvg = noCooked.isEmpty ? 0 : Double(noCooked.reduce(0) { $0 + $1.mood.rawValue }) / Double(noCooked.count)
            if cookAvg > noCookAvg + 0.3 {
                correlations.append(MoodCorrelation(
                    factor: "Home Cooking", icon: "frying.pan.fill",
                    insight: "Days you cook at home tend to be happier days",
                    impact: .positive, confidence: min(Double(withFood.count) / 10, 1.0)
                ))
            }
        }

        return correlations.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Helpers

    private func averageMoodForRange(daysAgo start: Int, to end: Int) -> Double {
        let cal = Calendar.current
        let from = cal.date(byAdding: .day, value: -start, to: Date())!
        let to = cal.date(byAdding: .day, value: -end, to: Date())!
        let range = entries.filter { $0.date >= from && $0.date < to }
        guard !range.isEmpty else { return 0 }
        return Double(range.reduce(0) { $0 + $1.mood.rawValue }) / Double(range.count)
    }

    private static func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func loadEntries() -> [MoodEntry] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([MoodEntry].self, from: data) else { return [] }
        return decoded
    }

    private func saveEntries() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
