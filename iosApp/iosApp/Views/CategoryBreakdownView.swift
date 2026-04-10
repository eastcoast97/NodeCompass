import SwiftUI
import Charts

struct CategoryBreakdownView: View {
    let data: [CategorySpend]

    private var total: Double {
        data.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Pie chart at top
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Amount", item.amount),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(by: .value("Category", item.categoryName))
                    .cornerRadius(4)
                }
                .frame(height: 250)
                .padding()

                // Detailed breakdown list
                ForEach(data) { item in
                    HStack {
                        Circle()
                            .fill(item.color)
                            .frame(width: 12, height: 12)

                        Text(item.categoryName)
                            .font(.body)

                        Spacer()

                        VStack(alignment: .trailing) {
                            Text(item.formattedAmount)
                                .font(.body)
                                .fontWeight(.medium)
                            if total > 0 {
                                Text(String(format: "%.1f%%", (item.amount / total) * 100))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
            }
        }
        .navigationTitle("Categories")
    }
}
