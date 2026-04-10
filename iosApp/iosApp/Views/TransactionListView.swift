import SwiftUI

struct TransactionListView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var filterSource: String? = nil
    @State private var searchText: String = ""

    var filteredTransactions: [StoredTransaction] {
        var txns = store.transactions
        if let source = filterSource {
            txns = txns.filter { $0.source == source }
        }
        if !searchText.isEmpty {
            txns = txns.filter {
                $0.merchant.localizedCaseInsensitiveContains(searchText) ||
                $0.category.localizedCaseInsensitiveContains(searchText)
            }
        }
        return txns
    }

    /// Group transactions by date section
    var groupedTransactions: [(String, [StoredTransaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { txn -> String in
            let cal = Calendar.current
            if cal.isDateInToday(txn.date) { return "Today" }
            if cal.isDateInYesterday(txn.date) { return "Yesterday" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: txn.date)
        }
        return grouped.sorted { lhs, rhs in
            let lhsDate = lhs.value.first?.date ?? .distantPast
            let rhsDate = rhs.value.first?.date ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    var body: some View {
        NavigationStack {
            if store.transactions.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Source filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "All", isSelected: filterSource == nil) {
                                withAnimation { filterSource = nil }
                            }
                            FilterChip(title: "Bank", icon: "building.columns.fill",
                                       isSelected: filterSource == "BANK") {
                                withAnimation { filterSource = "BANK" }
                            }
                            FilterChip(title: "Orders", icon: "bag.fill",
                                       isSelected: filterSource == "EMAIL") {
                                withAnimation { filterSource = "EMAIL" }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }

                    List {
                        ForEach(groupedTransactions, id: \.0) { section, txns in
                            Section {
                                ForEach(txns) { txn in
                                    NavigationLink(destination: TransactionDetailView(transaction: txn)) {
                                        TransactionRow(transaction: txn)
                                    }
                                }
                                .onDelete { indexSet in
                                    let toDelete = indexSet.map { txns[$0].id }
                                    for id in toDelete { store.delete(id: id) }
                                }
                            } header: {
                                Text(section)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search merchants, categories...")
                }
            }
        }
        .navigationTitle("Activity")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(NC.teal.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(NC.teal)
            }
            Text("No transactions yet")
                .font(.headline)
            Text("Connect your bank or email to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Transaction Row

private struct TransactionRow: View {
    let transaction: StoredTransaction

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            ZStack {
                Circle()
                    .fill(NC.color(for: transaction.category).opacity(0.12))
                    .frame(width: 42, height: 42)
                Image(systemName: NC.icon(for: transaction.category))
                    .font(.system(size: 15))
                    .foregroundStyle(NC.color(for: transaction.category))
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(transaction.merchant)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    if transaction.categorizedByAI {
                        Image(systemName: "brain.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(NC.teal)
                    }
                }

                HStack(spacing: 4) {
                    CategoryBadge(category: transaction.category, small: true)
                    if let items = transaction.lineItems, !items.isEmpty {
                        Text("\(items.count) items")
                            .font(.system(size: 10))
                            .foregroundStyle(.blue)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(transaction.formattedAmount)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(transaction.isCredit ? NC.income : .primary)
                Text(transaction.formattedDate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let title: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? NC.teal : Color(.systemGray6))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
        }
    }
}

#Preview {
    TransactionListView()
        .environmentObject(TransactionStore.shared)
}
