import SwiftUI

// MARK: - Insights View

struct InsightsView: View {
    @StateObject private var vm = InsightsViewModel()
    @State private var selectedFilter: InsightFilter = .all
    @State private var showProfileDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // "This Is You" profile summary
                    profileSummaryCard

                    // Filter pills
                    filterPills

                    // Insights list
                    if filteredInsights.isEmpty {
                        emptyState
                    } else {
                        insightsList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { vm.refresh() }
            .task { vm.load(); await vm.loadProfile() }
        }
    }

    // MARK: - Profile Summary ("This Is You")

    private var profileSummaryCard: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(NC.teal)
                        Text("NodeCompass Knows")
                            .font(.caption.bold())
                            .foregroundStyle(NC.teal)
                    }
                    Text("Here's what I've learned about you")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let updated = vm.profileLastUpdated {
                    Text(timeAgoShort(updated))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider().padding(.horizontal, 12)

            // Summary bullets
            VStack(alignment: .leading, spacing: 10) {
                ForEach(vm.profileSummaryLines, id: \.self) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(pillColor(for: line))
                            .frame(width: 6, height: 6)
                            .padding(.top, 5)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)

            // Quick stats row
            if !vm.quickStats.isEmpty {
                Divider().padding(.horizontal, 12)

                HStack(spacing: 0) {
                    ForEach(vm.quickStats.indices, id: \.self) { i in
                        let stat = vm.quickStats[i]
                        VStack(spacing: 4) {
                            Text(stat.value)
                                .font(.headline.bold())
                                .foregroundStyle(stat.color)
                            Text(stat.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)

                        if i < vm.quickStats.count - 1 {
                            Divider().frame(height: 30)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 3)
    }

    // MARK: - Filter Pills

    private var filterPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InsightFilter.allCases, id: \.self) { filter in
                    Button {
                        withAnimation(.spring(response: 0.25)) { selectedFilter = filter }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: filter.icon)
                                .font(.caption2)
                            Text(filter.rawValue)
                                .font(.caption.bold())
                            if filter != .all {
                                let count = insightCount(for: filter)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 10).bold())
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(
                                            selectedFilter == filter ? .white.opacity(0.3) : filter.color.opacity(0.8),
                                            in: Circle()
                                        )
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selectedFilter == filter
                                ? filter.color.opacity(0.15)
                                : Color(.systemGray6)
                        )
                        .foregroundStyle(selectedFilter == filter ? filter.color : .secondary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedFilter == filter ? filter.color.opacity(0.3) : .clear, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Insights List

    private var insightsList: some View {
        VStack(spacing: 10) {
            // Urgent/high insights first (as alert cards)
            let urgent = filteredInsights.filter { $0.priority >= .high }
            if !urgent.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(NC.warning)
                        Text("Needs Attention")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ForEach(urgent) { insight in
                        InsightDetailCard(insight: insight) {
                            withAnimation { vm.dismiss(insight) }
                        }
                    }
                }
            }

            // Medium insights
            let medium = filteredInsights.filter { $0.priority == .medium }
            if !medium.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                            .foregroundStyle(NC.teal)
                        Text("Worth Knowing")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, urgent.isEmpty ? 0 : 8)

                    ForEach(medium) { insight in
                        InsightDetailCard(insight: insight) {
                            withAnimation { vm.dismiss(insight) }
                        }
                    }
                }
            }

            // Low priority — more compact
            let low = filteredInsights.filter { $0.priority == .low }
            if !low.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Patterns")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.top, (urgent.isEmpty && medium.isEmpty) ? 0 : 8)

                    ForEach(low) { insight in
                        InsightCompactCard(insight: insight) {
                            withAnimation { vm.dismiss(insight) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedFilter == .all ? "lightbulb.fill" : selectedFilter.icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(selectedFilter == .all
                 ? "No Insights Yet"
                 : "No \(selectedFilter.rawValue) Insights")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            Text("Keep syncing transactions, logging meals, and staying active. Insights will appear as patterns emerge.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 60)
    }

    // MARK: - Helpers

    private var filteredInsights: [Insight] {
        switch selectedFilter {
        case .all: return vm.insights
        case .wealth: return vm.insights.filter { $0.category == "spending" || $0.type == .spendingTrend || $0.type == .anomaly || $0.type == .ghostSubscription || $0.type == .categorySpike || $0.type == .milestone }
        case .health: return vm.insights.filter { $0.category == "health" || $0.type == .healthPattern || $0.type == .vitaminD }
        case .food: return vm.insights.filter { $0.category == "food" || $0.type == .foodPattern || $0.type == .nutritionAlert || $0.type == .foodSpending || $0.type == .mealStreak || $0.type == .eatingPattern }
        case .alerts: return vm.insights.filter { $0.priority >= .high }
        }
    }

    private func insightCount(for filter: InsightFilter) -> Int {
        switch filter {
        case .all: return vm.insights.count
        case .wealth: return vm.insights.filter { $0.category == "spending" || $0.type == .spendingTrend || $0.type == .anomaly || $0.type == .ghostSubscription || $0.type == .categorySpike || $0.type == .milestone }.count
        case .health: return vm.insights.filter { $0.category == "health" || $0.type == .healthPattern || $0.type == .vitaminD }.count
        case .food: return vm.insights.filter { $0.category == "food" || $0.type == .foodPattern || $0.type == .nutritionAlert || $0.type == .foodSpending || $0.type == .mealStreak || $0.type == .eatingPattern }.count
        case .alerts: return vm.insights.filter { $0.priority >= .high }.count
        }
    }

    private func pillColor(for line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("spend") || lower.contains("$") || lower.contains("order") { return NC.spend }
        if lower.contains("step") || lower.contains("workout") || lower.contains("sleep") || lower.contains("gym") { return .pink }
        if lower.contains("eat") || lower.contains("meal") || lower.contains("cook") || lower.contains("calor") || lower.contains("protein") { return .orange }
        return NC.teal
    }

    private func timeAgoShort(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Insight Filter

enum InsightFilter: String, CaseIterable {
    case all = "All"
    case alerts = "Alerts"
    case wealth = "Wealth"
    case food = "Food"
    case health = "Health"

    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .alerts: return "exclamationmark.triangle.fill"
        case .wealth: return NC.currencyIcon
        case .food: return "fork.knife"
        case .health: return "heart.fill"
        }
    }

    var color: Color {
        switch self {
        case .all: return NC.teal
        case .alerts: return NC.warning
        case .wealth: return NC.teal
        case .food: return .orange
        case .health: return .pink
        }
    }
}

// MARK: - Insight Detail Card (medium/high/urgent)

private struct InsightDetailCard: View {
    let insight: Insight
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            Image(systemName: insight.type.icon)
                .font(.callout)
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                // Priority + time
                HStack(spacing: 6) {
                    if insight.priority >= .high {
                        Text(insight.priority.label)
                            .font(.system(size: 10).bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priorityColor, in: Capsule())
                    }

                    Text(categoryLabel)
                        .font(.system(size: 10).bold())
                        .foregroundStyle(categoryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(categoryColor.opacity(0.1), in: Capsule())

                    Spacer()

                    Text(timeAgo(insight.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Title
                Text(insight.title)
                    .font(.subheadline.bold())

                // Body
                Text(insight.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Dismiss
            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
                    .background(Color(.systemGray5), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
    }

    private var iconColor: Color {
        switch insight.priority {
        case .urgent: return NC.spend
        case .high: return NC.warning
        case .medium: return NC.teal
        case .low: return .secondary
        }
    }

    private var priorityColor: Color {
        insight.priority == .urgent ? NC.spend : NC.warning
    }

    private var categoryLabel: String {
        if !insight.category.isEmpty { return insight.category.capitalized }
        switch insight.type {
        case .spendingTrend, .anomaly, .ghostSubscription, .categorySpike, .milestone: return "Wealth"
        case .healthPattern, .vitaminD: return "Health"
        case .foodPattern, .nutritionAlert, .foodSpending, .mealStreak, .eatingPattern: return "Food"
        default: return "Insight"
        }
    }

    private var categoryColor: Color {
        switch categoryLabel.lowercased() {
        case "spending", "wealth": return NC.teal
        case "food": return .orange
        case "health": return .pink
        default: return .secondary
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Insight Compact Card (low priority)

private struct InsightCompactCard: View {
    let insight: Insight
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.type.icon)
                .font(.caption)
                .foregroundStyle(categoryColor)
                .frame(width: 28, height: 28)
                .background(categoryColor.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.caption.bold())
                Text(insight.body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8).bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 18, height: 18)
                    .background(Color(.systemGray5), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var categoryColor: Color {
        let cat = insight.category.lowercased()
        if cat == "food" { return .orange }
        if cat == "health" { return .pink }
        if cat == "spending" { return NC.teal }
        return .secondary
    }
}
