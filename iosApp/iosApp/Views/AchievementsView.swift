import SwiftUI

/// Achievements & streaks view — gamification layer.
struct AchievementsView: View {
    @StateObject private var vm = AchievementsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                // Show an aspirational empty state when the user has nothing
                // yet — better than rendering "0 earned / 0 streak / 0 stats"
                // which looks broken.
                if vm.earned.isEmpty && vm.activeStreaks.isEmpty {
                    emptyState
                        .padding(.horizontal, NC.hPad)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 20) {
                        summaryHeader

                        if !vm.activeStreaks.isEmpty {
                            streaksSection
                        }

                        statsCard

                        if !vm.earned.isEmpty {
                            earnedSection
                        }

                        if !vm.locked.isEmpty {
                            lockedSection
                        }
                    }
                    .padding(.horizontal, NC.hPad)
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
        }
    }

    /// Aspirational empty state. Shows three example badges you *could* earn
    /// with a neutral tone and a concrete next step.
    private var emptyState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(NC.teal.opacity(0.1))
                    .frame(width: 110, height: 110)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(NC.teal)
            }

            VStack(spacing: 6) {
                Text("Your first badge is on the way")
                    .font(.title3.bold())
                Text("Badges and streaks unlock as NodeCompass learns your patterns. Keep using the app — you don't need to do anything special.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            VStack(spacing: 10) {
                lockedExampleRow(icon: "figure.run", title: "First Workout", hint: "Log or sync one workout from Health")
                lockedExampleRow(icon: "fork.knife", title: "Home Chef", hint: "Cook one meal at home")
                lockedExampleRow(icon: "flame.fill", title: "Week Warrior", hint: "Check in 7 days in a row")
            }
            .padding(.horizontal, 8)
        }
    }

    private func lockedExampleRow(icon: String, title: String, hint: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(Color(.systemGray5))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, NC.vPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 20) {
            // Earned count
            VStack(spacing: 4) {
                Text("\(vm.earned.count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(NC.teal)
                Text("Earned")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            // Best streak
            VStack(spacing: 4) {
                let bestStreak = vm.activeStreaks.max(by: { $0.currentDays < $1.currentDays })
                Text("\(bestStreak?.currentDays ?? 0)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text("Best Streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider().frame(height: 40)

            // Total possible
            VStack(spacing: 4) {
                Text("\(AchievementEngine.AchievementType.allCases.count)")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Total")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
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
                            Circle()
                                .fill(.orange.opacity(0.1))
                                .frame(width: 38, height: 38)
                            Image(systemName: streak.type.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(streak.currentDays)")
                                .font(.title3.bold())
                                .foregroundStyle(.orange) +
                            Text(" days")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(streak.type.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.03), radius: 3, y: 2)
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
                miniStat(value: "\(vm.earned.count)/\(AchievementEngine.AchievementType.allCases.count)", label: "Badges", icon: "trophy.fill", color: .yellow)
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private func miniStat(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.1), in: Circle())
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
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(pillarColor(achievement.pillar).opacity(0.1))
                            .frame(width: NC.iconSize, height: NC.iconSize)
                        Image(systemName: achievement.icon)
                            .font(.subheadline)
                            .foregroundStyle(pillarColor(achievement.pillar))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(achievement.title)
                            .font(.subheadline.bold())
                        Text(achievement.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(achievement.earnedAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
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
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemGray5))
                            .frame(width: NC.iconSize, height: NC.iconSize)
                        Image(systemName: type.icon)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(formatTypeName(type.rawValue))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Keep going to unlock")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()
                }
                .padding(14)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
                .opacity(0.7)
            }
        }
    }

    // MARK: - Helpers

    private func pillarColor(_ pillar: String) -> Color {
        switch pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "food": return NC.food
        case "routine": return .blue
        default: return .gray
        }
    }

    private func formatTypeName(_ raw: String) -> String {
        raw.replacingOccurrences(of: "([A-Z])", with: " $1", options: .regularExpression)
           .replacingOccurrences(of: "([0-9]+)", with: " $1", options: .regularExpression)
           .capitalized
           .trimmingCharacters(in: .whitespaces)
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
        _ = await AchievementEngine.shared.evaluateToday()

        earned = await AchievementEngine.shared.allAchievements()
        activeStreaks = await AchievementEngine.shared.activeStreaks()
        stats = await AchievementEngine.shared.stats()

        let earnedTypes = Set(earned.map { $0.type })
        locked = AchievementEngine.AchievementType.allCases.filter { !earnedTypes.contains($0) }
    }
}
