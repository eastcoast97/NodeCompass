import SwiftUI

/// Mind pillar tab — consolidates Life Score, AI Coach, Challenges, Achievements, and Digest.
/// The hero element is the Life Score ring, designed to feel aspirational and motivating.
struct MindTabView: View {
    @State private var lifeScore: LifeScoreEngine.DailyScore?
    @State private var previousScore: Int?
    @State private var activeChallenges: [ChallengeStore.Challenge] = []
    @State private var dietPlan: ChallengeStore.Challenge?
    @State private var showEndPlanConfirm = false
    @State private var earnedAchievements: [AchievementEngine.Achievement] = []
    @State private var lockedTypes: [AchievementEngine.AchievementType] = []
    @State private var insights: [Insight] = []
    @StateObject private var tokenTracker = GroqTokenTracker.shared

    @State private var showCoach = false
    @State private var showChallenges = false
    @State private var showAchievements = false
    @State private var showCircles = false
    @State private var isLoading = true

    // MARK: - Mind pillar accent
    private let mindPurple = NC.mind

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DiscoveryTip(
                        id: "mind",
                        icon: "brain.head.profile",
                        title: "Your AI Life Coach",
                        message: "Challenges, routines, and achievements. The AI coach connects patterns across all your data to give personalized advice.",
                        accentColor: NC.mind
                    )

                    if isLoading {
                        loadingState
                    } else {
                        lifeScoreHero
                            .sectionAppear(delay: 0.05)
                        aiCoachCard
                            .sectionAppear(delay: 0.1)
                        if dietPlan != nil {
                            dietPlanHero
                                .sectionAppear(delay: 0.12)
                        }
                        challengesSection
                            .sectionAppear(delay: 0.15)
                        circlesCard
                            .sectionAppear(delay: 0.2)
                        achievementsSection
                            .sectionAppear(delay: 0.25)
                        insightsCarousel
                            .sectionAppear(delay: 0.35)
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.bottom, 32)
            }
            .background(NC.bgBase)
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
        .sheet(isPresented: $showCircles) {
            CirclesView()
        }
        .overlay(alignment: .top) {
            TabCoachmark(
                id: "mind",
                icon: "brain.head.profile",
                title: "Welcome to Mind",
                body: "Tap the AI Coach to ask anything about your patterns. Add a Challenge below — keep it solo or invite a Circle to compete.",
                color: NC.mind
            )
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
                .background(NC.bgElevated, in: RoundedRectangle(cornerRadius: 10))
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

    // MARK: - Diet Plan Hero (only when active)

    /// AI-generated daily macro target. Renders as a hero card above the
    /// regular challenges list. Tapping the menu lets the user end the plan.
    @ViewBuilder
    private var dietPlanHero: some View {
        if let plan = dietPlan,
           let targets = plan.macroTargets,
           let progress = plan.macroProgress {
            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    Image(systemName: "target")
                        .foregroundStyle(NC.teal)
                    Text(plan.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if plan.dietStreakDays > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(plan.dietStreakDays)d")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.orange.opacity(0.12), in: Capsule())
                    }
                    Menu {
                        Button(role: .destructive) {
                            showEndPlanConfirm = true
                        } label: {
                            Label("End Plan", systemImage: "xmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                // Calorie banner — primary metric
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int(round(progress.calories)))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(NC.teal)
                        .monospacedDigit()
                    Text("/ \(Int(round(targets.calories))) kcal")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(round((progress.calories / max(targets.calories, 1)) * 100)))%")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(progressColor(for: progress.calories, target: targets.calories))
                }

                // Calorie progress bar
                progressBar(value: progress.calories, target: targets.calories, color: NC.teal)

                // Macro rows
                VStack(spacing: 10) {
                    macroRow(label: "Protein", current: progress.protein, target: targets.protein, color: .red)
                    macroRow(label: "Carbs",   current: progress.carbs,   target: targets.carbs,   color: .yellow)
                    macroRow(label: "Fat",     current: progress.fat,     target: targets.fat,     color: .indigo)
                    if let fiberTarget = targets.fiber {
                        macroRow(label: "Fiber", current: progress.fiber ?? 0, target: fiberTarget, color: .green)
                    }
                }

                Text("Resets daily • Streak counts when you hit ≥80% on calories AND protein")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .card()
            .alert("End diet plan?", isPresented: $showEndPlanConfirm) {
                Button("End Plan", role: .destructive) {
                    Task { await endDietPlan() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your daily target will stop tracking. You can always ask the AI Coach to set a new one.")
            }
        }
    }

    private func macroRow(label: String, current: Double, target: Double, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(round(current)))/\(Int(round(target)))g")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(color)
            }
            progressBar(value: current, target: target, color: color)
        }
    }

    private func progressBar(value: Double, target: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.15))
                    .frame(height: 6)
                let pct = target > 0 ? min(value / target, 1.2) : 0
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: max(0, geo.size.width * pct), height: 6)
            }
        }
        .frame(height: 6)
    }

    private func progressColor(for value: Double, target: Double) -> Color {
        guard target > 0 else { return .secondary }
        let ratio = value / target
        if ratio < 0.8 { return .orange }
        if ratio > 1.15 { return .red }   // overshooting on calories
        return .green
    }

    private func endDietPlan() async {
        guard let plan = dietPlan else { return }
        await ChallengeStore.shared.deleteChallenge(id: plan.id)
        dietPlan = nil
    }

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
        .background(NC.bgElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - 3.5 Circles (compete with friends)

    private var circlesCard: some View {
        Button {
            Haptic.light()
            showCircles = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.callout)
                        .foregroundStyle(NC.teal)
                    Text("Circles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text("Challenge friends in private groups. Share challenges, send reactions, see each other's progress.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .card()
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
                    .fill(earned ? mindPurple.opacity(0.15) : NC.bgElevated)
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

    // MARK: - 5. Insights Carousel

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
        .background(NC.bgElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: NC.cardRadius)
                    .fill(NC.bgElevated)
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

        // Challenges — refresh progress before reading so the diet plan
        // card shows fresh today-totals on every tab visit.
        await ChallengeStore.shared.updateProgress()
        let allActive = await ChallengeStore.shared.activeChallenges()
        // Pull diet plan out separately so the hero card can render it
        // distinctly; remaining challenges go in the regular section.
        dietPlan = allActive.first { $0.type == .dietPlan }
        activeChallenges = allActive.filter { $0.type != .dietPlan }

        // Achievements
        let earned = await AchievementEngine.shared.allAchievements()
        earnedAchievements = earned.sorted { $0.earnedAt > $1.earnedAt }
        let earnedTypes = Set(earned.map { $0.type })
        lockedTypes = AchievementEngine.AchievementType.allCases.filter { !earnedTypes.contains($0) }

        // Insights from PatternEngine
        insights = await PatternEngine.shared.activeInsights()

        isLoading = false
    }
}

#Preview {
    MindTabView()
}
