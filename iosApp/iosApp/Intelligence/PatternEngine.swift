import Foundation

/// Orchestrator that runs all analyzers, produces insights, and updates the user profile.
/// Triggered on foreground, after transaction syncs, and periodically in the background.
actor PatternEngine {
    static let shared = PatternEngine()

    private var insights: [Insight] = []
    private let fileName = "insights.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var lastRunDate: Date?

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        loadInsights()
    }

    // MARK: - Public API

    /// Run all analyzers and produce new insights.
    /// Debounced — won't re-run if called within 60 seconds.
    func runAnalysis() async {
        if let lastRun = lastRunDate, Date().timeIntervalSince(lastRun) < 60 {
            return // Debounce
        }
        lastRunDate = Date()

        let events = await EventStore.shared.events(
            since: Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        )
        guard !events.isEmpty else { return }

        let profile = await UserProfileStore.shared.currentProfile()

        // Fetch user-marked cancelled / false-positive subscriptions once,
        // so SpendingAnalyzer can filter them out of ghost-sub detection.
        let cancelledEntries = await CancelledSubscriptionsStore.shared.all()
        let cancelledKeys = Set(cancelledEntries.map { entry in
            "\(entry.merchantKey)|\(String(format: "%.2f", entry.amount))"
        })

        // Run analyzers
        var newInsights: [Insight] = []
        newInsights.append(contentsOf: SpendingAnalyzer.analyze(
            events: events,
            profile: profile,
            cancelledSubscriptionKeys: cancelledKeys
        ))
        newInsights.append(contentsOf: AnomalyDetector.analyze(events: events))
        newInsights.append(contentsOf: LocationAnalyzer.analyze(events: events, profile: profile))
        newInsights.append(contentsOf: HealthAnalyzer.analyze(events: events, profile: profile))
        newInsights.append(contentsOf: FoodAnalyzer.analyze(events: events, profile: profile))
        newInsights.append(contentsOf: CrossSourceAnalyzer.analyze(events: events, profile: profile))

        // Weather-correlated behavioural insights. Requires a known home/frequent
        // location; fetches today's weather into the rolling 90-day cache and then
        // generates insights from ≥7 days of history.
        if !profile.frequentLocations.isEmpty {
            _ = await WeatherCorrelation.shared.todayWeather()
            let weatherInsights = await WeatherCorrelation.shared.generateInsights()
            for w in weatherInsights {
                // Skip the placeholder "Building Weather Profile" prompt — the
                // user doesn't need it on the insights feed.
                guard w.title != "Building Weather Profile" else { continue }
                newInsights.append(Insight(
                    type: .weatherPattern,
                    title: w.title,
                    body: w.description,
                    priority: .low,
                    category: "weather"
                ))
            }
        }

        // Deduplicate against existing insights (same type + same title within 24h)
        let deduped = newInsights.filter { new in
            !insights.contains { existing in
                existing.type == new.type &&
                existing.title == new.title &&
                abs(existing.createdAt.timeIntervalSince(new.createdAt)) < 86400
            }
        }

        if !deduped.isEmpty {
            insights.append(contentsOf: deduped)
            pruneExpiredInsights()
            saveInsights()

            // Send notifications for high/urgent insights
            for insight in deduped where insight.priority >= .high {
                await NotificationEngine.shared.scheduleIfAllowed(insight)
            }
        }

        // Update the user profile
        await updateProfile(from: events)
    }

    /// All active insights, sorted by priority (highest first) then date (newest first).
    func activeInsights() -> [Insight] {
        insights
            .filter { $0.isActive }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.createdAt > rhs.createdAt
            }
    }

    /// Total count of active insights.
    func activeCount() -> Int {
        insights.filter { $0.isActive }.count
    }

    /// Clear all insights (called when user clears data).
    func clearAll() {
        insights = []
        lastRunDate = nil
        saveInsights()
    }

    /// Dismiss an insight by ID.
    func dismiss(_ insightId: String) {
        insights.removeAll { $0.id == insightId }
        saveInsights()
    }

    // MARK: - Profile Update

    private func updateProfile(from events: [LifeEvent]) async {
        var profile = await UserProfileStore.shared.currentProfile()
        let cal = Calendar.current
        let now = Date()
        let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: now))!

        // Extract debit transactions
        let allDebits = events.compactMap { event -> (date: Date, txn: TransactionEvent)? in
            if case .transaction(let t) = event.payload, !t.isCredit {
                return (event.timestamp, t)
            }
            return nil
        }

        // Top merchants
        let byMerchant = Dictionary(grouping: allDebits, by: { $0.txn.merchant.lowercased() })
        profile.topMerchants = byMerchant.map { key, items in
            let first = items.first!.txn
            let total = items.reduce(0.0) { $0 + $1.txn.amount }
            return MerchantProfile(
                merchant: first.merchant,
                category: first.category,
                visitCount: items.count,
                totalSpent: total,
                averageAmount: total / Double(items.count),
                lastVisit: items.map { $0.date }.max() ?? now
            )
        }
        .sorted { $0.totalSpent > $1.totalSpent }
        .prefix(20)
        .map { $0 }

        // Spending by category this month
        let thisMonthDebits = allDebits.filter { $0.date >= startOfMonth }
        let lastMonthStart = cal.date(byAdding: .month, value: -1, to: startOfMonth)!
        let lastMonthDebits = allDebits.filter { $0.date >= lastMonthStart && $0.date < startOfMonth }

        let thisMonthByCategory = Dictionary(grouping: thisMonthDebits, by: { $0.txn.category })
        let lastMonthByCategory = Dictionary(grouping: lastMonthDebits, by: { $0.txn.category })

        profile.spendingByCategory = thisMonthByCategory.mapValues { items in
            let total = items.reduce(0.0) { $0 + $1.txn.amount }
            let category = items.first!.txn.category
            let lastMonthTotal = lastMonthByCategory[category]?.reduce(0.0) { $0 + $1.txn.amount } ?? 0
            return SpendingStats(
                totalThisMonth: total,
                totalLastMonth: lastMonthTotal,
                averagePerTransaction: total / Double(items.count),
                transactionCount: items.count,
                weekOverWeekChange: nil
            )
        }

        // Monthly spend trend (last 6 months)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        let byMonth = Dictionary(grouping: allDebits, by: { formatter.string(from: $0.date) })
        profile.monthlySpendTrend = byMonth.map { month, items in
            let byCat = Dictionary(grouping: items, by: { $0.txn.category })
                .mapValues { $0.reduce(0.0) { $0 + $1.txn.amount } }
            return MonthlySpend(
                month: month,
                total: items.reduce(0.0) { $0 + $1.txn.amount },
                byCategory: byCat
            )
        }.sorted { $0.month < $1.month }

        // MARK: Health Intelligence
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: now)!
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: now)!

        // Average daily steps (last 7 days)
        let stepDays = events.compactMap { event -> Double? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .healthSample(let h) = event.payload, h.metric == "steps" { return h.value }
            return nil
        }
        if !stepDays.isEmpty {
            profile.averageDailySteps = stepDays.reduce(0, +) / Double(stepDays.count)
        }

        // Workout frequency (last 2 weeks)
        let workouts = events.compactMap { event -> (date: Date, w: WorkoutEvent)? in
            guard event.timestamp >= twoWeeksAgo else { return nil }
            if case .workout(let w) = event.payload { return (event.timestamp, w) }
            return nil
        }
        if workouts.count >= 2 {
            let perWeek = Double(workouts.count) / 2.0
            let typeGroups = Dictionary(grouping: workouts, by: { $0.w.activityType })
            let topType = typeGroups.max(by: { $0.value.count < $1.value.count })?.key ?? "Workout"
            let hours = workouts.map { cal.component(.hour, from: $0.date) }
            let avgHour = hours.reduce(0, +) / hours.count
            let preferredDays = Array(Set(workouts.map { cal.component(.weekday, from: $0.date) }))

            // Streak
            let workoutDaySet = Set(workouts.map { cal.startOfDay(for: $0.date) }).sorted().reversed()
            var streak = 0
            var checkDate = cal.startOfDay(for: now)
            for day in workoutDaySet {
                if day == checkDate || day == cal.date(byAdding: .day, value: -1, to: checkDate)! {
                    streak += 1
                    checkDate = day
                } else { break }
            }

            profile.workoutFrequency = WorkoutFrequency(
                sessionsPerWeek: perWeek,
                preferredDays: preferredDays,
                preferredTime: avgHour,
                dominantType: topType,
                streakDays: streak
            )
        }

        // Sleep window (last 7 days)
        let sleepSessions = events.compactMap { event -> (bedtime: Date, wake: Date, hours: Double)? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .healthSample(let h) = event.payload, h.metric == "sleep" {
                return (h.startDate, h.endDate, h.value)
            }
            return nil
        }
        if sleepSessions.count >= 3 {
            let bedtimeMinutes = sleepSessions.map { session -> Int in
                let comps = cal.dateComponents([.hour, .minute], from: session.bedtime)
                var mins = comps.hour! * 60 + comps.minute!
                if mins < 720 { mins += 1440 }
                return mins
            }
            let wakeMinutes = sleepSessions.map { session -> Int in
                let comps = cal.dateComponents([.hour, .minute], from: session.wake)
                return comps.hour! * 60 + comps.minute!
            }
            let avgBedtime = bedtimeMinutes.reduce(0, +) / bedtimeMinutes.count
            let avgWake = wakeMinutes.reduce(0, +) / wakeMinutes.count
            let avgDuration = sleepSessions.reduce(0.0) { $0 + $1.hours } / Double(sleepSessions.count)

            profile.typicalSleepWindow = SleepWindow(
                typicalBedtimeMinutes: avgBedtime % 1440,
                typicalWakeMinutes: avgWake,
                averageDurationHours: avgDuration
            )
        }

        // MARK: Food Intelligence
        let foodEvents = events.compactMap { event -> (date: Date, food: FoodLogEvent)? in
            guard event.timestamp >= twoWeeksAgo else { return nil }
            if case .foodLog(let f) = event.payload { return (event.timestamp, f) }
            return nil
        }

        if foodEvents.count >= 3 {
            let foodByDay = Dictionary(grouping: foodEvents) { cal.startOfDay(for: $0.date) }
            profile.averageMealsPerDay = Double(foodEvents.count) / max(Double(foodByDay.count), 1)

            let outsideCount = foodEvents.filter { $0.food.source == .emailOrder || $0.food.source == .locationPrompt }.count
            let daysSpan = max(Double(foodByDay.count), 1) / 7.0
            profile.eatingOutFrequency = Double(outsideCount) / max(daysSpan, 1)

            let deliveryCount = foodEvents.filter { $0.food.source == .emailOrder }.count
            profile.foodDeliveryFrequency = Double(deliveryCount) / max(daysSpan, 1)

            // Typical meal times
            let breakfastHours = foodEvents.filter { $0.food.mealType == "breakfast" }.map { cal.component(.hour, from: $0.date) }
            let lunchHours = foodEvents.filter { $0.food.mealType == "lunch" }.map { cal.component(.hour, from: $0.date) }
            let dinnerHours = foodEvents.filter { $0.food.mealType == "dinner" }.map { cal.component(.hour, from: $0.date) }

            profile.typicalMealTimes = MealSchedule(
                typicalBreakfastHour: breakfastHours.isEmpty ? nil : breakfastHours.reduce(0, +) / breakfastHours.count,
                typicalLunchHour: lunchHours.isEmpty ? nil : lunchHours.reduce(0, +) / lunchHours.count,
                typicalDinnerHour: dinnerHours.isEmpty ? nil : dinnerHours.reduce(0, +) / dinnerHours.count
            )

            // Staple foods from FoodStore
            let staples = await FoodStore.shared.detectStapleFoods()
            profile.stapleFoods = staples
        }

        // MARK: Location Intelligence — outdoor time + routines
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now
        let locationVisits = events.compactMap { event -> (date: Date, loc: LocationEvent)? in
            guard event.timestamp >= thirtyDaysAgo else { return nil }
            if case .locationVisit(let l) = event.payload { return (event.timestamp, l) }
            return nil
        }

        if !locationVisits.isEmpty {
            profile.outdoorMinutesPerDay = Self.computeOutdoorMinutes(
                visits: locationVisits,
                since: thirtyDaysAgo,
                until: now,
                calendar: cal
            )

            profile.dailyRoutines = Self.buildDailyRoutines(
                visits: locationVisits,
                calendar: cal
            )

            profile.locationRoutines = Self.buildLocationRoutines(
                visits: locationVisits,
                calendar: cal
            )
        }

        profile.lastUpdated = now
        await UserProfileStore.shared.update(profile)
    }

    // MARK: - Routines + Outdoor Time Helpers

    /// Categories that indicate the user is physically outdoors.
    private static let outdoorCategories: Set<String> = [
        "park", "outdoor", "beach", "trail", "sport",
        "hike", "stadium", "garden"
    ]

    /// Sum outdoor dwell time across the window, divided by the number
    /// of distinct days with any location events — the "typical day".
    private static func computeOutdoorMinutes(
        visits: [(date: Date, loc: LocationEvent)],
        since: Date,
        until: Date,
        calendar: Calendar
    ) -> Double {
        var totalSeconds: Double = 0
        for v in visits {
            let category = v.loc.resolvedCategory?.lowercased() ?? ""
            let isOutdoor = outdoorCategories.contains(where: { category.contains($0) })
            // Short events with no category → treat as transit between places.
            let depart = v.loc.departureDate ?? v.loc.arrivalDate
            let dwell = depart.timeIntervalSince(v.loc.arrivalDate)
            let isTransit = category.isEmpty && dwell > 0 && dwell < 300
            if isOutdoor || isTransit {
                totalSeconds += max(0, dwell)
            }
        }
        let distinctDays = Set(visits.map { calendar.startOfDay(for: $0.date) }).count
        guard distinctDays > 0 else { return 0 }
        return (totalSeconds / 60.0) / Double(distinctDays)
    }

    /// Build the general daily routine — for each hour of the day,
    /// find the most-common resolvedCategory across the window, then
    /// collapse contiguous hours with the same category into TimeBlocks.
    /// Only emits blocks with confidence ≥ 0.4 (pattern holds on ≥40% of days).
    private static func buildDailyRoutines(
        visits: [(date: Date, loc: LocationEvent)],
        calendar: Calendar
    ) -> [TimeBlock] {
        guard !visits.isEmpty else { return [] }
        return buildBlocks(from: visits, calendar: calendar)
    }

    /// Build per-day-of-week routines (weekday vs weekend split is enough
    /// for a first pass — most users have clear weekday vs weekend patterns).
    private static func buildLocationRoutines(
        visits: [(date: Date, loc: LocationEvent)],
        calendar: Calendar
    ) -> [DayOfWeekRoutine] {
        let weekday = visits.filter { v in
            let w = calendar.component(.weekday, from: v.date)
            return w >= 2 && w <= 6  // Mon-Fri
        }
        let weekend = visits.filter { v in
            let w = calendar.component(.weekday, from: v.date)
            return w == 1 || w == 7  // Sun, Sat
        }

        var result: [DayOfWeekRoutine] = []

        if !weekday.isEmpty {
            let blocks = buildBlocks(from: weekday, calendar: calendar)
            if !blocks.isEmpty {
                // Emit one DayOfWeekRoutine per weekday with the same blocks.
                for day in 2...6 {
                    result.append(DayOfWeekRoutine(dayOfWeek: day, blocks: blocks))
                }
            }
        }
        if !weekend.isEmpty {
            let blocks = buildBlocks(from: weekend, calendar: calendar)
            if !blocks.isEmpty {
                for day in [1, 7] {
                    result.append(DayOfWeekRoutine(dayOfWeek: day, blocks: blocks))
                }
            }
        }
        return result
    }

    /// Core routine-extraction algorithm shared by buildDailyRoutines and
    /// buildLocationRoutines.
    private static func buildBlocks(
        from visits: [(date: Date, loc: LocationEvent)],
        calendar: Calendar
    ) -> [TimeBlock] {
        let distinctDays = Set(visits.map { calendar.startOfDay(for: $0.date) }).count
        guard distinctDays > 0 else { return [] }

        // For each hour, tally categories observed during that hour.
        var hourCategoryCounts: [Int: [String: Int]] = [:]
        for v in visits {
            let category = v.loc.resolvedCategory?.lowercased() ?? "unknown"
            guard category != "unknown" else { continue }
            let depart = v.loc.departureDate ?? v.loc.arrivalDate
            let startHour = calendar.component(.hour, from: v.loc.arrivalDate)
            let endHour = calendar.component(.hour, from: depart)
            // Handle visits that span midnight by capping at end-of-day for this day.
            let start = startHour
            let end = max(start, min(endHour, 23))
            for h in start...end {
                hourCategoryCounts[h, default: [:]][category, default: 0] += 1
            }
        }

        // For each hour, pick the dominant category + its confidence.
        struct HourSlot {
            let hour: Int
            let category: String
            let confidence: Double
        }
        var slots: [HourSlot] = []
        for h in 0..<24 {
            guard let counts = hourCategoryCounts[h],
                  let top = counts.max(by: { $0.value < $1.value }) else { continue }
            let confidence = Double(top.value) / Double(distinctDays)
            if confidence >= 0.4 {
                slots.append(HourSlot(hour: h, category: top.key, confidence: confidence))
            }
        }

        // Collapse contiguous hours with the same category into TimeBlocks.
        var blocks: [TimeBlock] = []
        var idx = 0
        while idx < slots.count {
            let start = slots[idx]
            var end = start
            var j = idx + 1
            while j < slots.count,
                  slots[j].hour == end.hour + 1,
                  slots[j].category == start.category {
                end = slots[j]
                j += 1
            }
            let label = friendlyRoutineLabel(for: start.category)
            let avgConfidence = (start.confidence + end.confidence) / 2.0
            blocks.append(TimeBlock(
                startHour: start.hour,
                endHour: end.hour,
                label: label,
                confidence: avgConfidence
            ))
            idx = j
        }

        return blocks
    }

    /// Map a raw place category into a user-friendly routine label.
    private static func friendlyRoutineLabel(for category: String) -> String {
        let c = category.lowercased()
        if c.contains("home") || c.contains("residence") { return "At home" }
        if c.contains("work") || c.contains("office") { return "At work" }
        if c.contains("gym") || c.contains("fitness") { return "At the gym" }
        if c.contains("restaurant") || c.contains("cafe") || c.contains("food") { return "Eating out" }
        if c.contains("park") || c.contains("outdoor") { return "Outdoors" }
        if c.contains("school") || c.contains("university") || c.contains("education") { return "At school" }
        if c.contains("shop") || c.contains("store") || c.contains("market") { return "Shopping" }
        return category.capitalized
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private func saveInsights() {
        do {
            let data = try encoder.encode(insights)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
        }
    }

    private func loadInsights() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            insights = try decoder.decode([Insight].self, from: data)
        } catch {
            insights = []
        }
    }

    private func pruneExpiredInsights() {
        insights.removeAll { !$0.isActive }
        // Keep max 100 insights
        if insights.count > 100 {
            insights = Array(insights.suffix(100))
        }
    }
}
