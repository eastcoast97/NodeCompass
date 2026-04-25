import SwiftUI
import Charts

// MARK: - Dashboard Pages

enum DashboardPage: Int, CaseIterable {
    case wealth = 0
    case health = 1
    case insights = 2

    var title: String {
        switch self {
        case .wealth: return "Wealth"
        case .health: return "Health"
        case .insights: return "Insights"
        }
    }

    var icon: String {
        switch self {
        case .wealth: return NC.currencyIcon
        case .health: return "heart.fill"
        case .insights: return "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .wealth: return NC.teal
        case .health: return .pink
        case .insights: return .orange
        }
    }
}

// MARK: - Dashboard View

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @StateObject private var authAlert = IntegrationAuthAlert()
    @EnvironmentObject var store: TransactionStore
    @State private var activePage: DashboardPage = .wealth
    @State private var showFoodLog = false
    @State private var showGoals = false
    @State private var showProfile = false
    @State private var showAchievements = false
    @State private var showMood = false
    @State private var showCoach = false
    @State private var showHeatmap = false
    @State private var showExportSheet = false
    @State private var pendingEntryToComplete: FoodStore.FoodLogEntry?
    @State private var nudges: [NudgeEngine.Nudge] = []
    @State private var todayPulse: TodayPulseEngine.TodayPulse?
    @State private var learningStage: AppLearningStage.Stage = .warmingUp
    @State private var userFocus: AppLearningStage.UserFocus = .everything
    @State private var daysUntilNextStage: Int = 0
    // Cross-pillar dashboard data
    @State private var habitsDone: Int = 0
    @State private var habitsTotal: Int = 0
    @State private var activeSubCount: Int = 0
    @State private var subMonthlyTotal: Double = 0
    // Inline dashboard cards
    @State private var activeChallenges: [ChallengeStore.Challenge] = []
    @State private var budgetProgress: [BudgetStore.BudgetProgress] = []
    @State private var savingsGoals: [SavingsGoalStore.SavingsProgress] = []
    @State private var activeStreaks: [AchievementEngine.Streak] = []
    @State private var earnedBadgeCount: Int = 0
    // Sheet navigation
    @State private var showHabits = false
    @State private var showSubscriptions = false
    @State private var showChallenges = false
    @State private var showBudget = false
    @ObservedObject private var profileStore = PersonalInfoStore.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Discovery tip for first-time users
                    DiscoveryTip(
                        id: "dashboard",
                        icon: "sparkles",
                        title: "Your Daily Pulse",
                        message: "This is your command center. It learns your patterns across money, health, and habits — and gets smarter every day.",
                        accentColor: NC.teal
                    )
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Re-auth alert banner (persistent until resolved)
                    if !authAlert.issues.isEmpty {
                        reAuthBanner
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                    }

                    // Today's Pulse — the hero of the redesigned dashboard.
                    if let pulse = todayPulse {
                        TodayPulseCard(
                            pulse: pulse,
                            stage: learningStage,
                            daysUntilNextStage: daysUntilNextStage
                        )
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .sectionAppear(delay: 0.1)
                    }

                    // Life Score + Goals
                    if learningStage.showsLifeScore, let score = vm.lifeScore {
                        LifeScoreCard(score: score, goalProgress: vm.goalProgress, onGoalsTap: {
                            showGoals = true
                        })
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .sectionAppear(delay: 0.15)
                    }

                    // Mood quick check-in
                    if learningStage.allowsNudges {
                        moodQuickRow
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .sectionAppear(delay: 0.2)
                    }

                    // Habits quick progress
                    if habitsTotal > 0 {
                        habitQuickBar
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .sectionAppear(delay: 0.25)
                    }

                    // Subscription awareness
                    if activeSubCount > 0 {
                        subscriptionQuickBar
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Active Challenges — show ongoing challenges inline
                    if !activeChallenges.isEmpty {
                        activeChallengesCard
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Budget snapshot — show top budget categories
                    if !budgetProgress.isEmpty {
                        budgetSnapshotCard
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Savings goals progress
                    if !savingsGoals.isEmpty {
                        savingsSnapshotCard
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Achievement streaks + badge count
                    if !activeStreaks.isEmpty || earnedBadgeCount > 0 {
                        achievementSnapshotCard
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    // Smart Nudges (capped by stage.maxNudges in the engine)
                    if !nudges.isEmpty {
                        nudgesSection
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }

                    // Swipeable Hero Cards — filtered to user's focus pillars
                    // in early stages, all pillars once stage >= .insights
                    heroSection

                    // Contextual Feed
                    feedSection
                        .padding(.top, 16)
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                }
            }
            .background(NC.bgBase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    greetingHeader
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { showProfile = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "person.crop.circle")
                                .font(.title3)
                                .foregroundStyle(profileStore.info.isComplete ? .secondary : NC.teal)
                            if profileStore.info.pendingCount > 0 {
                                Circle()
                                    .fill(NC.teal)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -2)
                            }
                        }
                    }
                    .accessibilityLabel(profileStore.info.isComplete ? "Profile" : "Complete your profile")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    // Adaptive "More" menu — replaces the 8-button Quick Action
                    // grid. Items are gated by learning stage so early users
                    // don't see features that aren't useful yet.
                    Menu {
                        Button { Haptic.light(); showMood = true } label: {
                            Label("Log Mood", systemImage: "face.smiling")
                        }

                        if learningStage.allowsLifeCoach {
                            Button { Haptic.light(); showCoach = true } label: {
                                Label("Ask Coach", systemImage: "brain.head.profile")
                            }
                        }

                        if learningStage.allowsGoals {
                            Button { Haptic.light(); showGoals = true } label: {
                                Label("Goals", systemImage: "target")
                            }
                            Button { Haptic.light(); showAchievements = true } label: {
                                Label("Achievements", systemImage: "trophy.fill")
                            }
                        }

                        Divider()

                        Button { Haptic.light(); showExportSheet = true } label: {
                            Label("Export Data", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .accessibilityLabel("More")
                    }
                }
            }
            .refreshable { vm.load(); await refreshAdaptive() }
        }
        .onAppear {
            vm.load()
            Task {
                await authAlert.check()
                await refreshAdaptive()
                await HabitAutoTracker.shared.evaluate()
                nudges = await NudgeEngine.shared.generateNudges()
                _ = await AchievementEngine.shared.evaluateToday()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task {
                await authAlert.check()
                await HabitAutoTracker.shared.evaluate()
                await refreshAdaptive()
            }
        }
        .onChange(of: store.transactions.count) { vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openFoodLog"))) { _ in
            showFoodLog = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("openHeatmap"))) { _ in
            showHeatmap = true
        }
        .sheet(isPresented: $showExportSheet) {
            DataExportView()
        }
        .sheet(isPresented: $showGoals) {
            GoalsView()
        }
        .sheet(isPresented: $showProfile) {
            ProfileSetupSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFoodLog) {
            FoodLogView()
                .onDisappear { vm.load() }
        }
        .sheet(isPresented: $showAchievements) {
            AchievementsView()
        }
        .sheet(isPresented: $showMood) {
            MoodCheckInView()
        }
        .overlay(alignment: .bottomTrailing) {
            AnimatedCoachButton { showCoach = true }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
        }
        .sheet(isPresented: $showCoach) {
            LifeCoachView()
        }
        .sheet(isPresented: $showHeatmap) {
            LocationHeatmapView()
        }
        .sheet(item: $pendingEntryToComplete) { entry in
            QuickFoodLogSheet(pendingEntry: entry)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .onDisappear { vm.load() }
        }
        .sheet(isPresented: $showHabits) {
            HabitTrackerView()
                .onDisappear { Task { await refreshAdaptive() } }
        }
        .sheet(isPresented: $showSubscriptions) {
            SubscriptionManagerView()
        }
        .sheet(isPresented: $showChallenges) {
            ChallengesView()
                .onDisappear { Task { await refreshAdaptive() } }
        }
        .sheet(isPresented: $showBudget) {
            BudgetView()
                .onDisappear { Task { await refreshAdaptive() } }
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = profileStore.info.name?.split(separator: " ").first.map(String.init) ?? ""
        let timeGreeting: String = {
            switch hour {
            case 5..<12: return "Good morning"
            case 12..<17: return "Good afternoon"
            case 17..<22: return "Good evening"
            default: return "Good night"
            }
        }()

        return HStack(spacing: 0) {
            if firstName.isEmpty {
                Text(timeGreeting)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
            } else {
                Text("\(timeGreeting), ")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.secondary)
                Text(firstName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [NC.teal, Color(hex: "#6366F1")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        }
    }

    // MARK: - Mood Quick Row

    @ViewBuilder
    private var moodQuickRow: some View {
        if vm.todayMood == nil {
            Button { showMood = true } label: {
                HStack(spacing: 12) {
                    Text("How are you feeling?")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(MoodStore.MoodLevel.allCases, id: \.rawValue) { mood in
                            Text(mood.emoji)
                                .font(.title3)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

            }
            .buttonStyle(.plain)
        } else if let mood = vm.todayMood {
            Button { showMood = true } label: {
                HStack(spacing: 10) {
                    Text(mood.emoji)
                        .font(.title2)
                    Text("Feeling \(mood.label.lowercased())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Update")
                        .font(.caption.bold())
                        .foregroundStyle(NC.teal)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Habit Quick Bar

    private var habitQuickBar: some View {
        Button {
            Haptic.light()
            showHabits = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(habitsDone == habitsTotal ? .green : .teal)

                VStack(alignment: .leading, spacing: 2) {
                    Text(habitsDone == habitsTotal ? "All habits done!" : "Habits")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(habitsDone)/\(habitsTotal) completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Mini progress bar
                GeometryReader { geo in
                    let pct = habitsTotal > 0 ? CGFloat(habitsDone) / CGFloat(habitsTotal) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.teal.opacity(0.15))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(habitsDone == habitsTotal ? Color.green : Color.teal)
                            .frame(width: geo.size.width * pct)
                    }
                }
                .frame(width: 60, height: 6)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscription Quick Bar

    private var subscriptionQuickBar: some View {
        Button {
            Haptic.light()
            showSubscriptions = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "repeat.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color(hex: "#EC4899"))

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(activeSubCount) Subscription\(activeSubCount == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("\(NC.money(subMonthlyTotal))/month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        }
        .buttonStyle(.plain)
    }

    // MARK: - Active Challenges Card

    private var activeChallengesCard: some View {
        Button {
            Haptic.light()
            showChallenges = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("Active Challenges")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("\(activeChallenges.count)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.12), in: Capsule())
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ForEach(activeChallenges.prefix(2), id: \.id) { challenge in
                    HStack(spacing: 10) {
                        Image(systemName: challenge.type.icon)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(width: 24, height: 24)
                            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(challenge.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(Int(challenge.currentValue))/\(Int(challenge.targetValue)) \(challenge.type.unit)")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Mini progress ring
                        let pct = challenge.targetValue > 0
                            ? min(Double(challenge.currentValue) / Double(challenge.targetValue), 1.0)
                            : 0
                        ZStack {
                            Circle()
                                .stroke(Color.orange.opacity(0.15), lineWidth: 3)
                                .frame(width: 28, height: 28)
                            Circle()
                                .trim(from: 0, to: pct)
                                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 28, height: 28)
                                .rotationEffect(.degrees(-90))
                            Text("\(Int(pct * 100))%")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(14)
            .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        }
        .buttonStyle(.plain)
    }

    // MARK: - Budget Snapshot Card

    private var budgetSnapshotCard: some View {
        Button {
            Haptic.light()
            showBudget = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .foregroundStyle(NC.teal)
                    Text("Budget")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ForEach(budgetProgress.prefix(3), id: \.id) { bp in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bp.category)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("\(NC.money(bp.spent)) of \(NC.money(bp.limit))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Progress bar
                        GeometryReader { geo in
                            let pct = min(bp.percentage, 1.2)
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.gray.opacity(0.12))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(bp.isOverBudget ? Color.red : (bp.percentage > 0.75 ? Color.yellow : NC.teal))
                                    .frame(width: geo.size.width * min(CGFloat(pct), 1.0))
                            }
                        }
                        .frame(width: 80, height: 6)

                        Text("\(Int(bp.percentage * 100))%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(bp.isOverBudget ? .red : .secondary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            .padding(14)
            .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        }
        .buttonStyle(.plain)
    }

    // MARK: - Savings Snapshot Card

    private var savingsSnapshotCard: some View {
        Button {
            Haptic.light()
            showGoals = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "banknote.fill")
                        .foregroundStyle(.green)
                    Text("Savings Goals")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                ForEach(savingsGoals.prefix(2), id: \.goal.id) { sp in
                    HStack(spacing: 10) {
                        Image(systemName: sp.goal.icon)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .frame(width: 24, height: 24)
                            .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(sp.goal.name)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(NC.money(sp.currentSaved)) of \(NC.money(sp.goal.targetAmount))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Status badge
                        Text(sp.isOnTrack ? "On Track" : "Behind")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(sp.isOnTrack ? .green : .orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((sp.isOnTrack ? Color.green : Color.orange).opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(14)
            .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        }
        .buttonStyle(.plain)
    }

    // MARK: - Achievement Snapshot Card

    private var achievementSnapshotCard: some View {
        Button {
            Haptic.light()
            showAchievements = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "trophy.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    if !activeStreaks.isEmpty {
                        let best = activeStreaks.max(by: { $0.currentDays < $1.currentDays })!
                        Text("\(best.type.rawValue.replacingOccurrences(of: "_", with: " ").capitalized) streak: \(best.currentDays)d")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    } else {
                        Text("Achievements")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }

                    if earnedBadgeCount > 0 {
                        Text("\(earnedBadgeCount) badge\(earnedBadgeCount == 1 ? "" : "s") earned")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Streak flames for active streaks
                HStack(spacing: 3) {
                    ForEach(Array(activeStreaks.prefix(3).enumerated()), id: \.offset) { _, streak in
                        HStack(spacing: 1) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                            Text("\(streak.currentDays)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Actions

    private var quickActionsRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                QuickActionButton(icon: "face.smiling.inverse", label: "Mood", color: .purple) {
                    Haptic.light(); showMood = true
                }
                QuickActionButton(icon: "brain.head.profile", label: "Coach", color: NC.teal) {
                    Haptic.light(); showCoach = true
                }
                QuickActionButton(icon: "trophy.fill", label: "Badges", color: .orange) {
                    Haptic.light(); showAchievements = true
                }
                QuickActionButton(icon: "target", label: "Goals", color: .pink) {
                    Haptic.light(); showGoals = true
                }
            }
        }
    }

    // MARK: - Nudges Section

    private var nudgesSection: some View {
        VStack(spacing: 8) {
            ForEach(nudges) { nudge in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                            .fill(nudgeColor(nudge.color).opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: nudge.icon)
                            .font(.caption)
                            .foregroundStyle(nudgeColor(nudge.color))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nudge.title)
                            .font(.caption.bold())
                        Text(nudge.body)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if let action = nudge.actionLabel {
                        Button {
                            handleNudgeAction(nudge)
                        } label: {
                            Text(action)
                                .font(.caption2.bold())
                                .foregroundStyle(nudgeColor(nudge.color))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(nudgeColor(nudge.color).opacity(0.1), in: Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(nudgeColor(nudge.color).opacity(0.04), in: RoundedRectangle(cornerRadius: NC.cardRadius))
            }
        }
    }

    private func nudgeColor(_ color: String) -> Color {
        switch color {
        case "teal": return NC.teal
        case "pink": return .pink
        case "food": return NC.food
        case "spend": return NC.spend
        case "warning": return NC.warning
        default: return .blue
        }
    }

    private func handleNudgeAction(_ nudge: NudgeEngine.Nudge) {
        switch nudge.type {
        case .mealReminder: showFoodLog = true
        default: break
        }
    }

    // MARK: - Re-Auth Banner

    private var reAuthBanner: some View {
        VStack(spacing: 8) {
            ForEach(authAlert.issues, id: \.service) { issue in
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(issue.service) needs attention")
                            .font(.subheadline.bold())
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        issue.action()
                    } label: {
                        Text("Fix")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(.orange, in: Capsule())
                    }
                }
                .padding(NC.cardRadius)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.cardRadius))
            }
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 12) {
            TabView(selection: $activePage) {
                WealthHeroCard(
                    totalSpend: vm.totalSpend,
                    totalIncome: vm.totalIncome,
                    symbol: vm.primaryCurrencySymbol
                )
                .tag(DashboardPage.wealth)

                HealthHeroCard(
                    steps: vm.dailySteps,
                    sleepHours: vm.sleepHours,
                    activeCalories: vm.activeCalories,
                    restingHR: vm.restingHR,
                    streak: vm.workoutStreak,
                    workoutsPerWeek: vm.workoutsPerWeek
                )
                .tag(DashboardPage.health)

                InsightsHeroCard(count: vm.insights.count, topInsight: vm.insights.first)
                .tag(DashboardPage.insights)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 180)
            .animation(.easeInOut(duration: 0.25), value: activePage)

            // Colored page dots
            PageDots(activePage: $activePage)
        }
        .padding(.horizontal)
    }

    // MARK: - Feed Section

    @ViewBuilder
    private var feedSection: some View {
        switch activePage {
        case .wealth:
            wealthFeed
        case .health:
            healthFeed
        case .insights:
            insightsFeed
        }
    }

    // MARK: - Wealth Feed

    private var wealthFeed: some View {
        VStack(spacing: 14) {
            if vm.isEmpty {
                EmptyStateView()
            } else {
                CategoryChartCard(store: store, currencySymbol: vm.primaryCurrencySymbol)
                if !vm.recentTransactions.isEmpty {
                    RecentActivityCard(title: "Recent Transactions", transactions: vm.recentTransactions)
                }
            }
        }
    }

    // MARK: - Health Feed

    private var healthFeed: some View {
        VStack(spacing: 14) {
            if vm.dailySteps == 0 && vm.sleepHours == 0 && vm.workoutStreak == 0 && vm.activeCalories == 0 {
                FeedEmptyState(
                    icon: "heart.fill",
                    color: .pink,
                    title: "No Health Data Yet",
                    subtitle: "Health data will appear here as your wearable syncs with Apple Health."
                )
            } else {
                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    HealthStatCard(icon: "shoeprints.fill", label: "Steps Today", value: formatSteps(vm.dailySteps), color: .green)
                    HealthStatCard(icon: "bolt.fill", label: "Active Cal", value: vm.activeCalories > 0 ? "\(vm.activeCalories)" : "--", color: .orange)
                    HealthStatCard(icon: "moon.zzz.fill", label: "Last Sleep", value: vm.sleepHours > 0 ? String(format: "%.1fh", vm.sleepHours) : "--", color: .indigo)
                    HealthStatCard(icon: "heart.fill", label: "Resting HR", value: vm.restingHR > 0 ? "\(vm.restingHR) bpm" : "--", color: .red)
                    HealthStatCard(icon: "flame.fill", label: "Streak", value: vm.workoutStreak > 0 ? "\(vm.workoutStreak) days" : "--", color: .orange)
                    HealthStatCard(icon: "figure.run", label: "Workouts", value: vm.workoutsPerWeek > 0 ? String(format: "%.0f/wk", vm.workoutsPerWeek) : "--", color: .pink)
                }

                // Health insights
                let healthInsights = vm.insights.filter { $0.category == "health" }
                if !healthInsights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Health Insights")
                            .font(.headline)
                        ForEach(healthInsights.prefix(5)) { insight in
                            CompactInsightRow(insight: insight)
                        }
                    }
                    .card()
                }
            }
        }
    }

    // MARK: - Insights Feed

    private var insightsFeed: some View {
        VStack(spacing: 12) {
            if vm.insights.isEmpty {
                FeedEmptyState(
                    icon: "lightbulb.fill",
                    color: .orange,
                    title: "No Insights Yet",
                    subtitle: "As you sync transactions and move around, insights will appear here."
                )
            } else {
                ForEach(vm.insights) { insight in
                    InsightCard(insight: insight) {
                        withAnimation { vm.dismissInsight(insight) }
                    }
                }
            }
        }
    }

    private func formatSteps(_ steps: Int) -> String {
        if steps >= 1000 { return String(format: "%.1fk", Double(steps) / 1000.0) }
        return steps > 0 ? "\(steps)" : "--"
    }

    // MARK: - Adaptive State Refresh

    /// Loads the user's learning stage, focus, days-until-next-stage, and
    /// today's pulse in parallel. Called on appear and on foreground.
    private func refreshAdaptive() async {
        async let stage = AppLearningStage.shared.currentStage
        async let focus = AppLearningStage.shared.userFocus
        async let days = AppLearningStage.shared.daysUntilNextStage
        async let pulse = TodayPulseEngine.shared.generate()

        self.learningStage = await stage
        self.userFocus = await focus
        self.daysUntilNextStage = await days
        self.todayPulse = await pulse

        // Cross-pillar data for dashboard cards
        let progress = await HabitStore.shared.todayProgress()
        self.habitsDone = progress.completed
        self.habitsTotal = progress.total

        let subs = await SubscriptionManager.shared.allSubscriptions()
        self.activeSubCount = subs.filter(\.isActive).count
        self.subMonthlyTotal = await SubscriptionManager.shared.monthlyTotal()

        // Active challenges — refresh progress, then load
        await ChallengeStore.shared.updateProgress()
        self.activeChallenges = await ChallengeStore.shared.activeChallenges()

        // Budget progress
        self.budgetProgress = await BudgetStore.shared.progressForAll()

        // Savings goals
        self.savingsGoals = await SavingsGoalStore.shared.progressForAll()
            .filter { !$0.goal.isCompleted }

        // Achievement streaks + badge count
        self.activeStreaks = await AchievementEngine.shared.activeStreaks()
        self.earnedBadgeCount = await AchievementEngine.shared.allAchievements().count
    }
}

// MARK: - Today's Pulse Card

/// The new dashboard hero — a single synthesized summary replacing the
/// 8-button Quick Action grid. Research-aligned: one glanceable insight
/// across all pillars, observation framing (not judgment).
private struct TodayPulseCard: View {
    let pulse: TodayPulseEngine.TodayPulse
    let stage: AppLearningStage.Stage
    let daysUntilNextStage: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(toneColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: pulse.icon)
                        .font(.subheadline)
                        .foregroundStyle(toneColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(pulse.headline)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let detail = pulse.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()
            }

            // Source chips — show which signals built this pulse, so users
            // can trust where the synthesis came from (confidence indicator).
            if !pulse.fragments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(pulse.fragments.enumerated()), id: \.offset) { _, fragment in
                            HStack(spacing: 4) {
                                Image(systemName: fragment.icon)
                                    .font(.system(size: 10))
                                Text(fragment.text)
                                    .font(.caption2.weight(.medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .foregroundStyle(.secondary)
                            .background(NC.bgElevated, in: Capsule())
                        }
                    }
                }
            }

            // Stage progress — hidden in stage 4 (Intelligence)
            if stage != .intelligence {
                HStack(spacing: 6) {
                    Image(systemName: stage.icon)
                        .font(.caption2)
                    Text("\(stage.displayName)")
                        .font(.caption2.weight(.medium))
                    if daysUntilNextStage > 0 {
                        Text("· \(daysUntilNextStage) day\(daysUntilNextStage == 1 ? "" : "s") until next")
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's pulse: \(pulse.headline)")
        .accessibilityHint(pulse.detail ?? "")
    }

    private var toneColor: Color {
        switch pulse.tone {
        case .positive:       return .green
        case .neutral:        return NC.teal
        case .needsAttention: return NC.warning
        case .warmingUp:      return .blue
        }
    }
}

// MARK: - Page Dots

private struct PageDots: View {
    @Binding var activePage: DashboardPage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(DashboardPage.allCases, id: \.rawValue) { page in
                let isActive = page == activePage
                Circle()
                    .fill(isActive ? page.color : page.color.opacity(0.25))
                    .frame(width: isActive ? 8 : 6, height: isActive ? 8 : 6)
                    .animation(.spring(response: 0.3), value: activePage)
            }
        }
    }
}

// MARK: - Hero Cards

private struct WealthHeroCard: View {
    let totalSpend: Double
    let totalIncome: Double
    let symbol: String

    var body: some View {
        VStack(spacing: 6) {
            Text(monthName.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.5)

            Text("\(symbol)\(totalSpend, specifier: "%.2f")")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text("spent this month")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))

            if totalIncome > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption2)
                    Text("+\(symbol)\(totalIncome, specifier: "%.2f") earned")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.green.opacity(0.9))
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "#0C1A2A"), Color(hex: "#0A2D2D"), NC.teal.opacity(0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: NC.heroRadius, style: .continuous))
    }

    private var monthName: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: Date())
    }
}

private struct HealthHeroCard: View {
    let steps: Int
    let sleepHours: Double
    let activeCalories: Int
    let restingHR: Int
    let streak: Int
    let workoutsPerWeek: Double

    private var hasData: Bool {
        steps > 0 || sleepHours > 0 || activeCalories > 0 || restingHR > 0
    }

    var body: some View {
        VStack(spacing: 8) {
            Text("YOUR HEALTH")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.5)

            if hasData {
                // Top row: steps + calories (big numbers)
                HStack(spacing: 24) {
                    if steps > 0 {
                        healthStat(icon: "shoeprints.fill",
                                   value: steps >= 1000 ? String(format: "%.1fk", Double(steps)/1000) : "\(steps)",
                                   label: "steps")
                    }
                    if activeCalories > 0 {
                        healthStat(icon: "bolt.fill",
                                   value: activeCalories >= 1000 ? String(format: "%.1fk", Double(activeCalories)/1000) : "\(activeCalories)",
                                   label: "kcal")
                    }
                    if sleepHours > 0 {
                        healthStat(icon: "moon.zzz.fill",
                                   value: String(format: "%.1f", sleepHours),
                                   label: "hrs sleep")
                    }
                }

                // Bottom row: HR + streak (smaller)
                if restingHR > 0 || streak > 0 {
                    HStack(spacing: 20) {
                        if restingHR > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red.opacity(0.8))
                                Text("\(restingHR) bpm")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }
                        if streak > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "flame.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange.opacity(0.8))
                                Text("\(streak)-day streak")
                                    .font(.caption.bold())
                            }
                            .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .padding(.top, 2)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 32))
                    Text("Connect Health")
                        .font(.headline)
                    Text("Swipe down for details")
                        .font(.caption)
                        .opacity(0.6)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.55, green: 0.1, blue: 0.25), Color(red: 0.35, green: 0.08, blue: 0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: NC.heroRadius, style: .continuous))
        .shadow(color: Color.pink.opacity(0.2), radius: 12, y: 6)
    }

    private func healthStat(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.title3)
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption2)
                .opacity(0.7)
        }
        .foregroundStyle(.white)
    }
}

