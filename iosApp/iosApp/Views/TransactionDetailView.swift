import SwiftUI

struct TransactionDetailView: View {
    let transaction: StoredTransaction

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: - Amount Header
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(NC.color(for: transaction.category).opacity(0.12))
                            .frame(width: 64, height: 64)
                        Image(systemName: NC.icon(for: transaction.category))
                            .font(.system(size: 24))
                            .foregroundStyle(NC.color(for: transaction.category))
                    }

                    Text(transaction.formattedAmount)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(transaction.isCredit ? NC.income : .primary)

                    Text(transaction.merchant)
                        .font(.title3)
                        .fontWeight(.medium)

                    HStack(spacing: 8) {
                        CategoryBadge(category: transaction.category)

                        if transaction.categorizedByAI {
                            HStack(spacing: 3) {
                                Image(systemName: "brain.fill")
                                    .font(.caption2)
                                Text("AI")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(NC.teal.opacity(0.12))
                            .foregroundStyle(NC.teal)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.top, 8)

                // MARK: - Description
                if let desc = transaction.description, !desc.isEmpty {
                    HStack {
                        Image(systemName: "text.alignleft")
                            .foregroundStyle(.secondary)
                        Text(desc)
                            .font(.subheadline)
                        Spacer()
                    }
                    .card()
                }

                // MARK: - Line Items
                if let items = transaction.lineItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "bag.fill")
                                .foregroundStyle(.purple)
                            Text("Items Ordered")
                                .font(.headline)
                            Spacer()
                            Text("\(items.count) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        ForEach(items) { item in
                            HStack {
                                if item.quantity > 1 {
                                    Text("\(item.quantity)x")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(NC.teal)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }

                                Text(item.name)
                                    .font(.subheadline)

                                Spacer()

                                Text("\(transaction.currencySymbol)\(item.amount, specifier: "%.2f")")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }

                        Divider()

                        let itemsTotal = items.reduce(0) { $0 + $1.amount * Double($1.quantity) }
                        HStack {
                            Text("Subtotal")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text("\(transaction.currencySymbol)\(itemsTotal, specifier: "%.2f")")
                                .font(.subheadline)
                                .fontWeight(.bold)
                        }
                    }
                    .card()
                }

                // MARK: - Details Grid
                VStack(spacing: 0) {
                    DetailGridRow(label: "Type", value: transaction.type, icon: "arrow.up.arrow.down")
                    Divider().padding(.horizontal)
                    DetailGridRow(label: "Date", value: fullDate, icon: "calendar")
                    Divider().padding(.horizontal)
                    DetailGridRow(label: "Source", value: transaction.source, icon: transaction.sourceIcon)
                    if let account = transaction.account, !account.isEmpty {
                        Divider().padding(.horizontal)
                        DetailGridRow(label: "Account", value: account, icon: "creditcard.fill")
                    }
                    Divider().padding(.horizontal)
                    DetailGridRow(label: "Currency", value: "\(transaction.currencySymbol) (\(transaction.currencyCode))", icon: "dollarsign.circle.fill")
                }
                .card(padding: 0)

                // MARK: - Raw Text
                if let raw = transaction.rawText, !raw.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "doc.text.fill")
                                .foregroundStyle(.secondary)
                            Text("Original Source")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        Text(raw)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                    .card()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fullDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: transaction.date)
    }
}

private struct DetailGridRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
