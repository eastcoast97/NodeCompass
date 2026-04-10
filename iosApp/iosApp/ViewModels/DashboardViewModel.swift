import SwiftUI

/// ViewModel for the unified Dashboard.
/// Loads data for all 4 dashboard pages: Wealth, Health, Insights, Orders.
@MainActor
class DashboardViewModel: ObservableObject {
    // Wealth
    @Published var totalSpend: Double = 0
    @Published var totalIncome: Double = 0
    @Published var primaryCurrencySymbol: String = "$"
    @Published var categoryBreakdown: [CategorySpend] = []
    @Published var recentTransactions: [TransactionItem] = []
    @Published var ghostSubscriptions: [GhostSubscriptionItem] = []

    // Health
    @Published var dailySteps: Int = 0
    @Published var workoutStreak: Int = 0
    @Published var sleepHours: Double = 0
    @Published var restingHR: Int = 0
    @Published var workoutsPerWeek: Double = 0
    @Published var dominantWorkout: String = ""
    @Published var activeCalories: Int = 0

    // Insights
    @Published var insights: [Insight] = []

    // Food
    @Published var todayMealCount: Int = 0
    @Published var todayCalories: Int = 0
    @Published var todayMacros: Macros = .zero
    @Published var homeCookingStreak: Int = 0
    @Published var todayFoodEntries: [FoodStore.FoodLogEntry] = []
    @Published var pendingFoodLogs: [FoodStore.FoodLogEntry] = []
    @Published var stapleFoods: [StapleFood] = []
    @Published var foodInsights: [Insight] = []

    // Orders
    @Published var emailSyncConnected: Bool = false  // true if any Gmail account connected
    @Published var emailReceiptsCount: Int = 0
    @Published var recentOrders: [TransactionItem] = []

    // Life Score & Goals
    @Published var lifeScore: LifeScoreEngine.DailyScore?
    @Published var goalProgress: [GoalProgress] = []

    @Published var isEmpty: Bool = true

    private let store = TransactionStore.shared

    func load() {
        let transactions = store.transactions

        // Load async data (insights, health profile, food)
        Task {
            let allInsights = await PatternEngine.shared.activeInsights()
            insights = allInsights
            foodInsights = allInsights.filter { $0.category == "food" }

            // Live health data — query HealthKit directly for real-time numbers
            let health = HealthCollector.shared
            async let liveSteps = health.todaySteps()
            async let liveCals = health.todayActiveCalories()
            async let liveSleep = health.lastNightSleepHours()
            async let liveHR = health.todayRestingHeartRate()
            async let liveWorkouts = health.recentWorkoutStats()

            dailySteps = await liveSteps
            activeCalories = await liveCals
            sleepHours = await liveSleep
            restingHR = await liveHR

            let workoutStats = await liveWorkouts
            workoutStreak = workoutStats.streak
            workoutsPerWeek = workoutStats.perWeek
            dominantWorkout = workoutStats.dominant

            // Food data
            todayFoodEntries = await FoodStore.shared.entriesForToday()
            todayMealCount = todayFoodEntries.filter { !$0.items.isEmpty }.count
            todayCalories = await FoodStore.shared.todayCalories
            todayMacros = todayFoodEntries.compactMap { $0.totalMacros }.reduce(Macros.zero, +)
            pendingFoodLogs = await FoodStore.shared.pendingEntries()
            stapleFoods = await FoodStore.shared.detectStapleFoods()

            // Compute home cooking streak from food insights
            if let streakInsight = allInsights.first(where: { $0.type == .mealStreak && $0.title.contains("cooking streak") }) {
                // Extract number from title like "5-day home cooking streak!"
                let digits = streakInsight.title.prefix(while: { $0.isNumber })
                homeCookingStreak = Int(digits) ?? 0
            }

            // Life Score & Goals
            lifeScore = await LifeScoreEngine.shared.calculateToday()
            goalProgress = await GoalStore.shared.progressForAll()
        }

        // Orders (email source — aggregated across all Gmail accounts)
        emailSyncConnected = !GmailService.shared.connectedEmails.isEmpty
        let emailTxns = transactions.filter { $0.source == "EMAIL" }
        emailReceiptsCount = emailTxns.count
        recentOrders = emailTxns.sorted { $0.date > $1.date }.prefix(10).map { txn in
            TransactionItem(
                id: txn.id, merchant: txn.merchant, amount: txn.amount,
                currencySymbol: txn.currencySymbol, category: txn.category,
                date: txn.formattedDate, source: txn.source, isCredit: txn.isCredit
            )
        }

        guard !transactions.isEmpty else {
            isEmpty = true
            totalSpend = 0; totalIncome = 0
            categoryBreakdown = []; recentTransactions = []; ghostSubscriptions = []
            return
        }

        isEmpty = false

        let currencyCount = Dictionary(grouping: transactions, by: { $0.currencySymbol })
        primaryCurrencySymbol = currencyCount.max(by: { $0.value.count < $1.value.count })?.key ?? Locale.current.currencySymbol ?? "$"
        // Persist for global access (goals, score, etc.)
        UserDefaults.standard.set(primaryCurrencySymbol, forKey: "primaryCurrencySymbol")

        totalSpend = store.totalSpendThisMonth
        totalIncome = store.totalIncomeThisMonth

        categoryBreakdown = store.categoryBreakdown.map { item in
            CategorySpend(categoryName: item.category, amount: item.amount, currencySymbol: primaryCurrencySymbol)
        }

        recentTransactions = store.recentTransactions.map { txn in
            TransactionItem(
                id: txn.id, merchant: txn.merchant, amount: txn.amount,
                currencySymbol: txn.currencySymbol, category: txn.category,
                date: txn.formattedDate, source: txn.source, isCredit: txn.isCredit
            )
        }

        ghostSubscriptions = store.ghostSubscriptions.map { ghost in
            GhostSubscriptionItem(
                id: "\(ghost.merchant)_\(ghost.amount)", merchant: ghost.merchant,
                amount: ghost.amount, currencySymbol: ghost.currencySymbol,
                frequency: "Monthly", occurrences: ghost.occurrences
            )
        }
    }

    func dismissInsight(_ insight: Insight) {
        Task {
            await PatternEngine.shared.dismiss(insight.id)
            insights.removeAll { $0.id == insight.id }
        }
    }
}

// MARK: - Display Models

struct CategorySpend: Identifiable {
    let id = UUID()
    let categoryName: String
    let amount: Double
    let currencySymbol: String

    var color: Color { NC.color(for: categoryName) }
    var formattedAmount: String { "\(currencySymbol)\(String(format: "%.2f", amount))" }
}

struct TransactionItem: Identifiable {
    let id: String
    let merchant: String
    let amount: Double
    let currencySymbol: String
    let category: String
    let date: String
    let source: String
    let isCredit: Bool

    var formattedAmount: String {
        let prefix = isCredit ? "+" : "-"
        return "\(prefix)\(currencySymbol)\(String(format: "%.2f", amount))"
    }
}

struct GhostSubscriptionItem: Identifiable {
    let id: String
    let merchant: String
    let amount: Double
    let currencySymbol: String
    let frequency: String
    let occurrences: Int

    var formattedAmount: String { "\(currencySymbol)\(String(format: "%.2f", amount))/mo" }
}