private struct InsightsHeroCard: View {
    let count: Int
    let topInsight: Insight?

    var body: some View {
        VStack(spacing: 8) {
            Text("INSIGHTS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.5)

            if let top = topInsight {
                Image(systemName: top.type.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(.white)

                Text(top.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)

                if count > 1 {
                    Text("+\(count - 1) more")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                Text("No insights yet")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Keep using the app")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.6, green: 0.35, blue: 0.05), Color(red: 0.45, green: 0.2, blue: 0.02)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: NC.heroRadius, style: .continuous))
        .shadow(color: Color.orange.opacity(0.2), radius: 12, y: 6)
    }
}

// MARK: - Daily Macro Card

private struct DailyMacroCard: View {
    let calories: Int
    let macros: Macros

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Today's Nutrition")
                    .font(.headline)
                Spacer()
                Text("\(calories) cal")
                    .font(.title3.bold())
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 0) {
                macroColumn(label: "Protein", grams: macros.protein, color: .red)
                macroColumn(label: "Carbs", grams: macros.carbs, color: .blue)
                macroColumn(label: "Fat", grams: macros.fat, color: .yellow)
                macroColumn(label: "Fiber", grams: macros.fiber, color: .green)
            }
        }
        .card()
    }

    private func macroColumn(label: String, grams: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(String(format: "%.0f", grams))
                .font(.title3.bold())
            Text("g")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label)
                .font(.system(size: 10).bold())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.iconRadius))
        .padding(.horizontal, 2)
    }
}

