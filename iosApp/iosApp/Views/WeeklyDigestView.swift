import SwiftUI

/// Weekly digest view — summarizes the user's week across all pillars.
struct WeeklyDigestView: View {
    @StateObject private var vm = WeeklyDigestViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                if let digest = vm.digest {
                    VStack(spacing: 20) {
                        // Score Summary
                        scoreCard(digest)

                        // Highlights
                        if !digest.highlights.isEmpty {
                            highlightsCard(digest)
                        }

                        // Wealth Summary
                        wealthCard(digest)

                        // Health Summary
                        healthCard(digest)

                        // Food Summary
                        foodCard(digest)
                    }
                    .padding(.horizontal, NC.hPad)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                } else {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Generating your weekly digest...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 100)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Weekly Digest")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
        }
    }

    // MARK: - Score Card

    private func scoreCard(_ d: WeeklyDigestEngine.WeeklyDigest) -> some View {
        VStack(spacing: 16) {
            // Big score
            ZStack {
                Circle()
                    .stroke(NC.teal.opacity(0.15), lineWidth: 10)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(d.avgScore) / 100)
                    .stroke(NC.teal, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(d.avgScore)")
                        .font(.title.bold())
                    Text("avg")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Trend
            HStack(spacing: 6) {
                Image(systemName: d.scoreTrend >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption.bold())
                    .foregroundStyle(d.scoreTrend >= 0 ? .green : NC.spend)
                Text(d.scoreTrend >= 0 ? "+\(d.scoreTrend) vs last week" : "\(d.scoreTrend) vs last week")
                    .font(.caption.bold())
                    .foregroundStyle(d.scoreTrend >= 0 ? .green : NC.spend)
            }

            if let best = d.bestDay {
                Text("Best day: \(best) (\(d.bestDayScore))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Highlights

    private func highlightsCard(_ d: WeeklyDigestEngine.WeeklyDigest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Highlights", systemImage: "sparkles")
                .font(.subheadline.bold())
                .foregroundStyle(NC.teal)

            ForEach(d.highlights, id: \.self) { h in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(NC.teal)
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                    Text(h)
                        .font(.subheadline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Wealth

    private func wealthCard(_ d: WeeklyDigestEngine.WeeklyDigest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            pillarHeader(icon: "banknote.fill", title: "Wealth", color: NC.teal)

            HStack(spacing: 20) {
                statBlock(label: "Spent", value: NC.money(d.totalSpent), color: NC.spend)
                statBlock(label: "vs Last Week",
                          value: "\(d.spentVsLastWeek >= 0 ? "+" : "")\(Int(d.spentVsLastWeek))%",
                          color: d.spentVsLastWeek <= 0 ? .green : NC.spend)
                statBlock(label: "Saved", value: NC.money(d.savedAmount), color: .green)
            }

            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                        .fill(NC.color(for: d.topCategory).opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: NC.icon(for: d.topCategory))
                        .font(.caption2)
                        .foregroundStyle(NC.color(for: d.topCategory))
                }
                Text("Top: \(d.topCategory)")
                    .font(.caption)
                Spacer()
                Text(NC.money(d.topCategoryAmount))
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Health

    private func healthCard(_ d: WeeklyDigestEngine.WeeklyDigest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            pillarHeader(icon: "heart.fill", title: "Health", color: .pink)

            HStack(spacing: 20) {
                statBlock(label: "Avg Steps", value: d.avgSteps.formatted(), color: .pink)
                statBlock(label: "Workouts", value: "\(d.totalWorkouts)", color: .pink)
                statBlock(label: "Avg Sleep", value: String(format: "%.1fh", d.avgSleep), color: .indigo)
            }

            if let day = d.bestWorkoutDay {
                HStack(spacing: 6) {
                    Image(systemName: "figure.run")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                    Text("Most active on \(day)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Food

    private func foodCard(_ d: WeeklyDigestEngine.WeeklyDigest) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            pillarHeader(icon: "fork.knife", title: "Food", color: NC.food)

            HStack(spacing: 20) {
                statBlock(label: "Home Meals", value: "\(d.homeMeals)/\(d.totalMeals)", color: NC.food)
                statBlock(label: "Avg Calories", value: "\(d.avgCalories)", color: .orange)
            }

            if let staple = d.topStaple {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Top staple: \(staple.capitalized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Helpers

    private func pillarHeader(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            Text(title)
                .font(.subheadline.bold())
        }
    }

    private func statBlock(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ViewModel

@MainActor
class WeeklyDigestViewModel: ObservableObject {
    @Published var digest: WeeklyDigestEngine.WeeklyDigest?

    func load() async {
        digest = await WeeklyDigestEngine.shared.generateCurrentWeekDigest()
    }
}
