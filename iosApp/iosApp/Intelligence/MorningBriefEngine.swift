import Foundation
import UserNotifications

/// Generates a personalized morning briefing combining data from all pillars.
/// Pulls sleep, budget, streaks, bills, and habits into one snapshot.
actor MorningBriefEngine {
    static let shared = MorningBriefEngine()

    // MARK: - Model

    struct MorningBrief: Codable {
        let date: String
        let greeting: String              // "Good morning, Ram"
        let sleepSummary: String?         // "You slept 7.2 hours"
        let budgetRemaining: String?      // "$42 left in today's budget"
        let activeStreaks: [String]        // ["3-day gym streak", "5-day cooking streak"]
        let upcomingBills: [String]       // ["Netflix $15.99 due tomorrow"]
        let habitReminder: String?        // "4 habits to complete today"
        let motivational: String          // "You're on a roll this week!"
        let weatherNote: String?          // future: weather integration
    }

    private let notificationID = "morning_brief_notification"

    private init() {}

    // MARK: - Brief Generation

    /// Build a morning brief from all available data sources.
    func generateBrief() async -> MorningBrief {
        let cal = Calendar.current
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayKey = dateFormatter.string(from: now)

        // --- Greeting ---
        let name = await MainActor.run { PersonalInfoStore.shared.info.name }
        let hour = cal.component(.hour, from: now)
        let timeGreeting: String
        if hour < 12 {
            timeGreeting = "Good morning"
        } else if hour < 17 {
            timeGreeting = "Good afternoon"
        } else {
            timeGreeting = "Good evening"
        }
        let greeting: String
        if let name, !name.isEmpty {
            greeting = "\(timeGreeting), \(name)"
        } else {
            greeting = timeGreeting
        }

        // --- Sleep ---
        let sleepHours = await HealthCollector.shared.lastNightSleepHours()
        let sleepSummary: String?
        if sleepHours > 0 {
            let formatted = String(format: "%.1f", sleepHours)
            sleepSummary = "You slept \(formatted) hours"
        } else {
            sleepSummary = nil
        }

        // --- Budget Remaining ---
        let budgetRemaining = await calculateBudgetRemaining(cal: cal, now: now)

        // --- Active Streaks ---
        let streaks = await AchievementEngine.shared.activeStreaks()
        let streakStrings: [String] = streaks.compactMap { streak in
            guard streak.isActive, streak.currentDays > 0 else { return nil }
            return "\(streak.currentDays)-day \(streak.type.title.lowercased()) streak"
        }

        // --- Upcoming Bills ---
        let bills = await BillCalendarEngine.shared.upcomingBills(days: 2)
        let billStrings: [String] = bills.map { bill in
            let amountStr = NC.money(bill.estimatedAmount)
            if let due = bill.nextDueDate {
                let isToday = cal.isDateInToday(due)
                let isTomorrow = cal.isDateInTomorrow(due)
                let dueLabel = isToday ? "due today" : (isTomorrow ? "due tomorrow" : "due soon")
                return "\(bill.merchant) \(amountStr) \(dueLabel)"
            }
            return "\(bill.merchant) \(amountStr) due soon"
        }

        // --- Habit Reminder ---
        let habitProgress = await HabitStore.shared.todayProgress()
        let habitReminder: String?
        if habitProgress.total > 0 {
            let remaining = habitProgress.total - habitProgress.completed
            if remaining > 0 {
                habitReminder = "\(remaining) habit\(remaining == 1 ? "" : "s") to complete today"
            } else {
                habitReminder = "All habits completed today!"
            }
        } else {
            habitReminder = nil
        }

        // --- Motivational ---
        let motivational = pickMotivational(
            sleepHours: sleepHours,
            streakCount: streakStrings.count,
            habitsCompleted: habitProgress.completed,
            habitsTotal: habitProgress.total
        )

        return MorningBrief(
            date: todayKey,
            greeting: greeting,
            sleepSummary: sleepSummary,
            budgetRemaining: budgetRemaining,
            activeStreaks: streakStrings,
            upcomingBills: billStrings,
            habitReminder: habitReminder,
            motivational: motivational,
            weatherNote: nil // future: weather integration
        )
    }

    // MARK: - Notification Scheduling

    /// Schedule a daily notification at 7:30 AM with the morning brief content.
    func scheduleMorningNotification() {
        let center = UNUserNotificationCenter.current()

        // Remove any existing morning brief notification
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }

            Task {
                let brief = await self.generateBrief()

                let content = UNMutableNotificationContent()
                content.title = brief.greeting
                content.sound = .default

                // Build a concise body from the brief
                var bodyParts: [String] = []
                if let sleep = brief.sleepSummary { bodyParts.append(sleep) }
                if let budget = brief.budgetRemaining { bodyParts.append(budget) }
                if let habit = brief.habitReminder { bodyParts.append(habit) }
                if !brief.activeStreaks.isEmpty {
                    bodyParts.append(brief.activeStreaks.first!)
                }
                bodyParts.append(brief.motivational)
                content.body = bodyParts.joined(separator: " | ")

                // Trigger at 7:30 AM daily
                var dateComponents = DateComponents()
                dateComponents.hour = 7
                dateComponents.minute = 30
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

                let request = UNNotificationRequest(
                    identifier: self.notificationID,
                    content: content,
                    trigger: trigger
                )

                try? await center.add(request)
            }
        }
    }

    // MARK: - Clear

    func clearAll() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    // MARK: - Helpers

    private func calculateBudgetRemaining(cal: Calendar, now: Date) async -> String? {
        let (monthlyIncome, todaySpend) = await MainActor.run {
            (TransactionStore.shared.totalIncomeThisMonth,
             TransactionStore.shared.totalSpendToday)
        }

        guard monthlyIncome > 0 else { return nil }

        let daysInMonth = cal.range(of: .day, in: .month, for: now)?.count ?? 30
        let dailyBudget = (monthlyIncome * 0.7) / Double(daysInMonth)
        let remaining = dailyBudget - todaySpend

        if remaining > 0 {
            return "\(NC.money(remaining)) left in today's budget"
        } else {
            return "Over today's budget by \(NC.money(abs(remaining)))"
        }
    }

    private func pickMotivational(sleepHours: Double, streakCount: Int, habitsCompleted: Int, habitsTotal: Int) -> String {
        // Context-aware motivational messages
        if habitsTotal > 0 && habitsCompleted == habitsTotal {
            return "All habits done already? You're unstoppable!"
        }
        if streakCount >= 3 {
            return "Multiple streaks active \u{2014} you're building real momentum!"
        }
        if sleepHours >= 7.5 {
            return "Great sleep last night \u{2014} let's make today count!"
        }
        if sleepHours > 0 && sleepHours < 6 {
            return "Short night \u{2014} take it easy and stay hydrated."
        }
        if streakCount >= 1 {
            return "You're on a roll this week \u{2014} keep it going!"
        }

        // Fallback pool
        let defaults = [
            "Small steps every day lead to big results.",
            "Today is a fresh start \u{2014} make it count!",
            "Consistency beats perfection. Keep showing up.",
            "Your future self will thank you for today's effort.",
            "One day at a time \u{2014} you've got this!",
        ]
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return defaults[dayOfYear % defaults.count]
    }
}