// MARK: - Food Entry Row

private struct FoodEntryRow: View {
    let entry: FoodStore.FoodLogEntry

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: mealIcon)
                    .font(.caption)
                    .foregroundStyle(mealColor)
                    .frame(width: 32, height: 32)
                    .background(mealColor.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.mealType.capitalized)
                        .font(.caption.bold())
                    if !entry.items.isEmpty {
                        Text(entry.items.map { $0.name }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    if let cal = entry.totalCaloriesEstimate, cal > 0 {
                        Text("\(cal) cal")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                    }
                    Text(sourceLabel)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }

            // Inline macros
            if let m = entry.totalMacros, m != .zero {
                HStack(spacing: 6) {
                    miniMacro("P", String(format: "%.0f", m.protein), .red)
                    miniMacro("C", String(format: "%.0f", m.carbs), .blue)
                    miniMacro("F", String(format: "%.0f", m.fat), .yellow)
                    miniMacro("Fb", String(format: "%.0f", m.fiber), .green)
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func miniMacro(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9).bold())
                .foregroundStyle(color)
            Text("\(value)g")
                .font(.system(size: 9))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.08), in: Capsule())
    }

    private var mealIcon: String {
        switch entry.mealType {
        case "breakfast": return "sun.horizon.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.fill"
        default: return "cup.and.saucer.fill"
        }
    }

    private var mealColor: Color {
        switch entry.mealType {
        case "breakfast": return .orange
        case "lunch": return .yellow
        case "dinner": return .indigo
        default: return .mint
        }
    }

    private var sourceLabel: String {
        switch entry.source {
        case .manual: return "Manual"
        case .emailOrder: return "Order"
        case .locationPrompt: return "GPS"
        case .stapleSuggestion: return "Staple"
        case .autoDetected: return "Smart"
        }
    }
}

