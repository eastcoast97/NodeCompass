import SwiftUI

/// Mind pillar tab — consolidates Life Score, AI Coach, Challenges, Achievements, and Digest.
/// The hero element is the Life Score ring, designed to feel aspirational and motivating.
struct MindTabView: View {
    @State private var lifeScore: LifeScoreEngine.DailyScore?
    @State private var previousScore: Int?
    @State private var activeChallenges: [ChallengeStore.Challenge] = []
    @State private var earnedAchievements: [AchievementEngine.Achievement] = []
    @State private var lockedTypes: [AchievementEngine.AchievementType] = []
    @State private var latestDigest: WeeklyDigestEngine.WeeklyDigest?
    @State private var insights: [Insight] = []
    @StateObject private var tokenTracker = GroqTokenTracker.shared

    @State private var showCoach = false
    @State private var showChallenges = false
    @State private var showAchievements = false
    @State private var showDigest = false
    @State private var isLoading = true

    // MARK: - Purple accent for Mind pillar
    private let mindPurple = Color(hex: "#A855F7")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isLoading {
                        loadingState
                    } else {
                        lifeScoreHero
                        aiCoachCard
                        challengesSection
                        achievementsSection
                        digestSection
                        insightsCarousel
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.bottom, 32)
            }
            .navigationTitle("Mind")
            .task { await loadAll() }
            .refreshable { await loadAll() }
        }
        .sheet(isPresented: $showCoach) {
            LifeCoachView()
        }
        .sheet(isPresented: $showChallenges) {
            ChallengesView()
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView()
        }
    }

    // MARK: - 1. Life Score Hero Card

    private var lifeScoreHero: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .foregroundStyle(mindPurple)
                Text("Life Score")
                    .font(.headline)
                Spacer()
                if let trend = scoreTrend {
                    trendBadge(trend)
                }
            }

            // Large circular score
            ZStack {
                // Background ring
                Circle()
                    .stroke(mindPurple.opacity(0.12), lineWidth: 12)
                    .frame(width: 140, height: 140)

                // Progress ring
                Circle()
                    .trim(from: 0, to: CGFloat(scoreValue) / 100.0)
                    .stroke(
                        AngularGradient(
                            colors: [mindPurple.opacity(0.6), mindPurple],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))

                // Score text
                VStack(spacing: 2) {
                    Text("\(scoreValue)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(mindPurple)
                    Text("of 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)

            // Pillar breakdown
            if let score = lifeScore {
                HStack(spacing: 0) {
                    pillarMini(label: "Wealth", value: score.wealth, icon: NC.currencyIconCircle, color: NC.teal)
                    Spacer()
                    pillarMini(label: "Health", value: score.health, icon: "heart.fill", color: .red)
                    Spacer()
                    pillarMini(label: "Food", value: score.food, icon: "fork.knife", color: NC.food)
                    Spacer()
                    pillarMini(label: "Routine", value: score.routine, icon: "clock.fill", color: .orange)
                }
            } else {
                Text("Log some activity to see your score")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.heroRadius, style: .continuous))
        .shadow(color: mindPurple.opacity(0.08), radius: 12, y: 4)
    }

    private func pillarMini(label: String, value: Int, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.system(.callout, design: .rounded, weight: .semibold))
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 60)
    }

    private func trendBadge(_ trend: Int) -> some View {
        HStack(spacing: 2) {
            Image(systemName: trend >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text("\(abs(trend))")
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (trend >= 0 ? Color.green : Color.red).opacity(0.12),
            in: Capsule()
        )
        .foregroundStyle(trend >= 0 ? .green : .red)
    }

    // MARK: - 2. AI Coach Quick Chat

    private var aiCoachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.callout)
                    .foregroundStyle(mindPurple)
                Text("AI Coach")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                // Subtle token usage
                Text(tokenTracker.formattedUsage)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            // Tap target that opens full coach
            Button {
                Haptic.light()
                showCoach = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Ask your AI coach...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            // Suggestion chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    suggestionChip("How am I doing?", icon: "chart.line.uptrend.xyaxis")
                    suggestionChip("Budget tips", icon: NC.currencyIcon)
                    suggestionChip("Set a challenge", icon: "flame.fill")
                }
            }
        }
        .card()
    }

    private func suggestionChip(_ text: String, icon: String) -> some View {
        Button {
            Haptic.light()
            showCoach = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(text)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(mindPurple.opacity(0.08), in: Capsule())
            .foregroundStyle(mindPurple)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Active Challenges

    private var challengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flame.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                Text("Active Challenges")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    Haptic.light()
                    showChallenges = true
                } label: {
                    Text("See All")
                        .font(.caption)
                        .foregroundStyle(mindPurple)
                }
            }

            if activeChallenges.isEmpty {
                // Empty state — motivate the user
                VStack(spacing: 8) {
                    Image(systemName: "flame")
                        .font(.title2)
                        .foregroundStyle(.orange.opacity(0.5))
                    Text("No active challenges")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        Haptic.light()
                        showChallenges = true
                    } label: {
                        Text("Start a Challenge")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mindPurple)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(mindPurple.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                ForEach(activeChallenges) { challenge in
                    challengeRow(challenge)
                }
            }
        }
        .card()
    }

    private func challengeRow(_ challenge: ChallengeStore.Challenge) -> some View {
        let progress = challenge.targetValue > 0
            ? min(challenge.currentValue / challenge.targetValue, 1.0)
            : 0.0
        let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: challenge.endDate).day ?? 0)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(challenge.title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(daysLeft)d left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(mindPurple.opacity(0.1))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(mindPurple)
                        .frame(width: geo.size.width * progress, height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(challenge.currentValue))/\(Int(challenge.targetValue))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(mindPurple)
            }
        }
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 4. Recent Achievements

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "trophy.fill")
                    .font(.callout)
                    .foregroundStyle(.yellow)
                Text("Achievements")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    Haptic.light()
                    showAchievements = true
                } label: {
                    Text("View All")
                        .font(.caption)
                        .foregroundStyle(mindPurple)
                }
            }

            if earnedAchievements.isEmpty && lockedTypes.isEmpty {
                Text("Complete challenges to earn badges")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Earned badges
                        ForEach(earnedAchievements.prefix(6)) { achievement in
                            achievementBadge(
                                icon: achievement.icon,
                                title: achievement.title,
                                earned: true
                            )
                        }
                        // Locked badges (dimmed)
                        ForEach(lockedTypes.prefix(4), id: \.rawValue) { type in
                            achievementBadge(
                                icon: type.icon,
                                title: type.rawValue.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized,
                                earned: false
                            )
                        }
                    }
                }
            }
        }
        .card()
    }

    private func achievementBadge(icon: String, title: String, earned: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(earned ? mindPurple.opacity(0.15) : Color(.systemGray5))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(earned ? mindPurple : .gray.opacity(0.4))
            }
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(earned ? .primary : .secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 60)
        }
        .opacity(earned ? 1.0 : 0.5)
        .onTapGesture {
            Haptic.light()
            showAchievements = true
        }
    }

    // MARK: - 5. Weekly Digest Preview

    private var digestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.callout)
                    .foregroundStyle(mindPurple)
                Text("Weekly Digest")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            if let digest = latestDigest {
                VStack(alignment: .leading, spacing: 8) {
                    Text(digest.weekKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Headline summary
                    HStack(spacing: 16) {
                        digestStat(label: "Avg Score", value: "\(digest.avgScore)", trend: digest.scoreTrend)
                        digestStat(label: "Spent", value: NC.money(digest.totalSpent), trend: nil)
                        digestStat(label: "Steps", value: "\(digest.avgSteps)", trend: nil)
                    }

                    if !digest.highlights.isEmpty {
                        Text(digest.highlights.first ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Button {
                        Haptic.light()
                        showDigest = true
                    } label: {
                        Text("View Full Digest")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(mindPurple)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(mindPurple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Your first digest arrives Sunday evening")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .card()
    }

    private func digestStat(label: String, value: String, trend: Int?) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text(value)
                    .font(.callout.weight(.semibold))
                if let t = trend, t != 0 {
                    Image(systemName: t > 0 ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(t > 0 ? .green : .red)
                }
            }
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 6. Insights Carousel

    private var insightsCarousel: some View {
        Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.callout)
                            .foregroundStyle(mindPurple)
                        Text("Pattern Insights")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(insights.prefix(5)) { insight in
                                insightCard(insight)
                            }
                        }
                    }
                }
                .card()
            }
        }
    }

    private func insightCard(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: insight.type.icon)
                    .font(.caption)
                    .foregroundStyle(mindPurple)
                Text(insight.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            Text(insight.body)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(width: 200, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: NC.cardRadius)
                    .fill(Color(.systemGray6))
                    .frame(height: 100)
                    .shimmer()
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Helpers

    private var scoreValue: Int {
        lifeScore?.total ?? 0
    }

    private var scoreTrend: Int? {
        guard let prev = previousScore, lifeScore != nil else { return nil }
        let diff = scoreValue - prev
        return diff
    }

    // MARK: - Data Loading

    private func loadAll() async {
        // Life Score
        let engine = LifeScoreEngine.shared
        let todayScore = await engine.todayScore()
        if todayScore == nil {
            let calculated = await engine.calculateToday()
            lifeScore = calculated
        } else {
            lifeScore = todayScore
        }

        // Previous week's average for trend
        let recent = await engine.recentScores(days: 14)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let lastWeekScores = recent.filter { $0.calculatedAt < weekAgo }
        if !lastWeekScores.isEmpty {
            previousScore = lastWeekScores.reduce(0) { $0 + $1.total } / lastWeekScores.count
        }

        // Challenges
        activeChallenges = await ChallengeStore.shared.activeChallenges()

        // Achievements
        let earned = await AchievementEngine.shared.allAchievements()
        earnedAchievements = earned.sorted { $0.earnedAt > $1.earnedAt }
        let earnedTypes = Set(earned.map { $0.type })
        lockedTypes = AchievementEngine.AchievementType.allCases.filter { !earnedTypes.contains($0) }

        // Weekly Digest
        latestDigest = await WeeklyDigestEngine.shared.latestDigest()

        // Insights from PatternEngine
        insights = await PatternEngine.shared.activeInsights()

        isLoading = false
    }
}

#Preview {
    MindTabView()
}
