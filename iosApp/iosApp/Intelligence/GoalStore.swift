import Foundation

/// Types of goals users can set — each auto-tracked from existing data.
enum GoalType: String, Codable, CaseIterable {
    case spending       // "Spend less than X/month"
    case steps          // "Walk X steps/day"
    case sleep          // "Sleep X hours/night"
    case workout        // "Work out X times/week"
    case calories       // "Burn X active calories/day"
    case homeCooking    // "Cook at home X times/week"
    case eatingOut      // "Eat out less than X times/week"
    case savings        // "Save X/month"

    var title: String {
        switch self {
        case .spending: return "Monthly Budget"
        case .steps: return "Daily Steps"
        case .sleep: return "Sleep Goal"
        case .workout: return "Weekly Workouts"
        case .calories: return "Active Calories"
        case .homeCooking: return "Home Cooking"
        case .eatingOut: return "Eating Out Limit"
        case .savings: return "Monthly Savings"
        }
    }

    var icon: String {
        switch self {
        case .spending: return NC.currencyIconCircle
        case .steps: return "shoeprints.fill"
        case .sleep: return "moon.zzz.fill"
        case .workout: return "figure.run"
        case .calories: return "bolt.fill"
        case .homeCooking: return "frying.pan.fill"
        case .eatingOut: return "fork.knife"
        case .savings: return "banknote.fill"
        }
    }

    var unit: String {
        switch self {
        case .spending: return "/month"
        case .steps: return "steps/day"
        case .sleep: return "hrs/night"
        case .workout: return "times/week"
        case .calories: return "kcal/day"
        case .homeCooking: return "times/week"
        case .eatingOut: return "times/week"
        case .savings: return "/month"
        }
    }

    var defaultValue: Double {
        let isUSD = NC.currencySymbol == "$"
        switch self {
        case .spending: return isUSD ? 3000 : 30000
        case .steps: return 8000
        case .sleep: return 7.5
        case .workout: return 4
        case .calories: return 400
        case .homeCooking: return 5
        case .eatingOut: return 3
        case .savings: return isUSD ? 1000 : 10000
        }
    }

    /// Presets for quick selection (currency-aware for money goals)
    var presets: [Double] {
        let isUSD = NC.currencySymbol == "$"
        switch self {
        case .spending: return isUSD ? [1500, 2000, 3000, 5000] : [15000, 20000, 30000, 50000]
        case .steps: return [5000, 8000, 10000, 12000]
        case .sleep: return [6.5, 7, 7.5, 8]
        case .workout: return [2, 3, 4, 5]
        case .calories: return [200, 300, 400, 500]
        case .homeCooking: return [3, 4, 5, 7]
        case .eatingOut: return [2, 3, 5, 7]
        case .savings: return isUSD ? [500, 1000, 2000, 3000] : [5000, 10000, 20000, 30000]
        }
    }

    /// Whether lower actual value is better (spending, eating out)
    var lowerIsBetter: Bool {
        switch self {
        case .spending, .eatingOut: return true
        default: return false
        }
    }

    var pillar: String {
        switch self {
        case .spending, .savings: return "wealth"
        case .steps, .sleep, .workout, .calories: return "health"
        case .homeCooking, .eatingOut: return "food"
        }
    }
}

/// A user-defined goal with auto-tracked progress.
struct Goal: Codable, Identifiable {
    let id: String
    let type: GoalType
    var targetValue: Double
    var isActive: Bool
    let createdAt: Date

    var formattedTarget: String {
        switch type {
        case .spending, .savings:
            return NC.money(targetValue)
        case .sleep:
            return String(format: "%.1f hrs", targetValue)
        case .steps:
            return "\(Int(targetValue).formatted()) steps"
        case .calories:
            return "\(Int(targetValue)) kcal"
        default:
            return "\(Int(targetValue))x"
        }
    }
}

/// Computed progress for a goal.
struct GoalProgress: Identifiable {
    var id: String { goal.id }
    let goal: Goal
    let currentValue: Double
    let progress: Double       // 0.0 to 1.0+
    let isOnTrack: Bool
    let streakDays: Int
    let statusText: String
}

