import Foundation

/// Tracks daily habits and streaks across all three life pillars.
actor HabitStore {
    static let shared = HabitStore()

    private let storeKey = "user_habits"
    private var habits: [Habit] = []

    private let logKey = "habit_logs"
    private var logs: [HabitLog] = []

    /// How a habit can be auto-completed without manual logging.
    /// nil = manual only (e.g., drink water, no smoking).
    enum AutoTrackSource: String, Codable, CaseIterable {
        case workout          // HealthKit detected a workout today
        case steps10k         // HealthKit steps >= 10,000
        case homeCooking      // FoodStore has a home-cooked meal today
        case noEatingOut      // No dining/restaurant transactions today
        case sleepEarly       // Sleep started before midnight (HealthKit)
        case meditation       // HealthKit mindfulness or meditation workout
        case noImpulseBuys    // No unplanned/impulse purchases today
        case gymVisit         // Location detected a gym visit

        var label: String {
            switch self {
            case .workout:       return "Auto: Workout detected"
            case .steps10k:      return "Auto: 10K steps"
            case .homeCooking:   return "Auto: Home meal logged"
            case .noEatingOut:   return "Auto: No dining spend"
            case .sleepEarly:    return "Auto: Slept before midnight"
            case .meditation:    return "Auto: Mindfulness session"
            case .noImpulseBuys: return "Auto: No impulse buys"
            case .gymVisit:      return "Auto: Gym visit"
            }
        }
    }

    struct Habit: Codable, Identifiable {
        let id: String
        var name: String
        var icon: String          // SF Symbol name
        var color: String         // "teal", "pink", "orange", "blue", "purple", "green"
        var isArchived: Bool
        var createdAt: Date
        var autoTrackSource: AutoTrackSource?  // nil = manual habit
    }

    struct HabitLog: Codable, Identifiable {
        let id: String
        let habitId: String
        let date: String          // "2026-04-10"
        let completedAt: Date
    }

    /// Suggested habits spanning Wealth, Health, and Mind pillars.
    /// autoTrack: nil means manual-only (tech can't verify it).
    static let suggestions: [(name: String, icon: String, color: String, autoTrack: AutoTrackSource?)] = [
        ("Meditate", "brain.head.profile", "purple", .meditation),
        ("Read", "book.fill", "blue", nil),               // manual
        ("Exercise", "figure.run", "pink", .workout),
        ("Cook at Home", "fork.knife", "orange", .homeCooking),
        ("No Junk Food", "leaf.fill", "green", nil),       // manual
        ("Journal", "note.text", "teal", nil),             // manual
        ("8 Glasses of Water", "drop.fill", "blue", nil),  // manual
        ("No Impulse Buys", "cart.badge.minus", "teal", .noImpulseBuys),
        ("Sleep by 11 PM", "moon.fill", "purple", .sleepEarly),
        ("Walk 10k Steps", "figure.walk", "pink", .steps10k),
        ("Go to Gym", "dumbbell.fill", "pink", .gymVisit),
        ("No Eating Out", "bag.fill", "teal", .noEatingOut),
    ]

    private init() {
        habits = loadHabits()
        logs = loadLogs()
        migrateAutoTrackSources()
    }

    /// One-time migration: backfill autoTrackSource for existing habits
    /// based on name/icon matching against known suggestions.
    private func migrateAutoTrackSources() {
        let migrationKey = "habit_autotrack_migrated"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let nameMap: [String: AutoTrackSource] = [
            "exercise": .workout, "workout": .workout,
            "walk 10k steps": .steps10k, "10k steps": .steps10k, "walk 10000 steps": .steps10k,
            "cook at home": .homeCooking, "home cooking": .homeCooking,
            "no eating out": .noEatingOut,
            "meditate": .meditation, "meditation": .meditation,
            "sleep by 11 pm": .sleepEarly, "sleep early": .sleepEarly,
            "no impulse buys": .noImpulseBuys,
            "go to gym": .gymVisit, "gym": .gymVisit,
        ]

        let iconMap: [String: AutoTrackSource] = [
            "figure.run": .workout,
            "figure.walk": .steps10k,
            "dumbbell.fill": .gymVisit,
        ]

        var changed = false
        for i in habits.indices where habits[i].autoTrackSource == nil {
            let name = habits[i].name.lowercased()
            if let source = nameMap[name] {
                habits[i].autoTrackSource = source
                changed = true
            } else if let source = iconMap[habits[i].icon] {
                habits[i].autoTrackSource = source
                changed = true
            }
        }

        if changed { saveHabits() }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    // MARK: - Queries

    /// Returns all non-archived habits.
    func allHabits() -> [Habit] {
        habits.filter { !$0.isArchived }
    }

    /// Whether a habit has a log for the given date.
    func isCompleted(habitId: String, date: Date) -> Bool {
        let key = dateKey(for: date)
        return logs.contains { $0.habitId == habitId && $0.date == key }
    }

    /// Count of habits completed today.
    func completedToday() -> Int {
        let todayKey = dateKey(for: Date())
        let activeIds = Set(allHabits().map(\.id))
        return logs.filter { $0.date == todayKey && activeIds.contains($0.habitId) }.count
    }

    /// Total number of active habits.
    func totalToday() -> Int {
        allHabits().count
    }

    /// Combined today progress.
    func todayProgress() -> (completed: Int, total: Int) {
        (completedToday(), totalToday())
    }

    /// Consecutive days completed going back from today.
    func streak(for habitId: String) -> Int {
        let cal = Calendar.current
        var day = Date()
        var count = 0
        while true {
            let key = dateKey(for: day)
            if logs.contains(where: { $0.habitId == habitId && $0.date == key }) {
                count += 1
                guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
                day = prev
            } else {
                break
            }
        }
        return count
    }

    /// Percentage of last N days the habit was completed (0.0 - 1.0).
    func completionRate(for habitId: String, days: Int) -> Double {
        guard days > 0 else { return 0 }
        let cal = Calendar.current
        var completed = 0
        for offset in 0..<days {
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            let key = dateKey(for: day)
            if logs.contains(where: { $0.habitId == habitId && $0.date == key }) {
                completed += 1
            }
        }
        return Double(completed) / Double(days)
    }

    // MARK: - Mutations

    /// Add a new habit.
    func addHabit(name: String, icon: String, color: String, autoTrackSource: AutoTrackSource? = nil) {
        let habit = Habit(
            id: UUID().uuidString,
            name: name,
            icon: icon,
            color: color,
            isArchived: false,
            createdAt: Date(),
            autoTrackSource: autoTrackSource
        )
        habits.append(habit)
        saveHabits()
    }

    // MARK: - Auto-Complete

    /// Silently mark a habit as done if not already logged today.
    /// Used by the auto-tracker — doesn't toggle off.
    func autoComplete(habitId: String) {
        let key = dateKey(for: Date())
        guard !logs.contains(where: { $0.habitId == habitId && $0.date == key }) else { return }
        let log = HabitLog(
            id: UUID().uuidString,
            habitId: habitId,
            date: key,
            completedAt: Date()
        )
        logs.append(log)
        saveLogs()
    }

    /// Archive a habit (soft delete).
    func deleteHabit(id: String) {
        guard let idx = habits.firstIndex(where: { $0.id == id }) else { return }
        habits[idx].isArchived = true
        saveHabits()
    }

    /// Toggle completion for a habit on a given date.
    /// If already logged, removes the log; otherwise adds one.
    func toggleHabit(id: String, date: Date) {
        let key = dateKey(for: date)
        if let logIdx = logs.firstIndex(where: { $0.habitId == id && $0.date == key }) {
            logs.remove(at: logIdx)
        } else {
            let log = HabitLog(
                id: UUID().uuidString,
                habitId: id,
                date: key,
                completedAt: Date()
            )
            logs.append(log)
        }
        saveLogs()
    }

    /// Clear all habits and logs (called when user clears data).
    func clearAll() {
        habits = []
        logs = []
        UserDefaults.standard.removeObject(forKey: storeKey)
        UserDefaults.standard.removeObject(forKey: logKey)
    }

    // MARK: - Helpers

    private func dateKey(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - Persistence

    private func loadHabits() -> [Habit] {
        guard let data = UserDefaults.standard.data(forKey: storeKey),
              let decoded = try? JSONDecoder().decode([Habit].self, from: data) else { return [] }
        return decoded
    }

    private func saveHabits() {
        if let data = try? JSONEncoder().encode(habits) {
            UserDefaults.standard.set(data, forKey: storeKey)
        }
    }

    private func loadLogs() -> [HabitLog] {
        guard let data = UserDefaults.standard.data(forKey: logKey),
              let decoded = try? JSONDecoder().decode([HabitLog].self, from: data) else { return [] }
        return decoded
    }

    private func saveLogs() {
        if let data = try? JSONEncoder().encode(logs) {
            UserDefaults.standard.set(data, forKey: logKey)
        }
    }
}
