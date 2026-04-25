import SwiftUI

// MARK: - Wealth Tab View

struct WealthTabView: View {
    @EnvironmentObject var store: TransactionStore

    // Sheet presentation state
    @State private var showBudgets = false
    @State private var showSubscriptions = false
    @State private var showSavings = false
    @State private var showAllTransactions = false
    @State private var showAddTransaction = false
    @State private var showTrends = false

    // Async-loaded data
    @State private var budgetProgress: [BudgetStore.BudgetProgress] = []
    @State private var savingsProgress: [SavingsGoalStore.SavingsProgress] = []
    @State private var activeSubscriptions: [SubscriptionManager.Subscription] = []
    @State private var subscriptionMonthly: Double = 0

    // MARK: - Computed Properties

    private var thisMonthTransactions: [StoredTransaction] {
        let cal = Calendar.current
        let now = Date()
        return store.transactions.filter {
            cal.isDate($0.date, equalTo: now, toGranularity: .month)
        }
    }

    private var totalSpend: Double {
        thisMonthTransactions
            .filter { $0.type.uppercased() == "DEBIT" }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalIncome: Double {
        thisMonthTransactions
            .filter { $0.type.uppercased() == "CREDIT" }
            .reduce(0) { $0 + $1.amount }
    }

    private var netAmount: Double {
        totalIncome - totalSpend
    }

    private var lastMonthSpend: Double {
        let cal = Calendar.current
        guard let lastMonth = cal.date(byAdding: .month, value: -1, to: Date()) else { return 0 }
        return store.transactions
            .filter {
                $0.type.uppercased() == "DEBIT" &&
                cal.isDate($0.date, equalTo: lastMonth, toGranularity: .month)
            }
            .reduce(0) { $0 + $1.amount }
    }

    private var spendChangePercent: Double {
        guard lastMonthSpend > 0 else { return 0 }
        return ((totalSpend - lastMonthSpend) / lastMonthSpend) * 100
    }

    private var recentTransactions: [StoredTransaction] {
        Array(store.transactions.prefix(6))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DiscoveryTip(
                        id: "wealth",
                        icon: NC.currencyIcon,
                        title: "Your Financial Brain",
                        message: "Every transaction is categorized automatically. Subscriptions, patterns, and budget insights surface over time.",
                        accentColor: NC.teal
                    )

                    spendingSummaryCard
                        .sectionAppear(delay: 0.05)
                    quickActionsRow
                        .sectionAppear(delay: 0.1)
                    subscriptionPreviewSection
                        .sectionAppear(delay: 0.15)
                    recentTransactionsSection
                        .sectionAppear(delay: 0.2)
                    budgetProgressSection
                        .sectionAppear(delay: 0.3)
                    savingsGoalsPreview
                        .sectionAppear(delay: 0.35)
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NC.bgBase)
            .navigationTitle("Wealth")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptic.light()
                        showAddTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(NC.teal)
                    }
                }
            }
            .sheet(isPresented: $showBudgets) { BudgetView() }
            .sheet(isPresented: $showSubscriptions) { SubscriptionManagerView() }
            .sheet(isPresented: $showSavings) { GoalsView() }
            .sheet(isPresented: $showTrends) { TrendChartsView() }
            .sheet(isPresented: $showAllTransactions) {
                TransactionListView()
                    .environmentObject(store)
            }
            .task { await loadAsyncData() }
            .refreshable { await loadAsyncData() }
        }
    }

    // MARK: - 1. Spending Summary Card (Hero)

    private var spendingSummaryCard: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthName())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Spending Summary")
                        .font(.title3.bold())
                }
                Spacer()
                Image(systemName: NC.currencyIconCircle)
                    .font(.title2)
                    .foregroundStyle(NC.teal)
            }

            // Main figures
            HStack(spacing: 0) {
                summaryFigure(
                    label: "Spent",
                    value: NC.money(totalSpend),
                    color: NC.spend
                )
                Spacer()
                summaryFigure(
                    label: "Income",
                    value: NC.money(totalIncome),
                    color: NC.income
                )
                Spacer()
                summaryFigure(
                    label: "Net",
                    value: NC.money(abs(netAmount)),
                    color: netAmount >= 0 ? NC.income : NC.spend,
                    prefix: netAmount >= 0 ? "+" : "-"
                )
            }

            // Progress bar vs last month
            if lastMonthSpend > 0 {
                VStack(spacing: 6) {
                    HStack {
                        Text("vs Last Month")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(spendChangeLabel)
                            .font(.caption.bold())
                            .foregroundStyle(spendChangePercent <= 0 ? NC.income : NC.spend)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(NC.bgElevated)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(progressBarColor)
                                .frame(
                                    width: min(geo.size.width, geo.size.width * progressBarFraction),
                                    height: 6
                                )
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .card()
    }

    private func summaryFigure(label: String, value: String, color: Color, prefix: String = "") -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(prefix + value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private var spendChangeLabel: String {
        let pct = abs(spendChangePercent)
        let direction = spendChangePercent <= 0 ? "less" : "more"
        return String(format: "%.0f%% %@", pct, direction)
    }

    private var progressBarFraction: CGFloat {
        guard lastMonthSpend > 0 else { return 0 }
        return CGFloat(min(totalSpend / lastMonthSpend, 1.5))
    }

    private var progressBarColor: Color {
        totalSpend <= lastMonthSpend ? NC.income : NC.spend
    }

    // MARK: - 2. Quick Actions Row

    private var quickActionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                quickActionPill(icon: "chart.pie.fill", label: "Budgets", color: Color(hex: "#6366F1")) {
                    showBudgets = true
                }
                quickActionPill(icon: "repeat", label: "Subscriptions", color: Color(hex: "#EC4899")) {
                    showSubscriptions = true
                }
                quickActionPill(icon: "target", label: "Goals", color: NC.teal) {
                    showSavings = true
                }
                quickActionPill(icon: "chart.xyaxis.line", label: "Trends", color: NC.slate) {
                    showTrends = true
                }
            }
            .padding(.horizontal, 2) // prevent shadow clipping
        }
    }

    private func quickActionPill(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.light()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(color.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Recent Transactions

    private var recentTransactionsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Recent", systemImage: "clock.fill")
                    .font(.headline)
                Spacer()
                Button {
                    Haptic.light()
                    showAllTransactions = true
                } label: {
                    Text("See All")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(NC.teal)
                }
            }

            if recentTransactions.isEmpty {
                emptyPlaceholder(
                    icon: "tray",
                    title: "No transactions yet",
                    subtitle: "Your spending will appear here"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentTransactions.enumerated()), id: \.element.id) { index, txn in
                        compactTransactionRow(txn)
                        if index < recentTransactions.count - 1 {
                            Divider()
                                .padding(.leading, NC.dividerIndent)
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }

    private func compactTransactionRow(_ txn: StoredTransaction) -> some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(NC.color(for: txn.category).opacity(0.12))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: NC.icon(for: txn.category))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NC.color(for: txn.category))
            }

            // Merchant + category
            VStack(alignment: .leading, spacing: 2) {
                Text(txn.merchant)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(txn.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(txn.isCredit ? "+" : "-")\(NC.money(txn.amount))")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(txn.isCredit ? NC.income : NC.spend)
                Text(relativeDate(txn.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 4. Budget Progress Cards

    @ViewBuilder
    private var budgetProgressSection: some View {
        if !budgetProgress.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    Label("Budgets", systemImage: "chart.pie.fill")
                        .font(.headline)
                    Spacer()
                    Button {
                        Haptic.light()
                        showBudgets = true
                    } label: {
                        Text("Manage")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NC.teal)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(budgetProgress) { budget in
                            budgetCard(budget)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func budgetCard(_ budget: BudgetStore.BudgetProgress) -> some View {
        VStack(spacing: 10) {
            // Progress ring
            ZStack {
                Circle()
                    .stroke(NC.bgElevated, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: min(budget.percentage, 1.0))
                    .stroke(
                        budget.isOverBudget ? NC.spend : NC.color(for: budget.category),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(min(budget.percentage, 1.0) * 100))%")
                        .font(.caption.bold().monospacedDigit())
                    if budget.isOverBudget {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(NC.spend)
                    }
                }
            }
            .frame(width: 52, height: 52)

            // Label
            Text(budget.category)
                .font(.caption2.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(.secondary)

            // Amounts
            VStack(spacing: 1) {
                Text(NC.money(budget.spent))
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(budget.isOverBudget ? NC.spend : .primary)
                Text("of \(NC.money(budget.limit))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 100)
        .card(padding: 12)
    }

    // MARK: - 5. Savings Goals Preview

    @ViewBuilder
    private var savingsGoalsPreview: some View {
        let activeGoals = savingsProgress.filter { !$0.goal.isCompleted }
        if !activeGoals.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    Label("Savings Goals", systemImage: "target")
                        .font(.headline)
                    Spacer()
                    Button {
                        Haptic.light()
                        showSavings = true
                    } label: {
                        Text("View All")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NC.teal)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(activeGoals.prefix(3)) { progress in
                        savingsGoalRow(progress)
                    }
                }
                .card()
            }
        }
    }

    private func savingsGoalRow(_ progress: SavingsGoalStore.SavingsProgress) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(NC.teal.opacity(0.12))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: progress.goal.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NC.teal)
            }

            // Name + progress bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(progress.goal.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int(progress.percentage * 100))%")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(NC.teal)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NC.bgElevated)
                            .frame(height: 5)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(NC.teal)
                            .frame(width: geo.size.width * min(progress.percentage, 1.0), height: 5)
                    }
                }
                .frame(height: 5)
                HStack {
                    Text(NC.money(progress.currentSaved))
                        .font(.caption2.weight(.medium))
                    Text("of \(NC.money(progress.goal.targetAmount))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Subscription Preview (inline)

    @ViewBuilder
    private var subscriptionPreviewSection: some View {
        if !activeSubscriptions.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    Label("Subscriptions", systemImage: "repeat")
                        .font(.headline)
                    Spacer()
                    Text(NC.money(subscriptionMonthly) + "/mo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: "#EC4899"))
                    Button {
                        Haptic.light()
                        showSubscriptions = true
                    } label: {
                        Text("Manage")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NC.teal)
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(activeSubscriptions.prefix(4).enumerated()), id: \.element.id) { index, sub in
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                                    .fill(Color(hex: "#EC4899").opacity(0.12))
                                    .frame(width: NC.iconSize, height: NC.iconSize)
                                Image(systemName: sub.frequency.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color(hex: "#EC4899"))
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub.merchant)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(sub.frequency.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(NC.money(sub.amount))
                                    .font(.subheadline.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(NC.spend)
                                if let next = sub.nextChargeDate {
                                    Text("Next: \(relativeDate(next))")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        if index < min(activeSubscriptions.count, 4) - 1 {
                            Divider()
                                .padding(.leading, NC.dividerIndent)
                        }
                    }
                }
                .card(padding: 0)

                if activeSubscriptions.count > 4 {
                    Button {
                        Haptic.light()
                        showSubscriptions = true
                    } label: {
                        Text("+\(activeSubscriptions.count - 4) more subscriptions")
                            .font(.caption)
                            .foregroundStyle(NC.teal)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func emptyPlaceholder(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.quaternary)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .card()
    }

    private func monthName() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        return fmt.string(from: Date())
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }

    private func loadAsyncData() async {
        async let b = BudgetStore.shared.progressForAll()
        async let s = SavingsGoalStore.shared.progressForAll()
        async let subs = SubscriptionManager.shared.allSubscriptions()
        async let monthly = SubscriptionManager.shared.monthlyTotal()

        budgetProgress = await b
        savingsProgress = await s

        let allSubs = await subs
        activeSubscriptions = allSubs.filter(\.isActive)
        subscriptionMonthly = await monthly
    }
}

// MARK: - Preview

#Preview {
    WealthTabView()
        .environmentObject(TransactionStore.shared)
}
