import Foundation

/// Generates "Today's Pulse" — a single synthesized sentence that captures
/// the user's day across all pillars (wealth, health, food, location).
///
/// Replaces the old dashboard's 8-button Quick Action grid with one
/// glanceable summary. Research shows this is the cross-source insight
/// users actually want from a multi-signal app.
///
/// Example outputs:
///   - "Quiet spending day. 8,200 steps. You cooked at home."
///   - "Still learning — come back tomorrow for patterns."
///   - "Active morning — 12k steps and a workout. $45 spent on coffee + lunch."
actor TodayPulseEngine {
    static let shared = TodayPulseEngine()

    struct TodayPulse {
        /// The headline synthesis — one to two short sentences.
        let headline: String
        /// Secondary detail line — optional extra context.
        let detail: String?
        /// Icon representing the overall "vibe" of the day.
        let icon: String
        /// Tone: positive / neutral / needsAttention. Used to color the UI
        /// without being explicitly judgmental.
        let tone: Tone
        /// Fragments used to build the headline — useful for debugging and
        /// for the dashboard to show "source" chips.
        let fragments: [Fragment]

        enum Tone {
            case positive
            case neutral
            case needsAttention
            case warmingUp
        }

        struct Fragment {
            let icon: String
            let text: String
            let pillar: String
        }
    }

    private init() {}

    /// Generate today's pulse by pulling live data from all engines.
    func generate() async -> TodayPulse {
        let stage = await AppLearningStage.shared.currentStage

        // Warming up stage — no judgment, just encouragement
        if stage == .warmingUp {
            let days = await AppLearningStage.shared.daysUntilNextStage
            return TodayPulse(
                headline: "Getting to know you.",
                detail: days > 0 ? "\(days) day\(days == 1 ? "" : "s") until patterns appear." : "Patterns unlock soon.",
                icon: "sparkle.magnifyingglass",
                tone: .warmingUp,
                fragments: []
            )
        }

        // Collect live data
        let health = HealthCollector.shared
        async let steps = health.todaySteps()
        async let sleep = health.lastNightSleepHours()
        async let workouts = health.recentWorkoutStats()
        let stepsVal = await steps
        let sleepVal = await sleep
        let workoutStats = await workouts

        let todaySpend = await MainActor.run { TransactionStore.shared.totalSpendToday }
        let todaySpendCurrency = await MainActor.run { TransactionStore.shared.transactions.first?.currencySymbol ?? "$" }

        let foodEntries = await FoodStore.shared.entriesForToday()
        let hasLoggedFood = !foodEntries.filter { !$0.items.isEmpty }.isEmpty
        let homeCooked = foodEntries.filter { !$0.items.isEmpty && $0.source != .emailOrder }.count
        let delivered = foodEntries.filter { $0.source == .emailOrder }.count

        // Mood
        let todayMood = await MoodStore.shared.todaysMood()

        // Habits
        let habitProgress = await HabitStore.shared.todayProgress()

        // Build fragments
        var fragments: [TodayPulse.Fragment] = []
        var positiveSignals = 0
        var concernSignals = 0

        // Spending signal
        if todaySpend > 0 {
            fragments.append(.init(
                icon: NC.currencyIcon,
                text: "\(todaySpendCurrency)\(Int(todaySpend).formatted()) spent",
                pillar: "wealth"
            ))
        } else if stage >= .tracking {
            fragments.append(.init(
                icon: "sparkles",
                text: "No spending yet",
                pillar: "wealth"
            ))
            positiveSignals += 1
        }

        // Steps signal
        if stepsVal >= Int(Config.Health.idealStepsPerDay) {
            fragments.append(.init(
                icon: "figure.walk",
                text: "\(stepsVal.formatted()) steps",
                pillar: "health"
            ))
            positiveSignals += 1
        } else if stepsVal >= Int(Config.Health.lowStepsWarning) {
            fragments.append(.init(
                icon: "figure.walk",
                text: "\(stepsVal.formatted()) steps",
                pillar: "health"
            ))
        } else if stepsVal > 0 {
            fragments.append(.init(
                icon: "figure.walk",
                text: "\(stepsVal.formatted()) steps",
                pillar: "health"
            ))
            concernSignals += 1
        }

        // Workout signal
        if workoutStats.streak > 0 {
            fragments.append(.init(
                icon: "flame.fill",
                text: "\(workoutStats.streak)-day workout streak",
                pillar: "health"
            ))
            positiveSignals += 1
        }

        // Sleep signal
        if sleepVal >= Config.Health.idealSleepHoursMin && sleepVal <= Config.Health.idealSleepHoursMax {
            fragments.append(.init(
                icon: "bed.double.fill",
                text: "\(String(format: "%.1f", sleepVal))h slept",
                pillar: "health"
            ))
            positiveSignals += 1
        } else if sleepVal > 0 && sleepVal < Config.Health.sleepWarningMin {
            fragments.append(.init(
                icon: "bed.double.fill",
                text: "\(String(format: "%.1f", sleepVal))h slept",
                pillar: "health"
            ))
            concernSignals += 1
        }

        // Food signal
        if homeCooked > 0 && delivered == 0 {
            fragments.append(.init(
                icon: "fork.knife",
                text: "Cooked at home",
                pillar: "food"
            ))
            positiveSignals += 1
        } else if delivered > 0 && homeCooked == 0 {
            fragments.append(.init(
                icon: "bag.fill",
                text: "\(delivered) delivery order\(delivered == 1 ? "" : "s")",
                pillar: "food"
            ))
        } else if hasLoggedFood {
            fragments.append(.init(
                icon: "fork.knife",
                text: "\(homeCooked + delivered) meal\(homeCooked + delivered == 1 ? "" : "s") logged",
                pillar: "food"
            ))
        }

        // Mood signal
        if let mood = todayMood {
            let moodLabel = mood.mood.label
            fragments.append(.init(
                icon: "face.smiling",
                text: "Feeling \(moodLabel)",
                pillar: "mind"
            ))
            if mood.mood.rawValue >= 4 { positiveSignals += 1 }
            else if mood.mood.rawValue <= 2 { concernSignals += 1 }
        }

        // Habits signal
        if habitProgress.total > 0 {
            let done = habitProgress.completed
            let total = habitProgress.total
            if done == total {
                fragments.append(.init(
                    icon: "checkmark.circle.fill",
                    text: "All \(total) habits done",
                    pillar: "mind"
                ))
                positiveSignals += 1
            } else if done > 0 {
                fragments.append(.init(
                    icon: "checkmark.circle",
                    text: "\(done)/\(total) habits",
                    pillar: "mind"
                ))
            } else {
                fragments.append(.init(
                    icon: "circle.dotted",
                    text: "\(total) habits pending",
                    pillar: "mind"
                ))
            }
        }

        // Build headline from the strongest signals
        let headline = buildHeadline(
            positive: positiveSignals,
            concern: concernSignals,
            steps: stepsVal,
            spend: todaySpend,
            homeCooked: homeCooked,
            delivered: delivered,
            hasWorkoutStreak: workoutStats.streak > 0
        )

        let tone: TodayPulse.Tone
        if positiveSignals > concernSignals && positiveSignals >= 2 {
            tone = .positive
        } else if concernSignals > positiveSignals && concernSignals >= 2 {
            tone = .needsAttention
        } else {
            tone = .neutral
        }

        let icon: String
        switch tone {
        case .positive:       icon = "sparkles"
        case .neutral:        icon = "circle.dashed"
        case .needsAttention: icon = "lightbulb"
        case .warmingUp:      icon = "sparkle.magnifyingglass"
        }

        let detail: String?
        if fragments.count > 2 {
            detail = fragments.prefix(3).map { $0.text }.joined(separator: " · ")
        } else if !fragments.isEmpty {
            detail = fragments.map { $0.text }.joined(separator: " · ")
        } else {
            detail = nil
        }

        return TodayPulse(
            headline: headline,
            detail: detail,
            icon: icon,
            tone: tone,
            fragments: fragments
        )
    }

    // MARK: - Headline Builder

    private func buildHeadline(
        positive: Int,
        concern: Int,
        steps: Int,
        spend: Double,
        homeCooked: Int,
        delivered: Int,
        hasWorkoutStreak: Bool
    ) -> String {
        // Observation, not judgment — follows the guilt-free framing research.
        // No "you're overspending" or "you're not exercising enough".

        if positive >= 3 {
            return "Strong day across the board."
        }

        if hasWorkoutStreak && homeCooked > 0 {
            return "Active day, cooked at home."
        }

        if steps >= 10_000 && spend == 0 {
            return "Walked a lot, spent nothing."
        }

        if steps >= 10_000 {
            return "Active day so far."
        }

        if homeCooked > 0 && delivered == 0 {
            return "Home-cooked kind of day."
        }

        if delivered > 0 && spend > 50 {
            return "Order-in day."
        }

        if spend == 0 && steps > 0 {
            return "Quiet spending day."
        }

        if positive >= 1 {
            return "Decent day so far."
        }

        if concern >= 2 {
            return "Take care of yourself today."
        }

        return "Your day, still unfolding."
    }
}
