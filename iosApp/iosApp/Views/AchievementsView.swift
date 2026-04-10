import SwiftUI

/// Achievements & streaks view — gamification layer.
struct AchievementsView: View {
    @StateObject private var vm = AchievementsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active Streaks
                    if !vm.activeStreaks.isEmpty {
                        streaksSection
                    }

                    // Stats Summary
                    statsCard

                    // Earned Achievements
                    if !vm.earned.isEmpty {
                        earnedSection
                    }

                    // Locked Achievements
                    if !vm.locked.isEmpty {
                        lockedSection
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
        }
    }

    // MARK: - Streaks

    private var streaksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Active Streaks")
                    .font(.subheadline.bold())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(vm.activeStreaks) { streak in
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                                .fill(.orange.opacity(0.12))
                                .frame(width: 36, height: 36)
                            Image(systemName: streak.type.icon)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(streak.currentDays) days")
                                .font(.subheadline.bold())
                            Text(streak.type.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(10)
                    .background(.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                }
            }
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(NC.teal)
                Text("Lifetime Stats")
                    .font(.subheadline.bold())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                miniStat(value: "\(vm.stats.totalWorkouts)", label: "Workouts", icon: "figure.run", color: .pink)
                miniStat(value: "\(vm.stats.daysUnderBudget)", label: "Under Budget", icon: "banknote.fill", color: NC.teal)
                miniStat(value: "\(vm.stats.totalHomeMeals)", label: "Home Meals", icon: "frying.pan.fill", color: NC.food)
                miniStat(value: "\(vm.stats.daysScoreAbove80)", label: "Score 80+", icon: "star.fill", color: .orange)
                miniStat(value: NC.money(vm.stats.totalSaved), label: "Saved", icon: "banknote.fill", color: .green)
                miniStat(value: "\(vm.earned.count)", label: "Badges", icon: "trophy.fill", color: .yellow)
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    private func miniStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Earned

    private var earnedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(.yellow)
                Text("Earned (\(vm.earned.count))")
                    .font(.subheadline.bold())
            }

            ForEach(vm.earned) { achievement in
                achievementRow(achievement, locked: false)
            }
        }
    }

    // MARK: - Locked

    private var lockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("Locked (\(vm.locked.count))")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            ForEach(vm.locked, id: \.rawValue) { type in
                lockedRow(type)
            }
        }
    }

    private func achievementRow(_ a: AchievementEngine.Achievement, locked: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(pillarColor(a.pillar).opacity(0.12))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: a.icon)
                    .font(.subheadline)
                    .foregroundStyle(pillarColor(a.pillar))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(a.title)
                    .font(.subheadline.bold())
                Text(a.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(a.earnedAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, NC.vPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    private func lockedRow(_ type: AchievementEngine.AchievementType) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(type.rawValue.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression).capitalized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Keep going to unlock")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: type.icon)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, NC.vPad)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    private func pillarColor(_ pillar: String) -> Color {
        switch pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "food": return NC.food
        case "routine": return .blue
        default: return .gray
        }
    }
}

// MARK: - ViewModel

@MainActor
class AchievementsViewModel: ObservableObject {
    @Published var earned: [AchievementEngine.Achievement] = []
    @Published var locked: [AchievementEngine.AchievementType] = []
    @Published var activeStreaks: [AchievementEngine.Streak] = []
    @Published var stats = AchievementEngine.LifetimeStats(
        totalWorkouts: 0, totalSteps: 0, totalHomeMeals: 0,
        daysUnderBudget: 0, daysScoreAbove80: 0, consecutiveLogDays: 0,
        totalSaved: 0, firstEventDate: nil
    )

    func load() async {
        // Evaluate today first (might earn new ones)
        _ = await AchievementEngine.shared.evaluateToday()

        earned = await AchievementEngine.shared.allAchievements()
        activeStreaks = await AchievementEngine.shared.activeStreaks()
        stats = await AchievementEngine.shared.stats()

        let earnedTypes = Set(earned.map { $0.type })
        locked = AchievementEngine.AchievementType.allCases.filter { !earnedTypes.contains($0) }
    }
}
