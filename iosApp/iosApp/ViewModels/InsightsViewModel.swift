import SwiftUI

struct QuickStat {
    let label: String
    let value: String
    let color: Color
}

@MainActor
class InsightsViewModel: ObservableObject {
    @Published var insights: [Insight] = []
    @Published var isLoading: Bool = false
    @Published var profileSummaryLines: [String] = []
    @Published var quickStats: [QuickStat] = []
    @Published var profileLastUpdated: Date? = nil

    func load() {
        isLoading = true
        Task {
            let active = await PatternEngine.shared.activeInsights()
            insights = active
            isLoading = false
        }
    }

    func refresh() {
        isLoading = true
        Task {
            await PatternEngine.shared.runAnalysis()
            let active = await PatternEngine.shared.activeInsights()
            insights = active
            await loadProfile()
            isLoading = false
        }
    }

    func dismiss(_ insight: Insight) {
        Task {
            await PatternEngine.shared.dismiss(insight.id)
            insights.removeAll { $0.id == insight.id }
        }
    }

    // MARK: - Profile Summary Generation

    func loadProfile() async {
        let profile = await UserProfileStore.shared.currentProfile()
        profileLastUpdated = profile.lastUpdated

        var lines: [String] = []
        var stats: [QuickStat] = []

        // --- Spending Intelligence ---
        let totalMonthly = profile.spendingByCategory.values.reduce(0.0) { $0 + $1.totalThisMonth }

        if totalMonthly > 0 {
            // Top category
            if let topCat = profile.spendingByCategory.max(by: { $0.value.totalThisMonth < $1.value.totalThisMonth }) {
                let pct = Int((topCat.value.totalThisMonth / totalMonthly) * 100)
                lines.append("You spend the most on \(topCat.key) (\(pct)% of monthly spending)")
            }

            // Top merchant
            if let topMerchant = profile.topMerchants.sorted(by: { $0.totalSpent > $1.totalSpent }).first {
                lines.append("Your most visited place is \(topMerchant.merchant) (\(topMerchant.visitCount) visits, $\(Int(topMerchant.totalSpent)) total)")
            }

            // Month-over-month trend
            if let lastMonth = profile.spendingByCategory.values.first?.totalLastMonth, lastMonth > 0 {
                let totalLastMonth = profile.spendingByCategory.values.reduce(0.0) { $0 + $1.totalLastMonth }
                if totalLastMonth > 0 {
                    let change = ((totalMonthly - totalLastMonth) / totalLastMonth) * 100
                    if abs(change) > 5 {
                        let direction = change > 0 ? "up" : "down"
                        lines.append("Your spending is \(direction) \(Int(abs(change)))% compared to last month")
                    }
                }
            }

            stats.append(QuickStat(label: "Monthly", value: "$\(Int(totalMonthly))", color: NC.teal))
        }

        // --- Food Intelligence ---
        if profile.averageMealsPerDay > 0 {
            let mealsDesc = String(format: "%.1f", profile.averageMealsPerDay)
            lines.append("You average \(mealsDesc) meals per day")
        }

        if profile.foodDeliveryFrequency > 0 {
            let freq = String(format: "%.0f", profile.foodDeliveryFrequency)
            if profile.foodDeliveryFrequency >= 4 {
                lines.append("You order food delivery ~\(freq)x per week — that's a lot of takeout")
            } else {
                lines.append("You order food delivery about \(freq)x per week")
            }
        }

        if profile.eatingOutFrequency > 0 && profile.averageMealsPerDay > 0 {
            let outPct = Int((profile.eatingOutFrequency / (profile.averageMealsPerDay * 7)) * 100)
            if outPct > 50 {
                lines.append("Over half your meals are outside food — consider cooking more")
            }
        }

        if !profile.stapleFoods.isEmpty {
            let topStaples = profile.stapleFoods.sorted { $0.occurrences > $1.occurrences }.prefix(3)
            let names = topStaples.map { $0.name }.joined(separator: ", ")
            lines.append("Your go-to foods: \(names)")
        }

        if let mealTimes = profile.typicalMealTimes {
            var timeParts: [String] = []
            if let b = mealTimes.typicalBreakfastHour { timeParts.append("breakfast around \(formatHour(b))") }
            if let l = mealTimes.typicalLunchHour { timeParts.append("lunch around \(formatHour(l))") }
            if let d = mealTimes.typicalDinnerHour { timeParts.append("dinner around \(formatHour(d))") }
            if !timeParts.isEmpty {
                lines.append("You typically eat \(timeParts.joined(separator: ", "))")
            }
        }

        // --- Health Intelligence ---
        if profile.averageDailySteps > 0 {
            let stepsK = String(format: "%.1f", profile.averageDailySteps / 1000)
            let stepsComment: String
            if profile.averageDailySteps >= 10000 {
                stepsComment = " — great activity level"
            } else if profile.averageDailySteps >= 7000 {
                stepsComment = " — solid"
            } else if profile.averageDailySteps >= 4000 {
                stepsComment = " — try to get more movement"
            } else {
                stepsComment = " — you're quite sedentary"
            }
            lines.append("You walk about \(stepsK)k steps per day\(stepsComment)")
            stats.append(QuickStat(label: "Steps/day", value: "\(stepsK)k", color: .pink))
        }

        if let workout = profile.workoutFrequency, workout.sessionsPerWeek > 0 {
            let sessionsDesc = String(format: "%.0f", workout.sessionsPerWeek)
            let typeDesc = workout.dominantType.isEmpty ? "" : " (mostly \(workout.dominantType))"
            lines.append("You work out ~\(sessionsDesc)x per week\(typeDesc)")

            if workout.streakDays >= 3 {
                lines.append("Currently on a \(workout.streakDays)-day workout streak")
            }
            stats.append(QuickStat(label: "Workouts/wk", value: sessionsDesc, color: .green))
        }

        if let sleep = profile.typicalSleepWindow, sleep.averageDurationHours > 0 {
            let hrs = String(format: "%.1f", sleep.averageDurationHours)
            let sleepComment: String
            if sleep.averageDurationHours >= 7.5 {
                sleepComment = " — healthy amount"
            } else if sleep.averageDurationHours >= 6.5 {
                sleepComment = " — could use more"
            } else {
                sleepComment = " — you need more sleep"
            }
            lines.append("You sleep about \(hrs) hours per night\(sleepComment)")

            let bedtime = formatMinutesFromMidnight(sleep.typicalBedtimeMinutes)
            let wake = formatMinutesFromMidnight(sleep.typicalWakeMinutes)
            lines.append("Typical sleep window: \(bedtime) to \(wake)")
            stats.append(QuickStat(label: "Sleep", value: "\(hrs)h", color: .indigo))
        }

        // --- Fallback if no data ---
        if lines.isEmpty {
            lines.append("Keep using NodeCompass — I'm still learning about you")
            lines.append("Sync your bank, log meals, and grant Health access to unlock personalized insights")
        }

        profileSummaryLines = lines
        quickStats = stats
    }

    // MARK: - Helpers

    private func formatHour(_ hour: Int) -> String {
        if hour == 0 { return "12 AM" }
        if hour == 12 { return "12 PM" }
        if hour > 12 { return "\(hour - 12) PM" }
        return "\(hour) AM"
    }

    private func formatMinutesFromMidnight(_ mins: Int) -> String {
        let h = mins / 60
        let m = mins % 60
        let hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        let ampm = h >= 12 ? "PM" : "AM"
        if m == 0 { return "\(hour12) \(ampm)" }
        return "\(hour12):\(String(format: "%02d", m)) \(ampm)"
    }
}
