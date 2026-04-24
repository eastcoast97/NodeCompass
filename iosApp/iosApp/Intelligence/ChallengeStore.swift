import Foundation

/// Manages user challenges — short-term goals that combine wealth and health data.
/// Challenges are time-bound with progress tracking and completion detection.
actor ChallengeStore {
    static let shared = ChallengeStore()

    private let storeKey = "user_challenges"
    private var challenges: [Challenge] = []

    // MARK: - Models

    /// A pillar tag for categorising challenges in the catalog. Uses String raw
    /// values so the "pillar" concept stays consistent with AchievementEngine,
    /// which already uses bare string pillars ("wealth", "health", etc.).
    enum Pillar: String, Codable, CaseIterable {
        case wealth, health, mind, cross

        var displayName: String {
            switch self {
            case .wealth: return "Wealth"
            case .health: return "Health"
            case .mind:   return "Mind"
            case .cross:  return "Cross-pillar"
            }
        }

        var icon: String {
            switch self {
            case .wealth: return "dollarsign.circle.fill"
            case .health: return "heart.fill"
            case .mind:   return "brain.head.profile"
            case .cross:  return "sparkles"
            }
        }
    }

    /// Difficulty tier for catalog entries. Used for surfaced hints only —
    /// does not affect progress tracking logic.
    enum Difficulty: String, Codable, CaseIterable {
        case easy, medium, hard

        var displayName: String {
            switch self {
            case .easy:   return "Easy"
            case .medium: return "Medium"
            case .hard:   return "Hard"
            }
        }
    }

    /// How a challenge is scoped.
    /// - `.solo` — tracked locally only, never syncs to Supabase
    /// - `.circle(String)` — shared with one of the user's circles; progress
    ///   syncs to `participant_scores` after every `updateProgress()` run.
    ///   The associated String is the `circle_challenges.id` (server-side UUID).
    ///
    /// Stored as a flat Codable struct so the Challenge model stays
    /// backward-compatible: a nil `circleChallengeId` means solo.
    struct Scope: Codable, Equatable {
        /// nil = solo, non-nil = circle-scoped (value is the server-side
        /// circle_challenges.id).
        let circleChallengeId: String?

        /// nil = solo, non-nil = the circle this challenge lives in. Stored
        /// alongside the challenge ID so we can route the Active card to the
        /// right Circle Detail view without an extra lookup.
        let circleId: String?

        static let solo = Scope(circleChallengeId: nil, circleId: nil)

        var isCircle: Bool { circleChallengeId != nil }
    }

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

        // --- Stage 1 additions (migration-safe via custom decoder below) ---

        /// Pillar tag for catalog filtering and UI accent colour.
        var pillar: Pillar
        /// Difficulty tier — shown as a chip on the catalog card.
        var difficulty: Difficulty
        /// Motivational one-liner shown under the title. Empty string for
        /// challenges migrated from pre-Stage-1 persistence.
        var subtitle: String
        /// Optional link into AchievementEngine. When a challenge with this
        /// field set completes, the corresponding badge is unlocked.
        var unlockAchievement: AchievementEngine.AchievementType?
        /// Catalog entry id the challenge was started from. Used to prevent
        /// duplicate concurrent instances of the same catalog entry.
        var catalogId: String?

        /// Solo (default) or circle-scoped. When circle-scoped, progress
        /// updates are uploaded to Supabase after each `updateProgress()` run.
        var scope: Scope

        enum CodingKeys: String, CodingKey {
            case id, title, type, targetValue, currentValue
            case startDate, endDate, isCompleted, completedAt
            case pillar, difficulty, subtitle, unlockAchievement, catalogId
            case scope
        }

        /// Custom decoder that tolerates pre-Stage-1 persistence by defaulting
        /// the new fields. Existing saved challenges decode cleanly; new fields
        /// simply land as sensible defaults.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            type = try c.decode(ChallengeType.self, forKey: .type)
            targetValue = try c.decode(Double.self, forKey: .targetValue)
            currentValue = try c.decode(Double.self, forKey: .currentValue)
            startDate = try c.decode(Date.self, forKey: .startDate)
            endDate = try c.decode(Date.self, forKey: .endDate)
            isCompleted = try c.decode(Bool.self, forKey: .isCompleted)
            completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
            pillar = try c.decodeIfPresent(Pillar.self, forKey: .pillar) ?? .wealth
            difficulty = try c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .easy
            subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
            unlockAchievement = try c.decodeIfPresent(AchievementEngine.AchievementType.self, forKey: .unlockAchievement)
            catalogId = try c.decodeIfPresent(String.self, forKey: .catalogId)
            // Stage 2.2+ field; pre-existing challenges default to solo.
            scope = try c.decodeIfPresent(Scope.self, forKey: .scope) ?? .solo
        }

        /// Memberwise init for code-created challenges. Keeps the old call
        /// sites compiling (catalogId / subtitle / etc. default to nil / "").
        init(
            id: String,
            title: String,
            type: ChallengeType,
            targetValue: Double,
            currentValue: Double,
            startDate: Date,
            endDate: Date,
            isCompleted: Bool,
            completedAt: Date?,
            pillar: Pillar = .wealth,
            difficulty: Difficulty = .easy,
            subtitle: String = "",
            unlockAchievement: AchievementEngine.AchievementType? = nil,
            catalogId: String? = nil,
            scope: Scope = .solo
        ) {
            self.id = id
            self.title = title
            self.type = type
            self.targetValue = targetValue
            self.currentValue = currentValue
            self.startDate = startDate
            self.endDate = endDate
            self.isCompleted = isCompleted
            self.completedAt = completedAt
            self.pillar = pillar
            self.difficulty = difficulty
            self.subtitle = subtitle
            self.unlockAchievement = unlockAchievement
            self.catalogId = catalogId
            self.scope = scope
        }
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
    /// Legacy entry point — used by NewChallengeSheet for custom challenges.
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

    /// Start a challenge from a `ChallengeCatalog.Entry`. Carries forward the
    /// catalog's pillar / difficulty / subtitle / unlockAchievement so the
    /// Active card can render richly and completion unlocks the right badge.
    ///
    /// No-op if the user already has an active (non-completed) challenge from
    /// the same catalog entry — prevents accidental duplicates when the user
    /// taps Start twice.
    @discardableResult
    func startFromCatalog(
        _ entry: ChallengeCatalog.Entry,
        scope: Scope = .solo
    ) -> Challenge? {
        let now = Date()
        // Only block duplicate catalog starts within the SAME scope. A user
        // can run a catalog entry solo AND share it to a circle at the same
        // time — those are distinct instances.
        let hasActive = challenges.contains { c in
            c.catalogId == entry.id && !c.isCompleted && c.endDate >= now
                && c.scope == scope
        }
        guard !hasActive else { return nil }

        let end = Calendar.current.date(byAdding: .day, value: entry.durationDays, to: now) ?? now
        let challenge = Challenge(
            id: UUID().uuidString,
            title: entry.title,
            type: entry.type,
            targetValue: entry.targetValue,
            currentValue: 0,
            startDate: now,
            endDate: end,
            isCompleted: false,
            completedAt: nil,
            pillar: entry.pillar,
            difficulty: entry.difficulty,
            subtitle: entry.subtitle,
            unlockAchievement: entry.unlockAchievement,
            catalogId: entry.id,
            scope: scope
        )
        challenges.append(challenge)
        saveToDisk()
        return challenge
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

                // Reward the user: unlock linked achievement (if any) and
                // surface a local notification via the shared NotificationEngine.
                // NotificationEngine enforces its own rate limits (3/day,
                // 12h per-type cooldown) so repeated completions on the same
                // day won't spam.
                await rewardCompletion(of: challenges[i])
            }

            // Also mark failed if past endDate and not completed
            // (we keep them as not-completed so they appear expired)
        }

        saveToDisk()

        // M2.2: for every active circle-scoped challenge, push the caller's
        // current value to Supabase so teammates see updated progress.
        // Fire-and-forget — failures (offline, session expired) just mean
        // the next updateProgress() run will try again.
        await syncCircleScoresToSupabase()
    }

    /// Upload current values for all active circle-scoped challenges via
    /// `CoopChallengeSync.uploadMyScore`. Only touches challenges whose
    /// `scope.circleChallengeId` is set. Called from the end of
    /// `updateProgress()`.
    private func syncCircleScoresToSupabase() async {
        for c in challenges {
            guard !c.isCompleted,
                  c.endDate >= Date(),
                  let remoteChallengeId = c.scope.circleChallengeId,
                  let uuid = UUID(uuidString: remoteChallengeId) else { continue }

            // Best-effort upload. Any failure is swallowed — the next run of
            // updateProgress (on foreground, transaction sync, background
            // task) will retry.
            try? await CoopChallengeSync.shared.uploadMyScore(
                challengeId: uuid,
                value: c.currentValue
            )
        }
    }

    /// Fire off the post-completion reward pipeline: achievement unlock +
    /// local push notification. Called once per challenge when it flips to
    /// `isCompleted == true`.
    private func rewardCompletion(of challenge: Challenge) async {
        // 1. Unlock linked achievement, if the catalog entry declared one.
        var unlockedTitle: String?
        if let achievementType = challenge.unlockAchievement {
            if let achievement = await AchievementEngine.shared.unlockFromChallenge(achievementType) {
                unlockedTitle = achievement.title
            }
        }

        // 2. Surface a local push notification, wrapped as an Insight so the
        //    existing NotificationEngine rate-limiting applies.
        let body: String
        if let badge = unlockedTitle {
            body = "Unlocked the '\(badge)' badge."
        } else {
            body = "You hit your target — nicely done."
        }
        let insight = Insight(
            type: .milestone,
            title: "🎉 Challenge complete: \(challenge.title)",
            body: body,
            priority: .medium,
            category: challenge.pillar.rawValue
        )
        await NotificationEngine.shared.scheduleIfAllowed(insight)
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
