import Foundation

/// Manages per-category monthly budgets with progress tracking.
/// Data persists via UserDefaults; spending is read from TransactionStore.
actor BudgetStore {
    static let shared = BudgetStore()

    private let storeKey = "category_budgets"
    private var budgets: [CategoryBudget] = []

    // MARK: - Models

    struct CategoryBudget: Codable, Identifiable {
        let id: String
        var category: String       // "Dining", "Shopping", "Transport", etc.
        var monthlyLimit: Double
        var isActive: Bool
        var createdAt: Date
    }

    struct BudgetProgress: Identifiable {
        let id: String
        let category: String
        let limit: Double
        let spent: Double
        let remaining: Double
        let percentage: Double     // 0.0 - 1.0+
        let isOverBudget: Bool
        let daysLeft: Int
        let dailyRemaining: Double // remaining / daysLeft
    }

    // MARK: - Init

    private init() {
        loadFromDisk()
    }

    // MARK: - CRUD

    func allBudgets() -> [CategoryBudget] {
        budgets.filter(\.isActive)
    }

    func addBudget(category: String, limit: Double) {
        // Prevent duplicates for the same category
        guard !budgets.contains(where: { $0.category == category && $0.isActive }) else { return }
        let budget = CategoryBudget(
            id: UUID().uuidString,
            category: category,
            monthlyLimit: limit,
            isActive: true,
            createdAt: Date()
        )
        budgets.append(budget)
        saveToDisk()
    }

    func updateBudget(id: String, limit: Double) {
        guard let idx = budgets.firstIndex(where: { $0.id == id }) else { return }
        budgets[idx].monthlyLimit = limit
        saveToDisk()
    }

    func deleteBudget(id: String) {
        budgets.removeAll { $0.id == id }
        saveToDisk()
    }

    func clearAll() {
        budgets = []
        saveToDisk()
    }

    // MARK: - Progress Calculation

    func progressForAll() async -> [BudgetProgress] {
        let activeBudgets = budgets.filter(\.isActive)
        guard !activeBudgets.isEmpty else { return [] }

        // Read transactions on MainActor
        let transactions = await MainActor.run {
            TransactionStore.shared.transactions
        }

        let calendar = Calendar.current
        let now = Date()

        // Filter this month's debits
        let thisMonthDebits = transactions.filter { txn in
            txn.type.uppercased() == "DEBIT" &&
            calendar.isDate(txn.date, equalTo: now, toGranularity: .month)
        }

        // Group spending by category
        var spendingByCategory: [String: Double] = [:]
        for txn in thisMonthDebits {
            spendingByCategory[txn.category, default: 0] += txn.amount
        }

        // Days left in month
        let daysLeft = daysRemainingInMonth()

        return activeBudgets.map { budget in
            let spent = spendingByCategory[budget.category] ?? 0
            let remaining = max(0, budget.monthlyLimit - spent)
            let percentage = budget.monthlyLimit > 0 ? spent / budget.monthlyLimit : 0
            let daily = daysLeft > 0 ? remaining / Double(daysLeft) : 0

            return BudgetProgress(
                id: budget.id,
                category: budget.category,
                limit: budget.monthlyLimit,
                spent: spent,
                remaining: remaining,
                percentage: percentage,
                isOverBudget: spent > budget.monthlyLimit,
                daysLeft: daysLeft,
                dailyRemaining: daily
            )
        }.sorted { $0.percentage > $1.percentage } // Most used budgets first
    }

    func progressFor(category: String) async -> BudgetProgress? {
        let all = await progressForAll()
        return all.first { $0.category == category }
    }

    // MARK: - Helpers

    private func daysRemainingInMonth() -> Int {
        let calendar = Calendar.current
        let now = Date()
        guard let range = calendar.range(of: .day, in: .month, for: now) else { return 1 }
        let today = calendar.component(.day, from: now)
        return max(1, range.count - today)
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(budgets)
            UserDefaults.standard.set(data, forKey: storeKey)
        } catch { }
    }

    private func loadFromDisk() {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else { return }
        do {
            budgets = try JSONDecoder().decode([CategoryBudget].self, from: data)
        } catch {
            budgets = []
        }
    }
}
