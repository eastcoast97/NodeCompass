import Foundation

/// Protocol all data collectors conform to.
/// Each collector gathers events from a specific source (GPS, HealthKit, etc.)
/// and converts them into LifeEvents for the EventStore.
protocol DataCollector {
    /// Which source this collector provides.
    var source: EventSource { get }

    /// Whether the user has granted the necessary permissions.
    var isAuthorized: Bool { get async }

    /// Request the necessary permissions from the user.
    func requestAuthorization() async throws

    /// Collect new events since last collection.
    func collect() async throws -> [LifeEvent]
}
