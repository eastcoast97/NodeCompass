import Foundation

/// "What If" projection engine.
/// Simulates the impact of behavioral changes on spending, savings, health, and score.
/// e.g. "If you cut dining out by 50%, you'd save $600/month"
struct WhatIfSimulator {

    // MARK: - Models

    struct Scenario: Identifiable {
        let id = UUID().uuidString
        let type: ScenarioType
        let title: String
        let description: String
        let icon: String
        let currentValue: Double
        let projectedValue: Double
        let monthlySavings: Double
        let yearlySavings: Double
        let scoreImpact: Int         // +/- points on life score
        let pillar: String
    }

    enum ScenarioType: String, CaseIterable {
        case cutDiningOut            // Reduce restaurant spending
        case cancelGhostSubs         // Cancel forgotten subscriptions
        case cookMoreAtHome          // Replace eating out with cooking
        case walkMore                // Increase daily steps
        case sleepBetter             // Improve sleep to 7-8 hrs
        case workoutMore             // Add workout days per week
        case reduceShopping          // Cut impulse shopping
        case increaseIncome          // Side income projection

        var title: String {
            switch self {
            case .cutDiningOut: return "Cut Dining Out by 50%"
            case .cancelGhostSubs: return "Cancel Unused Subscriptions"
            case .cookMoreAtHome: return "Cook 5 Days a Week"
            case .walkMore: return "Walk 10K Steps Daily"
            case .sleepBetter: return "Sleep 7-8 Hours Nightly"
            case .workoutMore: return "Work Out 4x/Week"
            case .reduceShopping: return "Reduce Impulse Shopping"
            case .increaseIncome: return "Add Side Income"
            }
        }

        var icon: String {
            switch self {
            case .cutDiningOut: return "fork.knife"
            case .cancelGhostSubs: return "repeat.circle.fill"
            case .cookMoreAtHome: return "frying.pan.fill"
            case .walkMore: return "shoeprints.fill"
            case .sleepBetter: return "moon.zzz.fill"
            case .workoutMore: return "figure.run"
            case .reduceShopping: return "bag.fill"
            case .increaseIncome: return "plus.circle.fill"
            }
        }

        var pillar: String {
            switch self {
            case .cutDiningOut, .cancelGhostSubs, .reduceShopping, .increaseIncome: return "wealth"
            case .walkMore, .sleepBetter, .workoutMore: return "health"
            case .cookMoreAtHome: return "food"
            }
        }
    }

    // MARK: - Generate Scenarios

    static func generateScenarios() async -> [Scenario] {
        var scenarios: [Scenario] = []
        let cal = Calendar.current

        let store = await MainActor.run { TransactionStore.shared }
        let transactions = await MainActor.run { store.transactions }
        let monthlySpend = await MainActor.run { store.totalSpendThisMonth }
        let monthlyIncome = await MainActor.run { store.totalIncomeThisMonth }

        let health = HealthCollector.shared
        let steps = await health.todaySteps()
        let sleepHrs = await health.lastNightSleepHours()
        let workoutStats = await health.recentWorkoutStats()

        let dayOfMonth = cal.component(.day, from: Date())
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())?.count ?? 30

        // Project full month from current pace
        let projectedMonthlySpend = dayOfMonth > 0 ? monthlySpend / Double(dayOfMonth) * Double(daysInMonth) : monthlySpend

        // 1. Cut Dining Out
        let diningTxns = transactions.filter {
            cal.isDate($0.date, equalTo: Date(), toGranularity: .month) &&
            ($0.category == "Food & Dining" || $0.category == "Restaurants") &&
            $0.type.uppercased() == "DEBIT"
        }
        let diningSpend = diningTxns.reduce(0.0) { $0 + $1.amount }
        let projectedDining = dayOfMonth > 0 ? diningSpend / Double(dayOfMonth) * Double(daysInMonth) : diningSpend
        if projectedDining > 0 {
            let savings = projectedDining * 0.5
            scenarios.append(Scenario(
                type: .cutDiningOut,
                title: "Cut Dining Out by 50%",
                description: "You're on pace to spend \(NC.money(projectedDining)) on dining this month. Halving it saves \(NC.money(savings))/month.",
                icon: "fork.knife",
                currentValue: projectedDining,
                projectedValue: projectedDining * 0.5,
                monthlySavings: savings,
                yearlySavings: savings * 12,
                scoreImpact: 5,
                pillar: "wealth"
            ))
        }

