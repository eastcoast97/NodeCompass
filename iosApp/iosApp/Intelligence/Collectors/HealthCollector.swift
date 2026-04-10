import Foundation
import HealthKit

/// Collects health data from HealthKit — aggregates data from iPhone, Apple Watch,
/// Whoop, Fitbit, and any other app that writes to HealthKit.
/// HealthKit automatically deduplicates overlapping samples from multiple sources.
class HealthCollector: NSObject, DataCollector, ObservableObject {
    static let shared = HealthCollector()

    let source: EventSource = .healthKit
    private let healthStore = HKHealthStore()
    private let lastSyncKey = "health_last_sync"

    @Published var authorizationStatus: HKAuthorizationStatus = .notDetermined
    @Published var isCollecting = false

    // Types we read (never write)
    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        // Quantity types
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let calories = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(calories) }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { types.insert(distance) }
        if let heartRate = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heartRate) }
        // Category types
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        // Workout type
        types.insert(HKObjectType.workoutType())
        return types
    }()

    var isAuthorized: Bool {
        get async {
            guard HKHealthStore.isHealthDataAvailable() else { return false }
            // Check if we can read step count as a proxy for authorization
            guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return false }
            return healthStore.authorizationStatus(for: stepType) == .sharingAuthorized ||
                   UserDefaults.standard.bool(forKey: "healthKitAuthorized")
        }
    }

    override init() {
        super.init()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthError.notAvailable
        }
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
        UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
        DispatchQueue.main.async {
            self.authorizationStatus = .sharingAuthorized
        }
    }

    /// Check and request — called from the gate view.
    func requestPermissionAndStart() {
        Task {
            try? await requestAuthorization()
            await collectAndStore()
            enableBackgroundDelivery()
        }
    }

    // MARK: - Background Delivery

    /// Enable HealthKit background delivery (requires paid developer account entitlement).
    /// For personal teams, health data is collected on foreground + background task scheduler.
    func enableBackgroundDelivery() {
        // Background delivery requires com.apple.developer.healthkit.background-delivery entitlement.
        // Personal developer teams don't support this, so we rely on BGTaskScheduler instead.
        // When publishing with a paid account, uncomment the code below:
        /*
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let typesToObserve: [HKSampleType] = [
            HKObjectType.quantityType(forIdentifier: .stepCount),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned),
            HKObjectType.workoutType(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        ].compactMap { $0 }
        for type in typesToObserve {
            healthStore.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
        */
    }

    // MARK: - DataCollector

    func collect() async throws -> [LifeEvent] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }

        let lastSync = lastSyncDate()
        var events: [LifeEvent] = []

        // Collect all data types in parallel
        async let stepsEvents = fetchDailySteps(since: lastSync)
        async let calorieEvents = fetchDailyCalories(since: lastSync)
        async let workoutEvents = fetchWorkouts(since: lastSync)
        async let sleepEvents = fetchSleep(since: lastSync)
        async let heartRateEvents = fetchRestingHeartRate(since: lastSync)

        events.append(contentsOf: await stepsEvents)
        events.append(contentsOf: await calorieEvents)
        events.append(contentsOf: await workoutEvents)
        events.append(contentsOf: await sleepEvents)
        events.append(contentsOf: await heartRateEvents)

        // Update last sync
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastSyncKey)

        return events
    }

    /// Collect and store into EventStore.
    func collectAndStore() async {
        isCollecting = true
        defer { DispatchQueue.main.async { self.isCollecting = false } }

        do {
            let events = try await collect()
            if !events.isEmpty {
                await EventStore.shared.appendBatch(events)
            }
        } catch {
        }
    }

    // MARK: - Steps (Daily Aggregated)

    private func fetchDailySteps(since: Date) async -> [LifeEvent] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }

        let samples = await queryDailyStatistics(type: stepType, unit: .count(), since: since)
        return samples.map { sample in
            LifeEvent(
                timestamp: sample.date,
                source: .healthKit,
                payload: .healthSample(HealthSampleEvent(
                    metric: "steps",
                    value: sample.value,
                    unit: "count",
                    startDate: sample.start,
                    endDate: sample.end
                ))
            )
        }
    }

    // MARK: - Calories (Daily Aggregated)

    private func fetchDailyCalories(since: Date) async -> [LifeEvent] {
        guard let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }

        let samples = await queryDailyStatistics(type: calType, unit: .kilocalorie(), since: since)
        return samples.map { sample in
            LifeEvent(
                timestamp: sample.date,
                source: .healthKit,
                payload: .healthSample(HealthSampleEvent(
                    metric: "activeCalories",
                    value: sample.value,
                    unit: "kcal",
                    startDate: sample.start,
                    endDate: sample.end
                ))
            )
        }
    }

    // MARK: - Workouts

    private func fetchWorkouts(since: Date) async -> [LifeEvent] {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                guard let workouts = results as? [HKWorkout], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                let events = workouts.map { workout -> LifeEvent in
                    let activityName = Self.workoutName(for: workout.workoutActivityType)
                    let duration = workout.duration / 60.0 // Convert to minutes
                    let calories = workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                    let distance = workout.totalDistance?.doubleValue(for: .meter())

                    return LifeEvent(
                        timestamp: workout.startDate,
                        source: .healthKit,
                        payload: .workout(WorkoutEvent(
                            activityType: activityName,
                            durationMinutes: duration,
                            caloriesBurned: calories,
                            distanceMeters: distance
                        ))
                    )
                }
                continuation.resume(returning: events)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep

    private func fetchSleep(since: Date) async -> [LifeEvent] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, results, error in
                guard let samples = results as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                // Group overlapping sleep samples into sessions
                // HealthKit reports multiple samples (inBed, asleep, REM, deep, core)
                // We want one event per sleep session — use inBed or asleep.core as the main signal
                let sleepSamples = samples.filter { sample in
                    let value = HKCategoryValueSleepAnalysis(rawValue: sample.value)
                    return value == .asleepUnspecified || value == .asleepCore ||
                           value == .asleepDeep || value == .asleepREM || value == .inBed
                }

                // Merge into sessions: group samples that overlap or are within 30 min of each other
                let sessions = Self.mergeSleepSessions(sleepSamples)

                let events = sessions.map { session -> LifeEvent in
                    let durationHours = session.end.timeIntervalSince(session.start) / 3600.0
                    return LifeEvent(
                        timestamp: session.start,
                        source: .healthKit,
                        payload: .healthSample(HealthSampleEvent(
                            metric: "sleep",
                            value: durationHours,
                            unit: "hours",
                            startDate: session.start,
                            endDate: session.end
                        ))
                    )
                }
                continuation.resume(returning: events)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Resting Heart Rate (Daily)

    private func fetchRestingHeartRate(since: Date) async -> [LifeEvent] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return [] }

        let samples = await queryDailyStatistics(type: hrType, unit: .count().unitDivided(by: .minute()), since: since, options: .discreteAverage)
        return samples.map { sample in
            LifeEvent(
                timestamp: sample.date,
                source: .healthKit,
                payload: .healthSample(HealthSampleEvent(
                    metric: "heartRate",
                    value: sample.value,
                    unit: "bpm",
                    startDate: sample.start,
                    endDate: sample.end
                ))
            )
        }
    }

    // MARK: - Live Queries (for dashboard — always fresh)

    /// Get today's step count directly from HealthKit (real-time).
    func todaySteps() async -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let steps = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }

    /// Get today's active calories directly from HealthKit (real-time).
    func todayActiveCalories() async -> Int {
        guard let calType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let cals = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: Int(cals))
            }
            healthStore.execute(query)
        }
    }

    /// Get last night's sleep hours from HealthKit.
    func lastNightSleepHours() async -> Double {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return 0 }
        let cal = Calendar.current
        // Look back 24 hours for sleep data
        let since = cal.date(byAdding: .hour, value: -24, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, _ in
                guard let samples = results as? [HKCategorySample] else {
                    continuation.resume(returning: 0)
                    return
                }
                let sleepSamples = samples.filter { s in
                    let v = HKCategoryValueSleepAnalysis(rawValue: s.value)
                    return v == .asleepUnspecified || v == .asleepCore || v == .asleepDeep || v == .asleepREM
                }
                let totalSeconds = sleepSamples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                continuation.resume(returning: totalSeconds / 3600.0)
            }
            healthStore.execute(query)
        }
    }

    /// Get today's resting heart rate from HealthKit.
    func todayRestingHeartRate() async -> Int {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return 0 }
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [sortDescriptor]) { _, results, _ in
                guard let sample = results?.first as? HKQuantitySample else {
                    continuation.resume(returning: 0)
                    return
                }
                let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                continuation.resume(returning: Int(bpm))
            }
            healthStore.execute(query)
        }
    }

    /// Get workouts from the last 14 days — returns (count this week, streak days, dominant type).
    func recentWorkoutStats() async -> (perWeek: Double, streak: Int, dominant: String) {
        let workoutType = HKObjectType.workoutType()
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .day, value: -14, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: twoWeeksAgo, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: workoutType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, _ in
                guard let workouts = results as? [HKWorkout], workouts.count >= 1 else {
                    continuation.resume(returning: (0, 0, ""))
                    return
                }

                let perWeek = Double(workouts.count) / 2.0

                // Dominant type
                let typeGroups = Dictionary(grouping: workouts, by: { Self.workoutName(for: $0.workoutActivityType) })
                let dominant = typeGroups.max(by: { $0.value.count < $1.value.count })?.key ?? "Workout"

                // Streak: consecutive days with workouts going backward from today
                let workoutDays = Set(workouts.map { cal.startOfDay(for: $0.startDate) }).sorted().reversed()
                var streak = 0
                var checkDate = cal.startOfDay(for: Date())
                for day in workoutDays {
                    if day == checkDate || day == cal.date(byAdding: .day, value: -1, to: checkDate)! {
                        streak += 1
                        checkDate = day
                    } else { break }
                }

                continuation.resume(returning: (perWeek, streak, dominant))
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Query Helpers

    private struct DailySample {
        let date: Date
        let start: Date
        let end: Date
        let value: Double
    }

    /// Query daily aggregated statistics for a quantity type.
    private func queryDailyStatistics(
        type: HKQuantityType,
        unit: HKUnit,
        since: Date,
        options: HKStatisticsOptions = .cumulativeSum
    ) async -> [DailySample] {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: since)
        let now = Date()

        let interval = DateComponents(day: 1)

        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: nil,
                options: options,
                anchorDate: startOfDay,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                guard let collection = collection, error == nil else {
                    continuation.resume(returning: [])
                    return
                }

                var samples: [DailySample] = []
                collection.enumerateStatistics(from: startOfDay, to: now) { statistics, _ in
                    let value: Double?
                    if options == .discreteAverage {
                        value = statistics.averageQuantity()?.doubleValue(for: unit)
                    } else {
                        value = statistics.sumQuantity()?.doubleValue(for: unit)
                    }

                    if let value = value, value > 0 {
                        samples.append(DailySample(
                            date: statistics.startDate,
                            start: statistics.startDate,
                            end: statistics.endDate,
                            value: value
                        ))
                    }
                }
                continuation.resume(returning: samples)
            }
            healthStore.execute(query)
        }
    }

    // MARK: - Sleep Session Merge

    private struct SleepSession {
        var start: Date
        var end: Date
    }

    /// Merge overlapping sleep samples into sessions.
    private static func mergeSleepSessions(_ samples: [HKCategorySample]) -> [SleepSession] {
        let sorted = samples.sorted { $0.startDate < $1.startDate }
        var sessions: [SleepSession] = []

        for sample in sorted {
            if var last = sessions.last,
               sample.startDate.timeIntervalSince(last.end) < 1800 { // 30 min gap
                last.end = max(last.end, sample.endDate)
                sessions[sessions.count - 1] = last
            } else {
                sessions.append(SleepSession(start: sample.startDate, end: sample.endDate))
            }
        }

        // Filter out very short "nap" sessions (< 1 hour)
        return sessions.filter { $0.end.timeIntervalSince($0.start) > 3600 }
    }

    // MARK: - Helpers

    private func lastSyncDate() -> Date {
        let ts = UserDefaults.standard.double(forKey: lastSyncKey)
        if ts > 0 {
            return Date(timeIntervalSince1970: ts)
        }
        // First sync: go back 30 days
        return Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }

    /// Map HKWorkoutActivityType to a human-readable name.
    static func workoutName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength Training"
        case .highIntensityIntervalTraining: return "HIIT"
        case .crossTraining: return "Cross Training"
        case .elliptical: return "Elliptical"
        case .rowing: return "Rowing"
        case .stairClimbing: return "Stair Climbing"
        case .pilates: return "Pilates"
        case .dance, .socialDance, .cardioDance: return "Dance"
        case .cooldown: return "Cooldown"
        case .coreTraining: return "Core Training"
        case .basketball: return "Basketball"
        case .soccer: return "Soccer"
        case .tennis: return "Tennis"
        case .badminton: return "Badminton"
        case .cricket: return "Cricket"
        case .tableTennis: return "Table Tennis"
        case .martialArts: return "Martial Arts"
        case .boxing, .kickboxing: return "Boxing"
        default: return "Workout"
        }
    }

    enum HealthError: Error, LocalizedError {
        case notAvailable
        case authorizationDenied

        var errorDescription: String? {
            switch self {
            case .notAvailable: return "HealthKit is not available on this device"
            case .authorizationDenied: return "Health data access was denied"
            }
        }
    }
}
