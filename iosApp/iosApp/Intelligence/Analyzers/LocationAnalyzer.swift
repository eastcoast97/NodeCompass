import Foundation

/// Analyzes location events to produce insights about places, routines, and spending correlations.
struct LocationAnalyzer {

    /// Analyze location events and produce insights.
    static func analyze(events: [LifeEvent], profile: UserProfile) -> [Insight] {
        let locationEvents = events.compactMap { event -> (event: LifeEvent, loc: LocationEvent)? in
            if case .locationVisit(let l) = event.payload { return (event, l) }
            return nil
        }
        guard locationEvents.count >= 3 else { return [] }

        var insights: [Insight] = []

        // 1. Frequent places
        insights.append(contentsOf: frequentPlaceInsights(profile: profile))

        // 2. Eating out pattern
        if let eatingInsight = eatingOutPattern(locationEvents: locationEvents) {
            insights.append(eatingInsight)
        }

        // 3. Spending-location correlation
        insights.append(contentsOf: spendingLocationCorrelation(events: events))

        // 4. Routine detection
        if let routineInsight = routineInsight(locationEvents: locationEvents) {
            insights.append(routineInsight)
        }

        return insights
    }

    // MARK: - Frequent Places

    private static func frequentPlaceInsights(profile: UserProfile) -> [Insight] {
        let frequentPlaces = profile.frequentLocations
            .filter { $0.visitCount >= 5 && $0.inferredType != "residential" }
            .sorted { $0.visitCount > $1.visitCount }
            .prefix(3)

        return frequentPlaces.compactMap { place in
            guard let label = place.label ?? place.inferredType else { return nil }
            return Insight(
                type: .routine,
                title: "\(label) — visited \(place.visitCount) times",
                body: "This is one of your most visited spots. You were last here \(timeAgo(place.lastVisit)).",
                priority: .low,
                category: "location"
            )
        }
    }

    // MARK: - Eating Out Pattern

    private static func eatingOutPattern(locationEvents: [(event: LifeEvent, loc: LocationEvent)]) -> Insight? {
        let cal = Calendar.current
        let fourWeeksAgo = cal.date(byAdding: .weekOfYear, value: -4, to: Date())!

        let recentRestaurants = locationEvents.filter {
            $0.event.timestamp >= fourWeeksAgo && $0.loc.resolvedCategory == "restaurant"
        }

        guard recentRestaurants.count >= 3 else { return nil }

        let perWeek = Double(recentRestaurants.count) / 4.0

        // Find the most common day
        let dayGroups = Dictionary(grouping: recentRestaurants) {
            cal.component(.weekday, from: $0.event.timestamp)
        }
        let topDay = dayGroups.max(by: { $0.value.count < $1.value.count })
        let dayName = topDay.map { dayOfWeekName($0.key) } ?? ""

        return Insight(
            type: .eatingPattern,
            title: "Eating out \(String(format: "%.0f", perWeek))x/week",
            body: "You've visited restaurants \(recentRestaurants.count) times in 4 weeks\(dayName.isEmpty ? "" : ", most often on \(dayName)s").",
            priority: perWeek >= 5 ? .medium : .low,
            category: "location"
        )
    }

    // MARK: - Spending-Location Correlation

    private static func spendingLocationCorrelation(events: [LifeEvent]) -> [Insight] {
        let cal = Calendar.current
        let oneWeekAgo = cal.date(byAdding: .day, value: -7, to: Date())!

        // Get recent location visits
        let recentVisits = events.compactMap { event -> (date: Date, loc: LocationEvent)? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .locationVisit(let l) = event.payload { return (event.timestamp, l) }
            return nil
        }

        // Get recent transactions
        let recentTxns = events.compactMap { event -> (date: Date, txn: TransactionEvent)? in
            guard event.timestamp >= oneWeekAgo else { return nil }
            if case .transaction(let t) = event.payload, !t.isCredit { return (event.timestamp, t) }
            return nil
        }

        var insights: [Insight] = []

        // Find transactions near restaurant visits (within 2 hours)
        for visit in recentVisits where visit.loc.resolvedCategory == "restaurant" {
            let nearbyTxns = recentTxns.filter {
                abs($0.date.timeIntervalSince(visit.date)) < 7200 // 2 hours
            }

            for txn in nearbyTxns {
                if txn.txn.category.lowercased().contains("food") || txn.txn.category.lowercased().contains("dining") {
                    let placeName = visit.loc.resolvedPlaceName ?? "a restaurant"
                    insights.append(Insight(
                        type: .locationCorrelation,
                        title: "Spent $\(String(format: "%.0f", txn.txn.amount)) near \(placeName)",
                        body: "\(txn.txn.merchant) charge matches your visit to \(placeName).",
                        priority: .low,
                        category: "location",
                        expiresAt: cal.date(byAdding: .day, value: 5, to: Date())
                    ))
                }
            }
        }

        return Array(insights.prefix(3)) // Cap at 3 correlation insights
    }

    // MARK: - Routine Detection

    private static func routineInsight(locationEvents: [(event: LifeEvent, loc: LocationEvent)]) -> Insight? {
        let cal = Calendar.current
        let twoWeeksAgo = cal.date(byAdding: .weekOfYear, value: -2, to: Date())!

        let gymVisits = locationEvents.filter {
            $0.event.timestamp >= twoWeeksAgo && $0.loc.resolvedCategory == "gym"
        }

        guard gymVisits.count >= 3 else { return nil }

        let perWeek = Double(gymVisits.count) / 2.0

        // Find typical time
        let hours = gymVisits.map { cal.component(.hour, from: $0.event.timestamp) }
        let avgHour = hours.reduce(0, +) / hours.count
        let timeLabel = avgHour < 12 ? "mornings" : avgHour < 17 ? "afternoons" : "evenings"

        return Insight(
            type: .healthPattern,
            title: "Gym \(String(format: "%.0f", perWeek))x/week",
            body: "You've hit the gym \(gymVisits.count) times in 2 weeks, usually in the \(timeLabel).",
            priority: .low,
            category: "health"
        )
    }

    // MARK: - Helpers

    private static func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func dayOfWeekName(_ day: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        return day >= 1 && day <= 7 ? names[day] : ""
    }
}