// MARK: - Health Stat Card

private struct HealthStatCard: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .card(padding: 0)
    }
}

// MARK: - Compact Insight Row

private struct CompactInsightRow: View {
    let insight: Insight

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: insight.type.icon)
                .font(.caption)
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(insight.title)
                    .font(.caption.bold())
                Text(insight.body)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var iconColor: Color {
        switch insight.priority {
        case .urgent: return NC.spend
        case .high: return NC.warning
        case .medium: return NC.teal
        case .low: return .secondary
        }
    }
}

// MARK: - Insight Card (Full)

struct InsightCard: View {
    let insight: Insight
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: insight.type.icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if insight.priority >= .high {
                        Text(insight.priority.label)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priorityColor, in: Capsule())
                    }
                    Spacer()
                    Text(timeAgo(insight.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(insight.title)
                    .font(.subheadline.bold())

                Text(insight.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            Button { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
                    .background(NC.bgElevated, in: Circle())
            }
        }
        .padding(14)
        .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius))

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

    private func timeAgo(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Feed Empty State

private struct FeedEmptyState: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(color)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .card()
    }
}

// MARK: - Category Chart

private struct CategoryChartCard: View {
    let store: TransactionStore
    let currencySymbol: String

    @State private var selectedPeriod: SpendPeriod = .month

