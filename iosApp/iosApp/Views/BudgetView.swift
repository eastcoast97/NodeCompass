import SwiftUI

// MARK: - Budget View

struct BudgetView: View {
    @State private var budgetProgress: [BudgetStore.BudgetProgress] = []
    @State private var upcomingBills: [BillCalendarEngine.RecurringBill] = []
    @State private var totalBillsDue: Double = 0
    @State private var totalBudget: Double = 0
    @State private var totalSpent: Double = 0
    @State private var showAddBudget = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Hero ring
                    overviewCard

                    // Category budgets
                    if budgetProgress.isEmpty && !isLoading {
                        emptyBudgetState
                    } else {
                        budgetList
                    }

                    // Add budget button
                    addBudgetButton

                    // Bill calendar
                    billCalendarSection
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Budgets")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddBudget) {
                AddBudgetSheet(onAdd: { category, limit in
                    Task {
                        await BudgetStore.shared.addBudget(category: category, limit: limit)
                        await reload()
                        showAddBudget = false
                    }
                })
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    // MARK: - Overview Card

    private var overviewCard: some View {
        VStack(spacing: 14) {
            ZStack {
                // Background track
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 10)
                    .frame(width: 100, height: 100)

                // Progress arc
                Circle()
                    .trim(from: 0, to: min(1.0, overallPercentage))
                    .stroke(
                        overallPercentage > 1.0 ? NC.spend :
                        overallPercentage > 0.75 ? NC.warning : NC.teal,
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: overallPercentage)

                VStack(spacing: 2) {
                    Text("\(Int(overallPercentage * 100))%")
                        .font(.title2.bold())
                    Text("used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 24) {
                VStack(spacing: 2) {
                    Text("Spent")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(NC.money(totalSpent))
                        .font(.subheadline.bold())
                        .foregroundStyle(NC.spend)
                }
                VStack(spacing: 2) {
                    Text("Budget")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(NC.money(totalBudget))
                        .font(.subheadline.bold())
                        .foregroundStyle(NC.teal)
                }
                VStack(spacing: 2) {
                    Text("Remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(NC.money(max(0, totalBudget - totalSpent)))
                        .font(.subheadline.bold())
                        .foregroundStyle(NC.income)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private var overallPercentage: Double {
        guard totalBudget > 0 else { return 0 }
        return totalSpent / totalBudget
    }

    // MARK: - Budget List

    private var budgetList: some View {
        VStack(spacing: 12) {
            ForEach(budgetProgress) { progress in
                BudgetCard(progress: progress, onDelete: {
                    Task {
                        await BudgetStore.shared.deleteBudget(id: progress.id)
                        await reload()
                    }
                })
            }
        }
    }

    // MARK: - Empty State

    private var emptyBudgetState: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 40))
                .foregroundStyle(NC.teal.opacity(0.4))
            Text("No budgets yet")
                .font(.headline)
            Text("Set per-category budgets and track your spending against them throughout the month.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Add Budget Button

    private var addBudgetButton: some View {
        Button { showAddBudget = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                Text("Add a Budget")
                    .fontWeight(.medium)
            }
            .font(.subheadline)
            .foregroundStyle(NC.teal)
            .frame(maxWidth: .infinity)
            .padding(.vertical, NC.vPad)
            .background(NC.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
    }

    // MARK: - Bill Calendar Section

    private var billCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(NC.teal)
                Text("Upcoming Bills")
                    .font(.headline)
                Spacer()
                if totalBillsDue > 0 {
                    Text(NC.money(totalBillsDue))
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)

            if upcomingBills.isEmpty && !isLoading {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(NC.income.opacity(0.6))
                        Text("No upcoming bills detected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 20)
                    Spacer()
                }
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
            } else {
                ForEach(upcomingBills) { bill in
                    BillRow(bill: bill)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func reload() async {
        isLoading = true
        let progress = await BudgetStore.shared.progressForAll()
        let bills = await BillCalendarEngine.shared.upcomingBills(days: 30)
        let billTotal = await BillCalendarEngine.shared.totalDueThisMonth()

        await MainActor.run {
            budgetProgress = progress
            upcomingBills = bills
            totalBillsDue = billTotal
            totalBudget = progress.reduce(0) { $0 + $1.limit }
            totalSpent = progress.reduce(0) { $0 + $1.spent }
            isLoading = false
        }
    }
}

// MARK: - Budget Card

private struct BudgetCard: View {
    let progress: BudgetStore.BudgetProgress
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: icon + category + daily hint
            HStack(spacing: 10) {
                Image(systemName: NC.icon(for: progress.category))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: NC.iconSize, height: NC.iconSize)
                    .background(NC.color(for: progress.category), in: RoundedRectangle(cornerRadius: NC.iconRadius))

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.category)
                        .font(.subheadline.weight(.semibold))
                    Text("\(NC.money(progress.spent)) / \(NC.money(progress.limit))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if progress.isOverBudget {
                    Text("Over budget!")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(NC.spend, in: Capsule())
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("~\(NC.money(progress.dailyRemaining))/day")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("\(progress.daysLeft)d left")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: min(geo.size.width, geo.size.width * progress.percentage), height: 8)
                        .animation(.easeOut(duration: 0.5), value: progress.percentage)
                }
            }
            .frame(height: 8)
        }
        .card()
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete Budget", systemImage: "trash")
            }
        }
    }

    private var progressColor: Color {
        if progress.percentage > 1.0 { return NC.spend }
        if progress.percentage > 0.75 { return NC.warning }
        return NC.income
    }
}

// MARK: - Bill Row

private struct BillRow: View {
    let bill: BillCalendarEngine.RecurringBill

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: NC.icon(for: bill.category))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: NC.iconSize, height: NC.iconSize)
                .background(NC.color(for: bill.category), in: RoundedRectangle(cornerRadius: NC.iconRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(bill.merchant)
                    .font(.subheadline.weight(.medium))
                Text(bill.frequency.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(NC.money(bill.estimatedAmount))
                    .font(.subheadline.weight(.semibold))

                if let due = bill.nextDueDate {
                    let days = daysUntil(due)
                    Text(days == 0 ? "Due today" : days == 1 ? "Due tomorrow" : "Due in \(days)d")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(days <= 3 ? NC.spend : NC.warning)
                }
            }
        }
        .card()
    }

    private func daysUntil(_ date: Date) -> Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0)
    }
}

// MARK: - Add Budget Sheet

private struct AddBudgetSheet: View {
    let onAdd: (String, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory = "Food & Dining"
    @State private var limitText = ""
    @FocusState private var isLimitFocused: Bool

    private let categories = [
        "Food & Dining", "Groceries", "Transport", "Shopping",
        "Subscriptions", "Bills & Utilities", "Entertainment",
        "Health", "Education", "Travel", "Other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in
                            HStack(spacing: 8) {
                                Image(systemName: NC.icon(for: cat))
                                    .foregroundStyle(NC.color(for: cat))
                                Text(cat)
                            }
                            .tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Monthly Limit") {
                    HStack {
                        Text(NC.currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("e.g. 500", text: $limitText)
                            .keyboardType(.decimalPad)
                            .focused($isLimitFocused)
                    }
                }

                Section {
                    Button {
                        guard let limit = Double(limitText), limit > 0 else { return }
                        onAdd(selectedCategory, limit)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Set Budget")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(Double(limitText) == nil || (Double(limitText) ?? 0) <= 0)
                }
            }
            .navigationTitle("Add Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isLimitFocused = true }
        }
    }
}

// MARK: - Preview

#Preview {
    BudgetView()
}
