import Foundation
import HealthKit
import UserNotifications

/// Automatically completes habits based on real data signals.
///
/// Runs on app foreground. Checks each habit's `autoTrackSource` against
/// HealthKit, FoodStore, TransactionStore, and UserProfile data.
/// Manual habits (autoTrackSource == nil) are never touched.
///
/// Design: habits like "Drink Water" or "No Smoking" stay manual because
/// no sensor can verify them. But "Exercise", "Walk 10K Steps", "Go to Gym"
/// can be confirmed from HealthKit and location data automatically.
actor HabitAutoTracker {
    static let shared = HabitAutoTracker()

    private let lastRunKey = "habit_auto_tracker_last_run"

    private init() {}

    /// Call once at app launch (from NodeCompassApp) to start listening
    /// for real-time location events and evaluate habits immediately.
    nonisolated func startListening() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PlaceVisitDetected"),
            object: nil,
            queue: .main
        ) { _ in
            Task {
                await HabitAutoTracker.shared.evaluateFromLocationEvent()
            }
        }
    }

    /// Evaluate all auto-trackable habits and complete any that are satisfied.
    /// Idempotent — safe to call multiple times per day.
    func evaluate() async {
        // Only run once per hour to avoid redundant work
        let now = Date()
        let lastRun = UserDefaults.standard.double(forKey: lastRunKey)
        if lastRun > 0 && now.timeIntervalSince1970 - lastRun < 3600 { return }
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastRunKey)

        let habits = await HabitStore.shared.allHabits()
        let autoHabits = habits.filter { $0.autoTrackSource != nil }
        guard !autoHabits.isEmpty else { return }

        // Gather signals once (shared across all habits)
        let signals = await gatherSignals()

        for habit in autoHabits {
            guard let source = habit.autoTrackSource else { continue }
            // Skip if already completed today
            let done = await HabitStore.shared.isCompleted(habitId: habit.id, date: Date())
            if done { continue }

            if shouldComplete(source: source, signals: signals) {
                await HabitStore.shared.autoComplete(habitId: habit.id)
            }
        }
    }

    /// Evaluate triggered by a location event — bypasses the 1-hour throttle.
    /// This ensures gym visits, restaurant visits, etc. are reflected in habits immediately.
    func evaluateFromLocationEvent() async {
        var habits = await HabitStore.shared.allHabits()

        // Auto-create gym habit if user visits a gym but doesn't have the habit yet
        let signals = await gatherSignals()
        if signals.hasGymVisit {
            let hasGymHabit = habits.contains { $0.autoTrackSource == .gymVisit && !$0.isArchived }
            if !hasGymHabit {
                await HabitStore.shared.addHabit(
                    name: "Go to Gym",
                    icon: "dumbbell.fill",
                    color: "pink",
                    autoTrackSource: .gymVisit
                )
                habits = await HabitStore.shared.allHabits()
            }
        }

        // Only run if there are location-relevant auto-track habits
        let locationHabits = habits.filter { habit in
            guard let source = habit.autoTrackSource else { return false }
            return source == .gymVisit || source == .workout || source == .noEatingOut || source == .homeCooking
        }
        guard !locationHabits.isEmpty else { return }

        for habit in locationHabits {
            guard let source = habit.autoTrackSource else { continue }
            let done = await HabitStore.shared.isCompleted(habitId: habit.id, date: Date())
            if done { continue }

            if shouldComplete(source: source, signals: signals) {
                await HabitStore.shared.autoComplete(habitId: habit.id)
                await sendHabitNotification(habit: habit)
            }
        }
    }

    // MARK: - Habit Completion Notification

    /// Send a local push notification when a habit is auto-completed.
    private func sendHabitNotification(habit: HabitStore.Habit) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()

        switch habit.autoTrackSource {
        case .gymVisit:
            content.title = "Gym visit detected! 💪"
            content.body = "Your \"\(habit.name)\" habit is auto-completed for today."
        case .workout:
            content.title = "Workout logged! 🏃"
            content.body = "Your \"\(habit.name)\" habit is auto-completed for today."
        case .steps10k:
            content.title = "10K steps reached! 🎯"
            content.body = "Your \"\(habit.name)\" habit is auto-completed for today."
        default:
            content.title = "Habit completed!"
            content.body = "\"\(habit.name)\" was auto-tracked and marked done."
        }

        content.sound = .default
        content.categoryIdentifier = "HABIT_COMPLETE"

        let request = UNNotificationRequest(
            identifier: "habit-\(habit.id)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    // MARK: - Signal Gathering

    private struct DaySignals {
        var hasWorkout: Bool = false
        var steps: Int = 0
        var sleepStartHour: Int? = nil       // hour of last sleep start (0-23)
        var hasMindfulnessSession: Bool = false
        var hasHomeMeal: Bool = false
        var hasDiningSpend: Bool = false
        var hasImpulseSpend: Bool = false
        var hasGymVisit: Bool = false
    }

    private func gatherSignals() async -> DaySignals {
        var signals = DaySignals()

        // HealthKit signals
        let health = HealthCollector.shared
        signals.steps = await health.todaySteps()

        // Workout check
        let workoutStats = await health.recentWorkoutStats()
        // Check if there's a workout TODAY specifically
        signals.hasWorkout = await checkTodayWorkout()
        signals.hasMindfulnessSession = await checkMindfulness()

        // Sleep: check if last sleep started before midnight
        signals.sleepStartHour = await checkSleepStartHour()

        // Food signals
        let foodEntries = await FoodStore.shared.entriesForToday()
        signals.hasHomeMeal = foodEntries.contains { entry in
            entry.mealType.lowercased() != "delivery" &&
            entry.mealType.lowercased() != "takeout"
        }

        // Transaction signals (today's spending)
        let todayTransactions = await MainActor.run {
            let cal = Calendar.current
            return TransactionStore.shared.transactions.filter {
                cal.isDateInToday($0.date) && $0.type.lowercased() != "credit"
            }
        }

        let diningCategories = Set(["food & dining", "restaurants", "fast food", "coffee shops", "dining"])
        let impulseCategories = Set(["shopping", "entertainment", "general merchandise"])

        signals.hasDiningSpend = todayTransactions.contains {
            diningCategories.contains($0.category.lowercased())
        }

        signals.hasImpulseSpend = todayTransactions.contains {
            impulseCategories.contains($0.category.lowercased())
        }

        // Gym visit from location data
        let profile = await UserProfileStore.shared.currentProfile()
        let cal = Calendar.current
        signals.hasGymVisit = profile.frequentLocations.contains { loc in
            guard let tag = loc.behaviorTag?.lowercased(),
                  tag.contains("fitness") || tag.contains("gym") else { return false }
            // Check if visited today
            if let dates = loc.visitDates {
                return dates.contains { cal.isDateInToday($0) }
            }
            // Fallback: check lastVisit
            return cal.isDateInToday(loc.lastVisit)
        }

        return signals
    }

    // MARK: - Evaluation

    private func shouldComplete(source: HabitStore.AutoTrackSource, signals: DaySignals) -> Bool {
        switch source {
        case .workout:
            return signals.hasWorkout

        case .steps10k:
            return signals.steps >= 10_000

        case .homeCooking:
            return signals.hasHomeMeal

        case .noEatingOut:
            // "No eating out" is true if you DIDN'T spend on dining
            return !signals.hasDiningSpend

        case .sleepEarly:
            // Consider "early" as sleep starting before midnight (hour < 24 / 0)
            guard let hour = signals.sleepStartHour else { return false }
            return hour >= 20 && hour <= 23  // Slept between 8 PM and midnight

        case .meditation:
            return signals.hasMindfulnessSession

        case .noImpulseBuys:
            return !signals.hasImpulseSpend

        case .gymVisit:
            return signals.hasGymVisit
        }
    }

    // MARK: - HealthKit Helpers

    private func checkTodayWorkout() async -> Bool {
        let workoutType = HKObjectType.workoutType()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let store = HKHealthStore()

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: (results?.count ?? 0) > 0)
            }
            store.execute(query)
        }
    }

    private func checkMindfulness() async -> Bool {
        guard let mindType = HKObjectType.categoryType(forIdentifier: .mindfulSession) else { return false }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let store = HKHealthStore()

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: mindType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, results, _ in
                continuation.resume(returning: (results?.count ?? 0) > 0)
            }
            store.execute(query)
        }
    }

    private func checkSleepStartHour() async -> Int? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let cal = Calendar.current
        let since = cal.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let store = HKHealthStore()

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: 5,
                sortDescriptors: [sort]
            ) { _, results, _ in
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: nil)
                    return
                }
                // Find the earliest "asleep" sample — that's when sleep started
                let sleepSamples = samples.filter { s in
                    let v = HKCategoryValueSleepAnalysis(rawValue: s.value)
                    return v == .asleepUnspecified || v == .asleepCore ||
                           v == .asleepDeep || v == .asleepREM
                }
                guard let earliest = sleepSamples.min(by: { $0.startDate < $1.startDate }) else {
                    continuation.resume(returning: nil)
                    return
                }
                let hour = cal.component(.hour, from: earliest.startDate)
                continuation.resume(returning: hour)
            }
            store.execute(query)
        }
    }
}