    private var data: [CategorySpend] {
        store.categoryBreakdown(for: selectedPeriod).map {
            CategorySpend(categoryName: $0.category, amount: $0.amount, currencySymbol: currencySymbol)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Spending Breakdown")
                    .font(.headline)
                Spacer()
            }

            // Period filter pills
            HStack(spacing: 6) {
                ForEach(SpendPeriod.allCases, id: \.self) { period in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedPeriod = period }
                    } label: {
                        Text(period.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedPeriod == period
                                    ? AnyShapeStyle(NC.teal)
                                    : AnyShapeStyle(NC.bgElevated),
                                in: Capsule()
                            )
                    }
                }
                Spacer()
            }

            if data.isEmpty {
                Text("No spending \(selectedPeriod == .today ? "today" : selectedPeriod == .week ? "this week" : "this month")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                Chart(data) { item in
                    SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.6), angularInset: 2)
                        .foregroundStyle(NC.color(for: item.categoryName))
                        .cornerRadius(6)
                }
                .frame(height: 180)

                VStack(spacing: 8) {
                    ForEach(data) { item in
                        let total = data.reduce(0) { $0 + $1.amount }
                        let pct = total > 0 ? (item.amount / total * 100) : 0
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(NC.color(for: item.categoryName))
                                .frame(width: 4, height: 28)
                            Image(systemName: NC.icon(for: item.categoryName))
                                .font(.caption)
                                .foregroundStyle(NC.color(for: item.categoryName))
                                .frame(width: 20)
                            Text(item.categoryName).font(.subheadline)
                            Spacer()
                            Text("\(pct, specifier: "%.0f")%")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                            Text(item.formattedAmount)
                                .font(.subheadline).fontWeight(.semibold)
                                .frame(width: 80, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .card()
    }
}

// MARK: - Ghost Subscriptions

// MARK: - Life Score Card

private struct LifeScoreCard: View {
    let score: LifeScoreEngine.DailyScore
    let goalProgress: [GoalProgress]
    let onGoalsTap: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            // Score ring + number
            HStack(spacing: 16) {
                // Animated ring
                ZStack {
                    Circle()
                        .stroke(NC.bgElevated, lineWidth: 6)
                        .frame(width: 64, height: 64)
                    Circle()
                        .trim(from: 0, to: Double(score.total) / 100.0)
                        .stroke(scoreColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    Text("\(score.total)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Life Score")
                        .font(.headline)
                    Text(scoreLabel)
                        .font(.caption)
                        .foregroundStyle(scoreColor)
                }

                Spacer()

                // Goals shortcut
                Button(action: onGoalsTap) {
                    VStack(spacing: 2) {
                        Image(systemName: "target")
                            .font(.title3)
                        Text("Goals")
                            .font(.caption2)
                    }
                    .foregroundStyle(NC.teal)
                    .frame(width: 52, height: 52)
                    .background(NC.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.iconRadius))
                }
            }

            // Pillar breakdown bar
            HStack(spacing: 8) {
                PillarPill(label: "Wealth", score: score.wealth, color: NC.teal)
                PillarPill(label: "Health", score: score.health, color: .pink)
                PillarPill(label: "Food", score: score.food, color: NC.food)
                PillarPill(label: "Routine", score: score.routine, color: .blue)
            }

            // Goal progress (top 3)
            if !goalProgress.isEmpty {
                Divider()
                VStack(spacing: 8) {
                    ForEach(goalProgress.prefix(3)) { item in
                        MiniGoalRow(item: item)
                    }
                    if goalProgress.count > 3 {
                        Button(action: onGoalsTap) {
                            Text("View all \(goalProgress.count) goals")
                                .font(.caption)
                                .foregroundStyle(NC.teal)
                        }
                    }
                }
            }
        }
        .padding(NC.hPad)
        .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    private var scoreColor: Color {
        if score.total >= 80 { return .green }
        if score.total >= 60 { return NC.teal }
        if score.total >= 40 { return .orange }
        return NC.spend
    }

    private var scoreLabel: String {
        if score.total >= 80 { return "Excellent — keep it up!" }
        if score.total >= 60 { return "Good — room to improve" }
        if score.total >= 40 { return "Fair — let's work on it" }
        return "Needs attention"
    }
}

