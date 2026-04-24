import Foundation

/// Curated library of pre-defined challenges the user can start with one tap.
///
/// The catalog replaces the old "empty state — manually pick a type and
/// target" flow with a discoverable menu across four pillars. Each entry
/// includes a motivational subtitle and an optional link into
/// `AchievementEngine.AchievementType` so completion unlocks a matching badge.
///
/// Currency amounts are stored as raw `Double` — the UI renders them with
/// `NC.currencySymbol` at display time, so the same catalog works for ₹ / $ /
/// € users without duplication.
enum ChallengeCatalog {

    struct Entry: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let pillar: ChallengeStore.Pillar
        let difficulty: ChallengeStore.Difficulty
        let type: ChallengeStore.ChallengeType
        let targetValue: Double
        let durationDays: Int
        let unlockAchievement: AchievementEngine.AchievementType?
    }

    // MARK: - Entries

    static let entries: [Entry] = [

        // ──────────────── WEALTH ────────────────
        Entry(
            id: "wealth.no-delivery-7",
            title: "No delivery for 7 days",
            subtitle: "Save ~\(NC.currencySymbol)1,500 on avg",
            pillar: .wealth, difficulty: .easy,
            type: .noEatingOut, targetValue: 7, durationDays: 7,
            unlockAchievement: .cookingStreak7
        ),
        Entry(
            id: "wealth.cook-5-days",
            title: "Cook 5 days this week",
            subtitle: "Small habit, real savings",
            pillar: .wealth, difficulty: .easy,
            type: .homeCooking, targetValue: 5, durationDays: 7,
            unlockAchievement: .cookingStreak3
        ),
        Entry(
            id: "wealth.under-500-daily",
            title: "Under 500/day for 7 days",
            subtitle: "Stay tight on weekday spend",
            pillar: .wealth, difficulty: .medium,
            type: .dailySpendLimit, targetValue: 500, durationDays: 7,
            unlockAchievement: .budgetStreak7
        ),
        Entry(
            id: "wealth.cancel-subscription",
            title: "Cancel a ghost subscription",
            subtitle: "We detected some you may have forgotten",
            pillar: .wealth, difficulty: .medium,
            type: .savingsTarget, targetValue: 1, durationDays: 30,
            unlockAchievement: .firstSavings
        ),
        Entry(
            id: "wealth.no-impulse",
            title: "No impulse buys for a week",
            subtitle: "Skip purchases under 200 this week",
            pillar: .wealth, difficulty: .medium,
            type: .dailySpendLimit, targetValue: 200, durationDays: 7,
            unlockAchievement: .budgetStreak7
        ),
        Entry(
            id: "wealth.save-5k-month",
            title: "Save 5,000 this month",
            subtitle: "Income minus spend, at month end",
            pillar: .wealth, difficulty: .hard,
            type: .savingsTarget, targetValue: 5000, durationDays: 30,
            unlockAchievement: .savingsGoal
        ),
        Entry(
            id: "wealth.budget-month",
            title: "30 days under budget",
            subtitle: "Marathon consistency",
            pillar: .wealth, difficulty: .hard,
            type: .dailySpendLimit, targetValue: 1000, durationDays: 30,
            unlockAchievement: .budgetStreak30
        ),

        // ──────────────── HEALTH ────────────────
        Entry(
            id: "health.steps-10k-5",
            title: "10K steps × 5 days",
            subtitle: "Move more without changing anything else",
            pillar: .health, difficulty: .easy,
            type: .stepGoal, targetValue: 5, durationDays: 7,
            unlockAchievement: .steps10KStreak7
        ),
        Entry(
            id: "health.sleep-5-nights",
            title: "Sleep before 11pm × 5 nights",
            subtitle: "Early sleep, better everything",
            pillar: .health, difficulty: .easy,
            type: .habitStreak, targetValue: 5, durationDays: 7,
            unlockAchievement: .sleepChamp
        ),
        Entry(
            id: "health.3-workouts",
            title: "3 workouts this week",
            subtitle: "Any type counts — strength, cardio, yoga",
            pillar: .health, difficulty: .medium,
            type: .workoutStreak, targetValue: 3, durationDays: 7,
            unlockAchievement: .workoutStreak3
        ),
        Entry(
            id: "health.outdoor-7",
            title: "30 min outdoor daily",
            subtitle: "Sun, park, walk — pick your poison",
            pillar: .health, difficulty: .medium,
            type: .habitStreak, targetValue: 7, durationDays: 7,
            unlockAchievement: .explorer
        ),
        Entry(
            id: "health.workout-streak-7",
            title: "7-day workout streak",
            subtitle: "Daily movement, no skip days",
            pillar: .health, difficulty: .hard,
            type: .workoutStreak, targetValue: 7, durationDays: 7,
            unlockAchievement: .workoutStreak7
        ),

        // ──────────────── MIND ────────────────
        Entry(
            id: "mind.mood-7-days",
            title: "Log mood every day × 7 days",
            subtitle: "Build emotional self-awareness",
            pillar: .mind, difficulty: .easy,
            type: .habitStreak, targetValue: 7, durationDays: 7,
            unlockAchievement: .weekStreak
        ),
        Entry(
            id: "mind.journal-7",
            title: "Journal 7 days",
            subtitle: "Two lines a day — that's it",
            pillar: .mind, difficulty: .easy,
            type: .habitStreak, targetValue: 7, durationDays: 7,
            unlockAchievement: .weekStreak
        ),
        Entry(
            id: "mind.screen-under-3h",
            title: "Screen time under 3h × 5 days",
            subtitle: "Reclaim evening hours",
            pillar: .mind, difficulty: .medium,
            type: .habitStreak, targetValue: 5, durationDays: 7,
            unlockAchievement: nil
        ),
        Entry(
            id: "mind.no-social-day",
            title: "No social media for a day",
            subtitle: "Quick reset — try just 24 hours",
            pillar: .mind, difficulty: .medium,
            type: .habitStreak, targetValue: 1, durationDays: 1,
            unlockAchievement: nil
        ),
        Entry(
            id: "mind.read-20-min",
            title: "Read 20 min × 5 days",
            subtitle: "Book, article, long-form — not reels",
            pillar: .mind, difficulty: .medium,
            type: .habitStreak, targetValue: 5, durationDays: 7,
            unlockAchievement: nil
        ),
        Entry(
            id: "mind.detox-weekend",
            title: "3-day digital detox weekend",
            subtitle: "Fri-Sat-Sun on airplane mode",
            pillar: .mind, difficulty: .hard,
            type: .habitStreak, targetValue: 3, durationDays: 7,
            unlockAchievement: nil
        ),

        // ──────────────── CROSS-PILLAR ────────────────
        Entry(
            id: "cross.gym-saver",
            title: "Gym visit = 200 saved elsewhere",
            subtitle: "Every workout matched with real savings",
            pillar: .cross, difficulty: .easy,
            type: .workoutStreak, targetValue: 3, durationDays: 14,
            unlockAchievement: .gymSaver
        ),
        Entry(
            id: "cross.walk-not-deliver",
            title: "Walk to cafe × 3, not delivery",
            subtitle: "Pair the coffee craving with a walk",
            pillar: .cross, difficulty: .medium,
            type: .homeCooking, targetValue: 3, durationDays: 14,
            unlockAchievement: .walkNotDeliver
        ),
        Entry(
            id: "cross.park-over-restaurant",
            title: "Park visit > new restaurant × 2",
            subtitle: "Weekend outdoors, not on a reservation list",
            pillar: .cross, difficulty: .medium,
            type: .habitStreak, targetValue: 2, durationDays: 14,
            unlockAchievement: .parkOverRestaurant
        ),
        Entry(
            id: "cross.mood-on-workout",
            title: "Mood up on workout days",
            subtitle: "Prove to yourself movement helps",
            pillar: .cross, difficulty: .hard,
            type: .workoutStreak, targetValue: 5, durationDays: 14,
            unlockAchievement: .moodOnWorkoutDay
        ),
        Entry(
            id: "cross.cook-and-walk",
            title: "Cook + walk combo × 5 days",
            subtitle: "Home-cooked meal AND 8K+ steps same day",
            pillar: .cross, difficulty: .hard,
            type: .homeCooking, targetValue: 5, durationDays: 14,
            unlockAchievement: .cookAndWalk
        ),
    ]

    // MARK: - Queries

    /// All entries for a given pillar. Preserves declaration order (difficulty
    /// ascends easy → hard within each pillar section above).
    static func forPillar(_ pillar: ChallengeStore.Pillar) -> [Entry] {
        entries.filter { $0.pillar == pillar }
    }

    /// Look up a catalog entry by its stable ID.
    static func entry(id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// All entries, filtered by difficulty.
    static func forDifficulty(_ difficulty: ChallengeStore.Difficulty) -> [Entry] {
        entries.filter { $0.difficulty == difficulty }
    }
}
