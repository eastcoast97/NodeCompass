import Foundation

/// Persistent store for LifeEvents.
/// Uses actor isolation (not @MainActor) because background collectors write from off-main threads.
actor EventStore {
    static let shared = EventStore()

    private(set) var events: [LifeEvent] = []
    private var deduplicationKeys: Set<String> = []
    private let fileName = "life_events.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
    }

    // MARK: - Public API

    /// Append a single event, deduplicating by key.
    @discardableResult
    func append(_ event: LifeEvent) -> Bool {
        let key = event.deduplicationKey
        guard !deduplicationKeys.contains(key) else { return false }

        events.append(event)
        deduplicationKeys.insert(key)
        trimIfNeeded()
        saveToDisk()
        return true
    }

    /// Append multiple events, deduplicating each.
    func appendBatch(_ newEvents: [LifeEvent]) {
        var added = 0
        for event in newEvents {
            let key = event.deduplicationKey
            guard !deduplicationKeys.contains(key) else { continue }
            events.append(event)
            deduplicationKeys.insert(key)
            added += 1
        }
        if added > 0 {
            trimIfNeeded()
            saveToDisk()
        }
    }

    /// Update metadata on an existing event.
    func updateMetadata(eventId: String, metadata: EventMetadata) {
        guard let index = events.firstIndex(where: { $0.id == eventId }) else { return }
        events[index].metadata = metadata
        saveToDisk()
    }

    // MARK: - Queries

    /// All events since a given date, optionally filtered by source.
    func events(since date: Date, source: EventSource? = nil) -> [LifeEvent] {
        events.filter { event in
            event.timestamp >= date &&
            (source == nil || event.source == source)
        }
    }

    /// Events within a date range, optionally filtered by multiple sources.
    func events(from start: Date, to end: Date, sources: [EventSource]? = nil) -> [LifeEvent] {
        events.filter { event in
            event.timestamp >= start && event.timestamp <= end &&
            (sources == nil || sources!.contains(event.source))
        }
    }

    /// Most recent N events.
    func recentEvents(limit: Int = 50) -> [LifeEvent] {
        Array(events.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// All transaction events (for spending analysis).
    func transactionEvents(since date: Date) -> [TransactionEvent] {
        events(since: date, source: nil).compactMap { event in
            if case .transaction(let t) = event.payload { return t }
            return nil
        }
    }

    /// Count of events by source.
    var eventCounts: [EventSource: Int] {
        Dictionary(grouping: events, by: { $0.source })
            .mapValues { $0.count }
    }

    /// Total event count.
    var totalCount: Int { events.count }

    /// Clear all events (called when user clears data).
    func clearAll() {
        events = []
        deduplicationKeys = []
        saveToDisk()
    }

    // MARK: - Persistence

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private func saveToDisk() {
        do {
            let data = try encoder.encode(events)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            events = try decoder.decode([LifeEvent].self, from: data)
            deduplicationKeys = Set(events.map { $0.deduplicationKey })
        } catch {
            events = []
        }
    }

    /// Keep events for the last 6 months to prevent unbounded growth.
    private func trimIfNeeded() {
        let sixMonthsAgo = Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        let before = events.count
        events.removeAll { $0.timestamp < sixMonthsAgo }
        if events.count < before {
            deduplicationKeys = Set(events.map { $0.deduplicationKey })
        }
    }
}
