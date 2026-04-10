import Foundation

/// Analyzes health events (workouts, steps, sleep, heart rate) to produce insights.
/// Cross-references with location and spending data for richer correlations.
struct HealthAnalyzer {

    /// Analyze health events and produce insights.
    static func analyze(events: [LifeEvent], profile: UserProfile) -> [Insight] {
        var insights: [Insight] = []

        let healthEvents = events.filter { $0.source == .healthKit }
        guard !healthEvents.isEmpty else { return [] }

        // 1. Workout streak & frequency
        insights.append(contentsOf: workoutInsights(events: events))

        // 2. Step count trends
        insights.append(contentsOf: stepInsights(events: healthEvents))

        // 3. Sleep patterns
        insights.append(contentsOf: sleepInsights(events: healthEvents))

        // 4. Heart rate
        if let hrInsight = heartRateInsight(events: healthEvents) {
            insights.append(hrInsight)
        }

        // 5. Cross-source: workout + spending correlation
        insights.append(contentsOf: postWorkoutSpending(events: events))

        // 6. Cross-source: low activity + high food delivery
        if let sedentaryInsight = sedentarySpendingCorrelation(events: events) {
            insights.append(sedentaryInsight)
        }

        return insights
    }

    // MARK: - Workout Insights

    private static func workoutInsights(events: [LifeEvent]) -> [Insight] {
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: Date())!

        let workouts = events.compactMap { event -> (date: Date, workout: WorkoutEvent)? in
            guard event.timestamp >= twoWeeksAgo else { return nil }
            if case .workout(let w) = event.payload { return (event.timestamp, w) }
            return nil
        }.sorted { $0.date > $1.date }

        guard workouts.count >= 2 else { return [] }

        var insights: [Insight] = []

        // Workout frequency
        let perWeek = Double(workouts.count) / 2.0

        // Most common workout type
        let typeGroups = Dictionary(grouping: workouts, by: { $0.workout.activityType })
        let topType = typeGroups.max(by: { $0.value.count < $1.value.count })
        let topTypeName = topType?.key ?? "Workout"