private struct PillarPill: View {
    let label: String; let score: Int; let color: Color
    var body: some View {
        VStack(spacing: 4) {
            Text("\(score)")
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(NC.bgElevated)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geo.size.width * Double(score) / 100.0, height: 3)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MiniGoalRow: View {
    let item: GoalProgress
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.goal.type.icon)
                .font(.caption)
                .foregroundStyle(pillarColor)
                .frame(width: 20)
            Text(item.goal.type.title)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            // Mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(NC.bgElevated)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(item.isOnTrack ? .green : .orange)
                        .frame(width: min(geo.size.width, geo.size.width * item.progress), height: 4)
                }
            }
            .frame(width: 60, height: 4)
            Text("\(Int(min(item.progress, 1.0) * 100))%")
                .font(.caption2.bold())
                .foregroundStyle(item.isOnTrack ? .green : .orange)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var pillarColor: Color {
        switch item.goal.type.pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "food": return NC.food
        default: return .blue
        }
    }
}

// MARK: - Recent Activity

private struct RecentActivityCard: View {
    let title: String
    let transactions: [TransactionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            ForEach(transactions.prefix(5)) { txn in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(NC.color(for: txn.category).opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: NC.icon(for: txn.category))
                            .font(.system(size: 14))
                            .foregroundStyle(NC.color(for: txn.category))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(txn.merchant).font(.subheadline).fontWeight(.medium)
                        Text(txn.date).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(txn.formattedAmount)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(txn.isCredit ? NC.income : .primary)
                }
            }
        }
        .card()
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(NC.teal.opacity(0.1)).frame(width: 100, height: 100)
                Image(systemName: "compass.drawing")
                    .font(.system(size: 40, weight: .light)).foregroundStyle(NC.teal)
            }
            VStack(spacing: 8) {
                Text("Welcome to NodeCompass").font(.title3).fontWeight(.bold)
                Text("Connect your bank or email to start\ntracking your spending automatically.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(32)
    }
}

// MARK: - Quick Action Button

private struct QuickActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))

        }
        .buttonStyle(.plain)
    }
}

#Preview {
    DashboardView()
        .environmentObject(TransactionStore.shared)
}