/// Persistent store for user goals with auto-progress calculation.
actor GoalStore {
    static let shared = GoalStore()

    private let storeKey = "user_goals"
    private var goals: [Goal] = []

    private init() {
        goals = loadGoals()
    }

    // MARK: - CRUD

    func allGoals() -> [Goal] {
        goals.filter { $0.isActive }
    }

    func addGoal(type: GoalType, target: Double) {
        // Remove existing goal of same type
        goals.removeAll { $0.type == type }
        let goal = Goal(
            id: UUID().uuidString,
            type: type,
            targetValue: target,
            isActive: true,
            createdAt: Date()
        )
        goals.append(goal)
        saveGoals()
    }

    func updateTarget(goalId: String, newTarget: Double) {
        guard let idx = goals.firstIndex(where: { $0.id == goalId }) else { return }
        goals[idx].targetValue = newTarget
        saveGoals()
    }

    func removeGoal(goalId: String) {
        goals.removeAll { $0.id == goalId }
        saveGoals()
    }

    // MARK: - Progress Calculation

    func progressForAll() async -> [GoalProgress] {
        var results: [GoalProgress] = []
        for goal in goals where goal.isActive {
            let progress = await calculateProgress(for: goal)
            results.append(progress)
        }
        return results
    }

    @MainActor
    private func calculateProgress(for goal: Goal) async -> GoalProgress {
        let store = TransactionStore.shared
        let cal = Calendar.current

        switch goal.type {
        case .spending:
            let spent = store.totalSpendThisMonth
            let progress = goal.targetValue > 0 ? spent / goal.targetValue : 0
            let daysInMonth = Double(cal.range(of: .day, in: .month, for: Date())?.count ?? 30)
            let dayOfMonth = Double(cal.component(.day, from: Date()))
            let expectedPct = dayOfMonth / daysInMonth
            let isOnTrack = progress <= expectedPct * 1.1 // 10% tolerance
            return GoalProgress(
                goal: goal,
                currentValue: spent,
                progress: min(progress, 1.5),
                isOnTrack: isOnTrack,
                streakDays: 0,
                statusText: isOnTrack ? "On track" : "Over pace"
            )

        case .savings:
            let income = store.totalIncomeThisMonth
            let spent = store.totalSpendThisMonth
            let saved = max(0, income - spent)
            let progress = goal.targetValue > 0 ? saved / goal.targetValue : 0
            return GoalProgress(
                goal: goal,
                currentValue: saved,
                progress: min(progress, 1.5),
                isOnTrack: progress >= 0.5,
                streakDays: 0,
                statusText: saved >= goal.targetValue ? "Goal met!" : "\(NC.money(goal.targetValue - saved)) to go"
            )

        case .steps:
            let steps = await HealthCollector.shared.todaySteps()
            let progress = goal.targetValue > 0 ? Double(steps) / goal.targetValue : 0
            return GoalProgress(
                goal: goal,
                currentValue: Double(steps),
                progress: min(progress, 1.5),
                isOnTrack: progress >= 0.5, // At least half by now
                streakDays: 0,
                statusText: steps >= Int(goal.targetValue) ? "Goal hit!" : "\(Int(goal.targetValue) - steps) to go"
            )

        case .sleep:
            let sleep = await HealthCollector.shared.lastNightSleepHours()
            let progress = goal.targetValue > 0 ? sleep / goal.targetValue : 0
            return GoalProgress(
                goal: goal,
                currentValue: sleep,
                progress: min(progress, 1.5),
                isOnTrack: sleep >= goal.targetValue * 0.9,
                streakDays: 0,
                statusText: sleep >= goal.targetValue ? "Well rested" : String(format: "%.1f hrs short", goal.targetValue - sleep)
            )

        case .workout:
            let stats = await HealthCollector.shared.recentWorkoutStats()
            let progress = goal.targetValue > 0 ? stats.perWeek / goal.targetValue : 0
            return GoalProgress(
                goal: goal,
                currentValue: stats.perWeek,
                progress: min(progress, 1.5),
                isOnTrack: stats.perWeek >= goal.targetValue * 0.8,
                streakDays: stats.streak,
                statusText: stats.perWeek >= goal.targetValue ? "On pace" : "\(Int(goal.targetValue - stats.perWeek)) more this week"
            )

        case .calories:
            let cals = await HealthCollector.shared.todayActiveCalories()
            let progress = goal.targetValue > 0 ? Double(cals) / goal.targetValue : 0
            return GoalProgress(
                goal: goal,
                currentValue: Double(cals),
                progress: min(progress, 1.5),
                isOnTrack: progress >= 0.4,
                streakDays: 0,
                statusText: cals >= Int(goal.targetValue) ? "Target hit!" : "\(Int(goal.targetValue) - cals) kcal to go"
            )

        case .homeCooking:
            let weekEntries = await FoodStore.shared.entriesForWeek()
            let homeMeals = weekEntries.filter { !$0.items.isEmpty && $0.source != .emailOrder }.count
            let progress = goal.targetValue > 0 ? Double(homeMeals) / goal.targetValue : 0
            return GoalProgress(
                goal: goal,
                currentValue: Double(homeMeals),
                progress: min(progress, 1.5),
                isOnTrack: progress >= 0.5,
                streakDays: 0,
                statusText: homeMeals >= Int(goal.targetValue) ? "Goal met!" : "\(Int(goal.targetValue) - homeMeals) more meals"
            )

        case .eatingOut:
            // Case-insensitive category matching against a configurable list
            // to survive category rename drift (previously broke if categories
            // were capitalized differently).
            let foodCategories: Set<String> = ["food & dining", "restaurants", "food", "fast food", "dining"]
            let weekTxns = store.transactions.filter { txn in
                cal.isDate(txn.date, equalTo: Date(), toGranularity: .weekOfYear) &&
                foodCategories.contains(txn.category.lowercased()) &&
                txn.type.uppercased() == "DEBIT"
            }.count
            let progress = goal.targetValue > 0 ? Double(weekTxns) / goal.targetValue : 0
            let isOnTrack = Double(weekTxns) <= goal.targetValue
            return GoalProgress(
                goal: goal,
                currentValue: Double(weekTxns),
                progress: min(progress, 1.5),
                isOnTrack: isOnTrack,
                streakDays: 0,
                statusText: isOnTrack ? "Under limit" : "\(weekTxns - Int(goal.targetValue)) over limit"
            )
        }
    }

    // MARK: - Persistence

    private func loadGoals() -> [Goal] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([Goal].self, from: data) else { return [] }
        return decoded
    }

    private func saveGoals() {
        if let data = try? JSONEncoder().encode(goals) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }
}