        // Streak detection: count consecutive days with a workout
        let workoutDays = Set(workouts.map { cal.startOfDay(for: $0.date) }).sorted().reversed()
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())
        for day in workoutDays {
            if day == checkDate || day == cal.date(byAdding: .day, value: -1, to: checkDate)! {
                streak += 1
                checkDate = day
            } else {
                break
            }
        }

        // Average duration & calories
        let avgDuration = workouts.reduce(0.0) { $0 + $1.workout.durationMinutes } / Double(workouts.count)
        let totalCalories = workouts.compactMap { $0.workout.caloriesBurned }.reduce(0, +)

        // Main workout frequency insight
        var body = "You've logged \(workouts.count) workouts in 2 weeks"
        body += ", mostly \(topTypeName)"
        body += ". Avg \(Int(avgDuration)) min per session."
        if totalCalories > 0 {
            body += " Total burn: \(Int(totalCalories)) cal."
        }

        insights.append(Insight(
            type: .healthPattern,
            title: "\(topTypeName) \(String(format: "%.0f", perWeek))x/week",
            body: body,
            priority: .low,
            category: "health"
        ))

        // Streak insight (3+ days)
        if streak >= 3 {
            insights.append(Insight(
                type: .healthPattern,
                title: "\(streak)-day workout streak!",
                body: "You've worked out \(streak) days in a row. Keep it going!",
                priority: streak >= 5 ? .medium : .low,
                category: "health"
            ))
        }

        // Preferred time
        let hours = workouts.map { cal.component(.hour, from: $0.date) }
        let avgHour = hours.reduce(0, +) / hours.count
        let timeLabel = avgHour < 6 ? "early morning" : avgHour < 12 ? "morning" : avgHour < 17 ? "afternoon" : "evening"

        // Preferred days
        let dayGroups = Dictionary(grouping: workouts) { cal.component(.weekday, from: $0.date) }
        let topDay = dayGroups.max(by: { $0.value.count < $1.value.count })
        let dayName = topDay.map { dayOfWeekName($0.key) } ?? ""

        if workouts.count >= 4 {
            insights.append(Insight(
                type: .routine,
                title: "You prefer \(timeLabel) workouts",
                body: "Most of your sessions are in the \(timeLabel)\(dayName.isEmpty ? "" : ", especially on \(dayName)s").",
                priority: .low,
                category: "health"
            ))
        }

        return insights
    }

    // MARK: - Step Insights

    private static func stepInsights(events: [LifeEvent]) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let stepDays = events.compactMap { event -> (date: Date, steps: Double)? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .healthSample(let h) = event.payload, h.metric == "steps" {
                return (event.timestamp, h.value)
            }
            return nil
        }

        guard stepDays.count >= 3 else { return [] }

        var insights: [Insight] = []

        let avgSteps = stepDays.reduce(0.0) { $0 + $1.steps } / Double(stepDays.count)
        let maxDay = stepDays.max(by: { $0.steps < $1.steps })
        let minDay = stepDays.min(by: { $0.steps < $1.steps })

        // Daily average insight
        let avgFormatted = Int(avgSteps).formatted(.number)
        insights.append(Insight(
            type: .healthPattern,
            title: "Avg \(avgFormatted) steps/day",
            body: "Your 7-day average is \(avgFormatted) steps.\(avgSteps >= 10000 ? " Great job hitting 10k!" : avgSteps < 5000 ? " Try to aim for at least 7,000." : "")",
            priority: .low,
            category: "health"
        ))

        // Best day callout
        if let best = maxDay, best.steps >= 10000 {
            let dayName = dayOfWeekName(cal.component(.weekday, from: best.date))
            insights.append(Insight(
                type: .milestone,
                title: "\(Int(best.steps).formatted(.number)) steps on \(dayName)!",
                body: "That was your most active day this week.",
                priority: .low,
                category: "health"
            ))
        }

        // Low activity day warning
        if let worst = minDay, worst.steps < 3000 && avgSteps > 5000 {
            let dayName = dayOfWeekName(cal.component(.weekday, from: worst.date))
            insights.append(Insight(
                type: .healthPattern,
                title: "Low activity on \(dayName)",
                body: "Only \(Int(worst.steps).formatted(.number)) steps — well below your \(avgFormatted) average.",
                priority: .low,
                category: "health"
            ))
        }

        return insights
    }

    // MARK: - Sleep Insights

    private static func sleepInsights(events: [LifeEvent]) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let sleepSessions = events.compactMap { event -> (date: Date, hours: Double, bedtime: Date, wake: Date)? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .healthSample(let h) = event.payload, h.metric == "sleep" {
                return (event.timestamp, h.value, h.startDate, h.endDate)
            }
            return nil
        }

        guard sleepSessions.count >= 3 else { return [] }

        var insights: [Insight] = []

        let avgHours = sleepSessions.reduce(0.0) { $0 + $1.hours } / Double(sleepSessions.count)

        // Average sleep duration
        let hoursStr = String(format: "%.1f", avgHours)
        var sleepBody = "Your average this week is \(hoursStr) hours."
        if avgHours < 6.5 {
            sleepBody += " That's below the recommended 7-9 hours."
        } else if avgHours >= 7 && avgHours <= 9 {
            sleepBody += " You're in the healthy 7-9 hour range."
        }

        insights.append(Insight(
            type: .healthPattern,
            title: "Avg \(hoursStr)h sleep/night",
            body: sleepBody,
            priority: avgHours < 6 ? .medium : .low,
            category: "health"
        ))

        // Bedtime consistency
        let bedtimeMinutes = sleepSessions.map { session -> Int in
            let comps = cal.dateComponents([.hour, .minute], from: session.bedtime)
            var mins = comps.hour! * 60 + comps.minute!
            if mins < 720 { mins += 1440 } // After midnight → add 24h for consistency
            return mins
        }
        let avgBedtime = bedtimeMinutes.reduce(0, +) / bedtimeMinutes.count
        let variance = bedtimeMinutes.map { abs($0 - avgBedtime) }.reduce(0, +) / bedtimeMinutes.count

        let bedtimeHour = (avgBedtime % 1440) / 60
        let bedtimeMin = (avgBedtime % 1440) % 60
        let bedtimeStr = String(format: "%d:%02d %@",
                                bedtimeHour > 12 ? bedtimeHour - 12 : bedtimeHour,
                                bedtimeMin,
                                bedtimeHour >= 12 ? "PM" : "AM")

        if variance > 60 {
            insights.append(Insight(
                type: .healthPattern,
                title: "Irregular bedtime",
                body: "Your bedtime varies by over an hour. Average is \(bedtimeStr). Consistent sleep timing improves quality.",
                priority: .low,
                category: "health"
            ))
        } else {
            insights.append(Insight(
                type: .routine,
                title: "Bedtime around \(bedtimeStr)",
                body: "Your sleep schedule is consistent — great for your circadian rhythm.",
                priority: .low,
                category: "health"
            ))
        }

        return insights
    }

    // MARK: - Heart Rate Insight

    private static func heartRateInsight(events: [LifeEvent]) -> Insight? {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let hrReadings = events.compactMap { event -> Double? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .healthSample(let h) = event.payload, h.metric == "heartRate" {
                return h.value
            }
            return nil
        }

        guard hrReadings.count >= 3 else { return nil }

        let avg = hrReadings.reduce(0, +) / Double(hrReadings.count)
        return Insight(
            type: .healthPattern,
            title: "Avg resting HR: \(Int(avg)) bpm",
            body: avg < 60 ? "Athlete-level resting heart rate. Your cardiovascular fitness is excellent." :
                  avg <= 80 ? "Your resting heart rate is in a healthy range." :
                  "Your resting heart rate is elevated. Consider more aerobic exercise.",
            priority: .low,
            category: "health"
        )
    }

    // MARK: - Cross-Source: Post-Workout Spending

    private static func postWorkoutSpending(events: [LifeEvent]) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        let workouts = events.compactMap { event -> (date: Date, workout: WorkoutEvent)? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .workout(let w) = event.payload { return (event.timestamp, w) }
            return nil
        }

        let transactions = events.compactMap { event -> (date: Date, txn: TransactionEvent)? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .transaction(let t) = event.payload, !t.isCredit { return (event.timestamp, t) }
            return nil
        }

        var insights: [Insight] = []

        // Find spending within 2 hours after a workout
        for workout in workouts {
            let postWorkoutWindow = workout.date.addingTimeInterval(7200) // 2 hours

            let nearbySpend = transactions.filter {
                $0.date > workout.date && $0.date <= postWorkoutWindow
            }

            for txn in nearbySpend {
                let category = txn.txn.category.lowercased()
                if category.contains("food") || category.contains("dining") ||
                   category.contains("restaurant") || category.contains("health") ||
                   category.contains("smoothie") || category.contains("juice") {
                    insights.append(Insight(
                        type: .locationCorrelation,
                        title: "$\(String(format: "%.0f", txn.txn.amount)) after \(workout.workout.activityType)",
                        body: "\(txn.txn.merchant) charge right after your \(Int(workout.workout.durationMinutes)) min \(workout.workout.activityType.lowercased()) session.",
                        priority: .low,
                        category: "health",
                        expiresAt: cal.date(byAdding: .day, value: 5, to: Date())
                    ))
                }
            }
        }

        return Array(insights.prefix(3))
    }

    // MARK: - Cross-Source: Sedentary + Food Delivery

    private static func sedentarySpendingCorrelation(events: [LifeEvent]) -> Insight? {
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: Date())!

        // Get daily step counts
        let stepDays = events.compactMap { event -> (date: Date, steps: Double)? in
            guard event.timestamp >= twoWeeksAgo else { return nil }
            if case .healthSample(let h) = event.payload, h.metric == "steps" {
                return (cal.startOfDay(for: event.timestamp), h.value)
            }
            return nil
        }

        // Get food/dining transactions
        let foodTxns = events.compactMap { event -> (date: Date, amount: Double)? in
            guard event.timestamp >= twoWeeksAgo else { return nil }
            if case .transaction(let t) = event.payload, !t.isCredit {
                let cat = t.category.lowercased()
                if cat.contains("food") || cat.contains("dining") || cat.contains("delivery") {
                    return (cal.startOfDay(for: event.timestamp), t.amount)
                }
            }
            return nil
        }

        guard stepDays.count >= 7 && foodTxns.count >= 3 else { return nil }

        let avgSteps = stepDays.reduce(0.0) { $0 + $1.steps } / Double(stepDays.count)

        // Low step days (below 60% of average)
        let lowStepDates = Set(stepDays.filter { $0.steps < avgSteps * 0.6 }.map { cal.startOfDay(for: $0.date) })
        let highStepDates = Set(stepDays.filter { $0.steps >= avgSteps }.map { cal.startOfDay(for: $0.date) })

        guard !lowStepDates.isEmpty && !highStepDates.isEmpty else { return nil }

        let foodOnLowDays = foodTxns.filter { lowStepDates.contains(cal.startOfDay(for: $0.date)) }
        let foodOnHighDays = foodTxns.filter { highStepDates.contains(cal.startOfDay(for: $0.date)) }

        let avgFoodLow = foodOnLowDays.isEmpty ? 0 : foodOnLowDays.reduce(0.0) { $0 + $1.amount } / Double(lowStepDates.count)
        let avgFoodHigh = foodOnHighDays.isEmpty ? 0 : foodOnHighDays.reduce(0.0) { $0 + $1.amount } / Double(highStepDates.count)

        guard avgFoodHigh > 0 && avgFoodLow > avgFoodHigh * 1.5 else { return nil }

        let multiplier = String(format: "%.1f", avgFoodLow / avgFoodHigh)

        return Insight(
            type: .healthPattern,
            title: "Sedentary days = more food spending",
            body: "On low-activity days, you spend \(multiplier)x more on food delivery. Active days: $\(Int(avgFoodHigh)) avg, lazy days: $\(Int(avgFoodLow)) avg.",
            priority: .medium,
            category: "health"
        )
    }

    // MARK: - Helpers

    private static func dayOfWeekName(_ day: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return day >= 1 && day <= 7 ? names[day] : ""
    }
}
