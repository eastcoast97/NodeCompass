import Foundation

/// Tracks the user's "learning stage" — how mature their data is.
/// The UI progressively reveals features based on this stage to prevent
/// overwhelm on day 1 and to make the app feel smarter over time.
///
/// Philosophy:
/// - Day 1-2: Warming Up — minimal UI, no judgments, "still learning"
/// - Day 3-6: Tracking — basic stats, simple observations, no scores
/// - Day 7-20: Patterns — trends emerge, Life Score unlocks, goals available
/// - Day 21-59: Insights — correlations, nudges, predictions
/// - Day 60+: Intelligence — cross-source patterns, ghost subs, wrapped
///
/// Each stage unlocks features and adapts the dashboard to show
/// the most relevant information for that level of data maturity.
actor AppLearningStage {
    static let shared = AppLearningStage()

    enum Stage: Int, Codable, Comparable {
        case warmingUp = 0    // Day 1-2: Just setting up
        case tracking = 1     // Day 3-6: Basic data collection
        case patterns = 2     // Day 7-20: Trends emerging
        case insights = 3     // Day 21-59: Correlations and predictions
        case intelligence = 4 // Day 60+: Full cross-source intelligence

        static func < (lhs: Stage, rhs: Stage) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var displayName: String {
            switch self {
            case .warmingUp: return "Warming Up"
            case .tracking: return "Tracking"
            case .patterns: return "Finding Patterns"
            case .insights: return "Generating Insights"
            case .intelligence: return "Full Intelligence"
            }
        }

        /// Short, reassuring status message for the dashboard.
        var statusMessage: String {
            switch self {
            case .warmingUp:
                return "Getting to know you. Keep using the app as normal."
            case .tracking:
                return "Learning your daily patterns."
            case .patterns:
                return "Your trends are starting to emerge."
            case .insights:
                return "Finding connections across your data."
            case .intelligence:
                return "Your full life intelligence is active."
            }
        }

        /// Emoji-free status icon from SF Symbols.
        var icon: String {
            switch self {
            case .warmingUp:    return "sparkle.magnifyingglass"
            case .tracking:     return "chart.line.flattrend.xyaxis"
            case .patterns:     return "chart.line.uptrend.xyaxis"
            case .insights:     return "lightbulb.fill"
            case .intelligence: return "brain.head.profile"
            }
        }

        // MARK: - Feature Gates

        /// Is the Life Score mature enough to show? Hidden in early stages
        /// to avoid shaming users with no data.
        var showsLifeScore: Bool { self >= .patterns }

        /// Show only a neutral "Day X of tracking" badge instead of a score.
        var showsTrackingBadgeInsteadOfScore: Bool { self < .patterns }

        /// Are goals available? Requires baseline data.
        var allowsGoals: Bool { self >= .tracking }

        /// Are cross-source insights surfaced?
        var allowsCrossSourceInsights: Bool { self >= .insights }

        /// Is the Life Coach conversational AI available?
        var allowsLifeCoach: Bool { self >= .tracking }

        /// Should nudges be shown? Requires some baseline to be useful.
        var allowsNudges: Bool { self >= .tracking }

        /// Is ghost subscription detection reliable?
        var allowsGhostSubscriptions: Bool { self >= .insights }

        /// Max number of simultaneous nudges shown — grows with stage to
        /// avoid overwhelming new users.
        var maxNudges: Int {
            switch self {
            case .warmingUp:    return 0
            case .tracking:     return 1
            case .patterns:     return 2
            case .insights:     return 3
            case .intelligence: return 3
            }
        }

        /// Which dashboard pillars should be visible? In early stages,
        /// only the user's selected focus is shown. Later stages reveal all.
        func visiblePillars(userFocus: UserFocus) -> Set<DashboardPillar> {
            switch self {
            case .warmingUp, .tracking:
                return userFocus.initialPillars
            case .patterns:
                // Add one more pillar beyond initial focus
                return userFocus.initialPillars.union([.insights])
            case .insights, .intelligence:
                return Set(DashboardPillar.allCases)
            }
        }
    }

    enum UserFocus: String, Codable, CaseIterable {
        case wealth       // Primary focus on spending and savings
        case health       // Primary focus on activity and sleep
        case food         // Primary focus on meals and nutrition
        case everything   // Show all pillars from day 1

        var displayName: String {
            switch self {
            case .wealth:     return "Money"
            case .health:     return "Health"
            case .food:       return "Food"
            case .everything: return "Everything"
            }
        }

        var description: String {
            switch self {
            case .wealth:     return "Track spending, subscriptions, and savings"
            case .health:     return "Track activity, sleep, and workouts"
            case .food:       return "Track meals, cooking, and nutrition"
            case .everything: return "Show me all four pillars at once"
            }
        }

        var icon: String {
            switch self {
            case .wealth:     return "dollarsign.circle.fill"
            case .health:     return "heart.fill"
            case .food:       return "fork.knife"
            case .everything: return "square.grid.2x2.fill"
            }
        }

        /// Which pillars are visible for users who picked this focus
        /// in early stages.
        var initialPillars: Set<DashboardPillar> {
            switch self {
            case .wealth:     return [.wealth]
            case .health:     return [.health]
            case .food:       return [.food]
            case .everything: return Set(DashboardPillar.allCases)
            }
        }
    }

    enum DashboardPillar: String, CaseIterable, Codable {
        case wealth
        case health
        case food
        case insights
        case orders
    }

    // MARK: - State

    private struct State: Codable {
        var firstLaunchDate: Date
        var userFocus: UserFocus
        var manualStageOverride: Stage?  // Dev/testing override
    }

    private var state: State
    private let stateKey = "app_learning_state"

    private init() {
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            self.state = decoded
        } else {
            self.state = State(
                firstLaunchDate: Date(),
                userFocus: .everything,
                manualStageOverride: nil
            )
        }
    }

    // MARK: - Public API

    /// Current stage based on days since first launch.
    var currentStage: Stage {
        if let override = state.manualStageOverride { return override }
        let days = daysSinceFirstLaunch
        switch days {
        case 0..<3:   return .warmingUp
        case 3..<7:   return .tracking
        case 7..<21:  return .patterns
        case 21..<60: return .insights
        default:      return .intelligence
        }
    }

    /// Days since the user first launched the app.
    var daysSinceFirstLaunch: Int {
        let interval = Date().timeIntervalSince(state.firstLaunchDate)
        return max(0, Int(interval / 86400))
    }

    /// User's selected focus area (chosen during onboarding).
    var userFocus: UserFocus {
        state.userFocus
    }

    /// Mark the user's focus selection from onboarding.
    func setUserFocus(_ focus: UserFocus) {
        state.userFocus = focus
        save()
    }

    /// Mark the first launch — only applied if not already set.
    func initializeIfNeeded() {
        // firstLaunchDate is set in init; nothing to do unless we want to
        // distinguish between app install and first onboarding completion.
    }

    /// Dev/testing override to jump to a specific stage.
    func setStageOverride(_ stage: Stage?) {
        state.manualStageOverride = stage
        save()
    }

    /// Progress within the current stage (0.0 to 1.0). Useful for
    /// progress bars showing "days until next level."
    var progressInCurrentStage: Double {
        let days = daysSinceFirstLaunch
        switch currentStage {
        case .warmingUp:    return Double(days) / 3.0
        case .tracking:     return Double(days - 3) / 4.0
        case .patterns:     return Double(days - 7) / 14.0
        case .insights:     return Double(days - 21) / 39.0
        case .intelligence: return 1.0
        }
    }

    /// Days remaining until the next stage unlocks.
    var daysUntilNextStage: Int {
        let days = daysSinceFirstLaunch
        switch currentStage {
        case .warmingUp:    return max(0, 3 - days)
        case .tracking:     return max(0, 7 - days)
        case .patterns:     return max(0, 21 - days)
        case .insights:     return max(0, 60 - days)
        case .intelligence: return 0
        }
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: stateKey)
        }
    }

    /// Reset all learning state (e.g., on "reset onboarding").
    func reset() {
        state = State(
            firstLaunchDate: Date(),
            userFocus: .everything,
            manualStageOverride: nil
        )
        save()
    }
}