        // 2. Cancel Ghost Subscriptions
        let ghostSubs = await MainActor.run { store.ghostSubscriptions }
        if !ghostSubs.isEmpty {
            let ghostTotal = ghostSubs.reduce(0.0) { $0 + $1.amount }
            scenarios.append(Scenario(
                type: .cancelGhostSubs,
                title: "Cancel \(ghostSubs.count) Unused Subscription\(ghostSubs.count == 1 ? "" : "s")",
                description: "We detected \(ghostSubs.count) potential ghost subscriptions totaling \(NC.money(ghostTotal))/month.",
                icon: "repeat.circle.fill",
                currentValue: ghostTotal,
                projectedValue: 0,
                monthlySavings: ghostTotal,
                yearlySavings: ghostTotal * 12,
                scoreImpact: 3,
                pillar: "wealth"
            ))
        }

        // 3. Cook More at Home
        let weekFoodEntries = await FoodStore.shared.entriesForWeek()
        let homeMeals = weekFoodEntries.filter { !$0.items.isEmpty && $0.source != .emailOrder }.count
        let totalWeekMeals = max(1, weekFoodEntries.filter { !$0.items.isEmpty }.count)
        let homeRatio = Double(homeMeals) / Double(totalWeekMeals)
        if homeRatio < 0.7 && projectedDining > 0 {
            let targetRatio = 0.7 // 5 out of 7 days
            let potentialSavings = projectedDining * (targetRatio - homeRatio)
            scenarios.append(Scenario(
                type: .cookMoreAtHome,
                title: "Cook 5 Days a Week",
                description: "Currently home-cooking \(Int(homeRatio * 100))% of meals. Reaching 70% could save \(NC.money(max(0, potentialSavings)))/month on dining.",
                icon: "frying.pan.fill",
                currentValue: homeRatio * 100,
                projectedValue: 70,
                monthlySavings: max(0, potentialSavings),
                yearlySavings: max(0, potentialSavings) * 12,
                scoreImpact: 8,
                pillar: "food"
            ))
        }

        // 4. Walk 10K Steps
        if steps < 10000 {
            let currentAvg = max(steps, 3000)
            scenarios.append(Scenario(
                type: .walkMore,
                title: "Walk 10,000 Steps Daily",
                description: "You're at \(steps.formatted()) steps today. Hitting 10K daily improves cardiovascular health and can boost your score by ~10 points.",
                icon: "shoeprints.fill",
                currentValue: Double(currentAvg),
                projectedValue: 10000,
                monthlySavings: 0,
                yearlySavings: 0,
                scoreImpact: 10,
                pillar: "health"
            ))
        }

        // 5. Sleep Better
        if sleepHrs > 0 && (sleepHrs < 7 || sleepHrs > 9) {
            scenarios.append(Scenario(
                type: .sleepBetter,
                title: "Sleep 7-8 Hours Nightly",
                description: "Last night: \(String(format: "%.1f", sleepHrs)) hrs. Consistent 7-8hr sleep improves energy, focus, and Life Score.",
                icon: "moon.zzz.fill",
                currentValue: sleepHrs,
                projectedValue: 7.5,
                monthlySavings: 0,
                yearlySavings: 0,
                scoreImpact: 12,
                pillar: "health"
            ))
        }

        // 6. Work Out More
        if workoutStats.perWeek < 4 {
            scenarios.append(Scenario(
                type: .workoutMore,
                title: "Work Out 4x/Week",
                description: "Currently at \(String(format: "%.1f", workoutStats.perWeek))x/week. Adding \(Int(4 - workoutStats.perWeek)) more sessions boosts health score significantly.",
                icon: "figure.run",
                currentValue: workoutStats.perWeek,
                projectedValue: 4,
                monthlySavings: 0,
                yearlySavings: 0,
                scoreImpact: 15,
                pillar: "health"
            ))
        }

        // 7. Reduce Shopping
        let shoppingTxns = transactions.filter {
            cal.isDate($0.date, equalTo: Date(), toGranularity: .month) &&
            $0.category == "Shopping" && $0.type.uppercased() == "DEBIT"
        }
        let shoppingSpend = shoppingTxns.reduce(0.0) { $0 + $1.amount }
        let projectedShopping = dayOfMonth > 0 ? shoppingSpend / Double(dayOfMonth) * Double(daysInMonth) : shoppingSpend
        if projectedShopping > projectedMonthlySpend * 0.15 { // Shopping > 15% of total
            let savings = projectedShopping * 0.3
            scenarios.append(Scenario(
                type: .reduceShopping,
                title: "Reduce Impulse Shopping",
                description: "Shopping is \(Int(projectedShopping / projectedMonthlySpend * 100))% of your spending. Cutting 30% saves \(NC.money(savings))/month.",
                icon: "bag.fill",
                currentValue: projectedShopping,
                projectedValue: projectedShopping * 0.7,
                monthlySavings: savings,
                yearlySavings: savings * 12,
                scoreImpact: 4,
                pillar: "wealth"
            ))
        }

        return scenarios.sorted { $0.scoreImpact > $1.scoreImpact }
    }
}
