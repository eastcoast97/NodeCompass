import Foundation

/// Smart contextual nudges — proactive, time-aware suggestions.
/// "You usually work out on Tuesdays", "80% of budget used with 10 days left"
/// Different from insights (reactive observations) — nudges are forward-looking.
actor NudgeEngine {
    static let shared = NudgeEngine()

    private let storeKey = "nudge_history"
    private var history: [NudgeRecord] = []

    struct Nudge: Identifiable {
        let id = UUID().uuidString
        let type: NudgeType
        let title: String
        let body: String
        let icon: String
        let color: String           // "teal", "pink", "food", "blue"
        let priority: Int            // 0-3
        let actionLabel: String?
    }

    enum NudgeType: String, Codable {
        case workoutReminder         // "You usually work out on Tuesdays"
        case budgetWarning           // "80% of budget used, 10 days left"
        case sleepReminder           // "Bedtime in 30 min based on your pattern"
        case mealReminder            // "No lunch logged yet — it's 2pm"
        case stepsPush               // "3,200 steps to hit your goal — a 25-min walk"
        case savingsCheck            // "On track to save $X this month"
        case streakProtect           // "Don't break your 5-day workout streak!"
        case weeklyReview            // "Your weekly digest is ready"
        case goalNearby              // "200 steps from your daily goal!"
        case spendingPace            // "Spending is 20% above pace for the month"
    }

    private struct NudgeRecord: Codable {
        let type: String
        let date: Date
    }

    private init() {
        loadHistory()
    }

    // MARK: - Generate Nudges

    /// Generate contextual nudges for right now. Returns 0-3 most relevant.
    func generateNudges() async -> [Nudge] {
        var nudges: [Nudge] = []
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let weekday = cal.component(.weekday, from: Date()) // 1=Sun, 2=Mon...
        let dayOfMonth = cal.component(.day, from: Date())
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30
        let daysLeft = daysInMonth - dayOfMonth

        let health = HealthCollector.shared
        let steps = await health.todaySteps()
        let workoutStats = await health.recentWorkoutStats()

        let goals = await GoalStore.shared.allGoals()
        let profile = await UserProfileStore.shared.currentProfile()

        let monthlySpend = await MainActor.run { TransactionStore.shared.totalSpendThisMonth }
        let monthlyIncome = await MainActor.run { TransactionStore.shared.totalIncomeThisMonth }

        // 1. Budget Warning (priority 2) takes precedence over Spending Pace
        // (priority 1) — previously both could fire and consume 2 of 3 slots
        // for essentially the same message. Now only one ever shows.
        let budgetGoal = goals.first { $0.type == .spending }
        let budget = budgetGoal?.targetValue ?? (monthlyIncome > 0 ? monthlyIncome * Config.Spending.defaultBudgetIncomeRatio : 0)
        var emittedBudgetNudge = false
        if budget > 0 {
            let pctUsed = monthlySpend / budget
            if pctUsed >= 0.8 && daysLeft >= 5 && !recentlyNudged(.budgetWarning) {
                nudges.append(Nudge(
                    type: .budgetWarning,
                    title: "Budget Check",
                    body: "\(Int(pctUsed * 100))% of your monthly budget used with \(daysLeft) days left. \(NC.money(budget - monthlySpend)) remaining.",
                    icon: "exclamationmark.triangle.fill",
                    color: "spend",
                    priority: 2,
                    actionLabel: nil
                ))
                emittedBudgetNudge = true
            }

            // Spending pace — only fires if Budget Warning didn't already fire
            // for the same underlying issue.
            if !emittedBudgetNudge {
                let expectedPct = Double(dayOfMonth) / Double(daysInMonth)
                if pctUsed > expectedPct * 1.2 && pctUsed < 0.8 && !recentlyNudged(.spendingPace) {
                    let overBy = Int((pctUsed - expectedPct) * 100)
                    nudges.append(Nudge(
                        type: .spendingPace,
                        title: "Spending Pace",
                        body: "You're \(overBy)% ahead of your monthly pace. Slowing down could save \(NC.money((pctUsed - expectedPct) * budget)).",
                        icon: "speedometer",
                        color: "warning",
                        priority: 1,
                        actionLabel: nil
                    ))
                }
            }
        }

        // 2. Savings Check (mid-month, once)
        if dayOfMonth >= 14 && dayOfMonth <= 16 && monthlyIncome > 0 && !recentlyNudged(.savingsCheck, hours: 72) {
            let projected = monthlyIncome - (monthlySpend / Double(dayOfMonth) * Double(daysInMonth))
            if projected > 0 {
                nudges.append(Nudge(
                    type: .savingsCheck,
                    title: "Savings Projection",
                    body: "At this pace, you'll save \(NC.money(projected)) this month.",
                    icon: "banknote.fill",
                    color: "teal",
                    priority: 1,
                    actionLabel: nil
                ))
            }
        }

        // 3. Workout Reminder (if user typically works out on this weekday)
        if hour >= 7 && hour <= 10 {
            let workoutDays = profile.workoutFrequency?.preferredDays ?? []
            if workoutDays.contains(weekday) && workoutStats.streak == 0 && !recentlyNudged(.workoutReminder) {
                let dayName = Calendar.current.weekdaySymbols[weekday - 1]
                nudges.append(Nudge(
                    type: .workoutReminder,
                    title: "Workout Day",
                    body: "You usually work out on \(dayName)s. Keep the pattern going!",
                    icon: "figure.run",
                    color: "pink",
                    priority: 1,
                    actionLabel: nil
                ))
            }
        }

        // 4. Streak Protection
        let activeStreaks = await AchievementEngine.shared.activeStreaks()
        for streak in activeStreaks where streak.currentDays >= 3 {
            if streak.type == .workout && workoutStats.streak == 0 && hour >= 16 && !recentlyNudged(.streakProtect) {
                nudges.append(Nudge(
                    type: .streakProtect,
                    title: "Protect Your Streak!",
                    body: "Don't break your \(streak.currentDays)-day workout streak! Even a short session counts.",
                    icon: "flame.fill",
                    color: "food",
                    priority: 2,
                    actionLabel: nil
                ))
            }
        }

        // 5. Steps Push (afternoon/evening, close to goal)
        let stepGoal = goals.first { $0.type == .steps }?.targetValue ?? 8000
        let stepsRemaining = Int(stepGoal) - steps
        if hour >= 15 && stepsRemaining > 0 && stepsRemaining <= 3000 && !recentlyNudged(.goalNearby) {
            let walkMinutes = stepsRemaining / 120 // ~120 steps/min
            nudges.append(Nudge(
                type: .goalNearby,
                title: "Almost There!",
                body: "\(stepsRemaining.formatted()) steps to hit your goal — about a \(walkMinutes)-min walk.",
                icon: "shoeprints.fill",
                color: "pink",
                priority: 1,
                actionLabel: nil
            ))
        } else if hour >= 12 && Double(steps) < stepGoal * 0.3 && !recentlyNudged(.stepsPush) {
            nudges.append(Nudge(
                type: .stepsPush,
                title: "Step It Up",
                body: "Only \(steps.formatted()) steps so far today. A walk could boost your score.",
                icon: "shoeprints.fill",
                color: "pink",
                priority: 0,
                actionLabel: nil
            ))
        }

        // 6. Meal Reminder (lunchtime, no food logged)
        if hour >= 13 && hour <= 15 {
            let todayFood = await FoodStore.shared.entriesForToday()
            let lunchLogged = todayFood.contains { entry in
                let h = cal.component(.hour, from: entry.timestamp)
                return h >= 11 && h <= 15
            }
            if !lunchLogged && !recentlyNudged(.mealReminder) {
                nudges.append(Nudge(
                    type: .mealReminder,
                    title: "Log Your Lunch",
                    body: "No lunch logged yet. Quick-log to keep your streak going!",
                    icon: "fork.knife",
                    color: "food",
                    priority: 0,
                    actionLabel: "Log Food"
                ))
            }
        }

        // 7. Weekly Review (Sunday afternoon)
        if weekday == 1 && hour >= 15 && !recentlyNudged(.weeklyReview, hours: 72) {
            nudges.append(Nudge(
                type: .weeklyReview,
                title: "Weekly Digest Ready",
                body: "Your week in review is ready. See how you did across all pillars.",
                icon: "doc.text.fill",
                color: "teal",
                priority: 1,
                actionLabel: "View Digest"
            ))
        }

        // Gate on AppLearningStage: early-stage users get fewer (or zero)
        // nudges to avoid day-1 overwhelm. Stage progresses as data matures.
        let stage = await AppLearningStage.shared.currentStage
        guard stage.allowsNudges else { return [] }
        let maxSlots = stage.maxNudges

        // Record shown nudges and return top N for this stage
        let sorted = nudges.sorted { $0.priority > $1.priority }
        let top = Array(sorted.prefix(maxSlots))
        for nudge in top {
            history.append(NudgeRecord(type: nudge.type.rawValue, date: Date()))
        }
        saveHistory()

        return top
    }

    // MARK: - Rate Limiting

    private func recentlyNudged(_ type: NudgeType, hours: Int = 12) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -hours, to: Date())!
        return history.contains { $0.type == type.rawValue && $0.date > cutoff }
    }

    // MARK: - Persistence

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([NudgeRecord].self, from: data) else { return }
        // Keep last 7 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        history = decoded.filter { $0.date > cutoff }
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
