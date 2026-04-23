import Foundation
import CoreLocation

/// Collects location data passively using significant location changes + visit monitoring.
/// Battery-efficient: uses CLVisit (system-managed) + significant change (cell tower based).
/// Never uses continuous GPS — all tracking is passive and low-power.
class LocationCollector: NSObject, DataCollector, CLLocationManagerDelegate, ObservableObject {
    static let shared = LocationCollector()

    let source: EventSource = .location
    private let locationManager = CLLocationManager()
    private let placeResolver = PlaceResolver.shared
    private let lastCollectionKey = "location_last_collection"

    /// Categories to SKIP for quick-visit logging — everything else gets logged.
    /// Only residential is skipped because CLVisit handles home detection naturally.
    private let skipQuickVisitCategories: Set<String> = ["residential"]

    /// Track last quick-visit coordinate to avoid duplicates at same spot
    private var lastQuickVisitKey: String?

    /// Track recently notified places to prevent duplicate food notifications
    /// from both CLVisit and significantLocationChange firing for the same visit.
    /// Key: grid cell key, Value: timestamp when notification was sent.
    private var recentlyNotifiedPlaces: [String: Date] = [:]

    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking = false

    var isAuthorized: Bool {
        get async {
            let status = locationManager.authorizationStatus
            return status == .authorizedAlways
        }
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = locationManager.authorizationStatus
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        let status = locationManager.authorizationStatus

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Wait for callback — user will need to upgrade to Always later
        } else if status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }
    }

    // MARK: - Start/Stop Tracking

    /// Request permission and start tracking (called from Settings toggle).
    func requestPermissionAndStart() {
        let status = locationManager.authorizationStatus
        UserDefaults.standard.set(true, forKey: "locationTrackingEnabled")

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Tracking starts automatically in didChangeAuthorization callback
        } else if status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
            startTracking()
        } else if status == .authorizedAlways {
            startTracking()
        }
    }

    /// Start passive location monitoring.
    func startTracking() {
        guard locationManager.authorizationStatus == .authorizedAlways ||
              locationManager.authorizationStatus == .authorizedWhenInUse else { return }

        locationManager.startMonitoringSignificantLocationChanges()
        locationManager.startMonitoringVisits()
        isTracking = true
    }

    func stopTracking() {
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.stopMonitoringVisits()
        isTracking = false
        UserDefaults.standard.set(false, forKey: "locationTrackingEnabled")
    }

    // MARK: - DataCollector

    func collect() async throws -> [LifeEvent] {
        // Location events are pushed via delegate callbacks, not pulled
        // This method returns any pending events from the visit buffer
        return []
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }

        if manager.authorizationStatus == .authorizedAlways ||
           manager.authorizationStatus == .authorizedWhenInUse {
            startTracking()
        }
    }

    /// Called when the system detects a visit (arrival/departure at a place).
    /// This is the primary data source — extremely battery efficient.
    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let lat = visit.coordinate.latitude
        let lon = visit.coordinate.longitude

        // Skip invalid visits
        guard lat != 0, lon != 0 else { return }
        guard visit.arrivalDate != .distantPast else { return }

        Task {
            // Resolve the place name, category, and rich details (menu/reviews from Google)
            let place = await placeResolver.resolveWithDetails(latitude: lat, longitude: lon)

            let locationEvent = LocationEvent(
                latitude: lat,
                longitude: lon,
                horizontalAccuracy: visit.horizontalAccuracy,
                arrivalDate: visit.arrivalDate,
                departureDate: visit.departureDate == .distantFuture ? nil : visit.departureDate,
                resolvedPlaceName: place?.name,
                resolvedCategory: place?.category
            )

            let lifeEvent = LifeEvent(
                timestamp: visit.arrivalDate,
                source: .location,
                payload: .locationVisit(locationEvent)
            )

            let added = await EventStore.shared.append(lifeEvent)
            if added {
                // Update profile with this location
                await updateFrequentLocations(lat: lat, lon: lon, place: place, arrivalDate: visit.arrivalDate)

                // Broadcast cross-pillar signals so other engines react in real-time
                await broadcastPlaceVisit(lat: lat, lon: lon, place: place)

                // Check if this is a restaurant — prompt food logging.
                // Guard against duplicate notifications from both CLVisit and
                // significantLocationChange firing for the same physical visit.
                let gridKey = "\(Int(lat * Config.Location.gridCellMultiplier))_\(Int(lon * Config.Location.gridCellMultiplier))"
                if let placeName = place?.name, !wasRecentlyNotified(gridKey: gridKey) {
                    markAsNotified(gridKey: gridKey)
                    FoodAutoDetector.checkLocationVisit(
                        placeName: placeName,
                        category: place?.category,
                        arrivalDate: visit.arrivalDate,
                        placeDetails: place?.details
                    )
                }
            }
        }
    }

    /// Significant location change — doubles as a quick-visit detector.
    /// When you arrive near a recognizable place (restaurant, store, gym, etc.),
    /// it logs it immediately instead of waiting for CLVisit's 5-10 min dwell time.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Throttle: at least 2 minutes between quick-visit checks
        let lastCollection = UserDefaults.standard.double(forKey: lastCollectionKey)
        let now = Date().timeIntervalSince1970
        guard now - lastCollection > Config.Location.quickVisitThrottleSeconds else { return }
        UserDefaults.standard.set(now, forKey: lastCollectionKey)

        // De-duplicate: skip if we're still at the same ~50m grid cell
        let gridKey = "\(Int(location.coordinate.latitude * Config.Location.gridCellMultiplier))_\(Int(location.coordinate.longitude * Config.Location.gridCellMultiplier))"
        guard gridKey != lastQuickVisitKey else { return }

        Task {
            let place = await placeResolver.resolveWithDetails(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            let category = place?.category ?? "other"

            // Log all places except residential — any place you physically visit matters.
            // Residential is skipped because CLVisit handles home detection naturally.
            let isQuickVisit = !skipQuickVisitCategories.contains(category)

            let locationEvent = LocationEvent(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                horizontalAccuracy: location.horizontalAccuracy,
                arrivalDate: location.timestamp,
                departureDate: nil,
                resolvedPlaceName: place?.name,
                resolvedCategory: category
            )

            let lifeEvent = LifeEvent(
                timestamp: location.timestamp,
                source: .location,
                payload: .locationVisit(locationEvent)
            )

            let added = await EventStore.shared.append(lifeEvent)
            if added {
                lastQuickVisitKey = gridKey

                if isQuickVisit {
                    // Update profile with this location
                    await updateFrequentLocations(
                        lat: location.coordinate.latitude,
                        lon: location.coordinate.longitude,
                        place: place,
                        arrivalDate: location.timestamp
                    )

                    // Broadcast cross-pillar signals so other engines react in real-time
                    await broadcastPlaceVisit(
                        lat: location.coordinate.latitude,
                        lon: location.coordinate.longitude,
                        place: place
                    )

                    // Check if restaurant — prompt food logging, guarding
                    // against duplicates from the CLVisit delegate also firing.
                    if let placeName = place?.name, !wasRecentlyNotified(gridKey: gridKey) {
                        markAsNotified(gridKey: gridKey)
                        FoodAutoDetector.checkLocationVisit(
                            placeName: placeName,
                            category: place?.category,
                            arrivalDate: location.timestamp,
                            placeDetails: place?.details
                        )
                    }
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationCollector] Error: \(error.localizedDescription)")
    }

    // MARK: - Notification Deduplication

    /// Check if a food notification was recently sent for this grid cell.
    private func wasRecentlyNotified(gridKey: String) -> Bool {
        pruneExpiredNotifications()
        return recentlyNotifiedPlaces[gridKey] != nil
    }

    /// Mark a grid cell as recently notified.
    private func markAsNotified(gridKey: String) {
        recentlyNotifiedPlaces[gridKey] = Date()
    }

    /// Remove expired entries to prevent memory growth.
    private func pruneExpiredNotifications() {
        let cutoff = Date().addingTimeInterval(-Config.Location.foodNotificationCooldownSeconds)
        recentlyNotifiedPlaces = recentlyNotifiedPlaces.filter { $0.value > cutoff }
    }

    // MARK: - Profile Update

    private func updateFrequentLocations(lat: Double, lon: Double, place: PlaceResolver.ResolvedPlace?, arrivalDate: Date) async {
        var profile = await UserProfileStore.shared.currentProfile()

        // Check if this is near an existing frequent location (within 100m)
        if let index = profile.frequentLocations.firstIndex(where: { $0.distance(to: lat, lon) < Config.Location.sameLocationRadiusMeters }) {
            // Update existing location
            profile.frequentLocations[index].visitCount += 1
            profile.frequentLocations[index].lastVisit = arrivalDate

            // Track visit dates for pattern detection (keep last 30)
            var dates = profile.frequentLocations[index].visitDates ?? []
            dates.append(arrivalDate)
            if dates.count > 30 { dates = Array(dates.suffix(30)) }
            profile.frequentLocations[index].visitDates = dates

            // Update resolved place info
            if let resolvedType = place?.category {
                profile.frequentLocations[index].inferredType = resolvedType
            }
            if let name = place?.name, profile.frequentLocations[index].label == nil {
                profile.frequentLocations[index].label = name
            }

            // Enrich with Google Places data if available
            enrichLocation(&profile.frequentLocations[index], with: place)

            // Recalculate behavioral intelligence with updated visit history
            let loc = profile.frequentLocations[index]
            profile.frequentLocations[index].typicalVisitDay = PlaceIntelligence.typicalVisitDay(from: loc.visitDates ?? [])
            profile.frequentLocations[index].typicalVisitHour = PlaceIntelligence.typicalVisitHour(from: loc.visitDates ?? [])
            profile.frequentLocations[index].behaviorTag = PlaceIntelligence.inferBehaviorTag(
                category: loc.inferredType,
                googleTypes: loc.googleTypes,
                visitCount: loc.visitCount,
                typicalVisitHour: loc.typicalVisitHour,
                typicalVisitDay: loc.typicalVisitDay,
                totalSpent: loc.totalSpent,
                rating: loc.rating,
                priceLevel: loc.priceLevel
            )
            profile.frequentLocations[index].pillarTags = PlaceIntelligence.pillarTags(
                category: loc.inferredType,
                googleTypes: loc.googleTypes,
                totalSpent: loc.totalSpent,
                visitCount: loc.visitCount
            )

            // Persist totalSpent by correlating transactions with this place
            if let label = loc.label, !label.isEmpty, label.lowercased() != "unknown" {
                let placeName = label.lowercased()
                let spent = await MainActor.run {
                    TransactionStore.shared.transactions
                        .filter { $0.type.lowercased() != "credit" }
                        .filter { txn in
                            let merchant = txn.merchant.lowercased()
                            return merchant.contains(placeName) || placeName.contains(merchant)
                        }
                        .reduce(0.0) { $0 + $1.amount }
                }
                if spent > 0 {
                    profile.frequentLocations[index].totalSpent = spent
                }
            }
        } else {
            // New frequent location — build it fully enriched
            var newLocation = FrequentLocation(
                id: UUID().uuidString,
                latitude: lat,
                longitude: lon,
                label: place?.name,
                inferredType: place?.category,
                visitCount: 1,
                averageDurationMinutes: 0,
                lastVisit: arrivalDate,
                visitDates: [arrivalDate]
            )

            // Enrich with Google Places data
            enrichLocation(&newLocation, with: place)

            // Initial behavioral classification
            newLocation.behaviorTag = PlaceIntelligence.inferBehaviorTag(
                category: newLocation.inferredType,
                googleTypes: newLocation.googleTypes,
                visitCount: 1,
                typicalVisitHour: Calendar.current.component(.hour, from: arrivalDate),
                typicalVisitDay: Calendar.current.component(.weekday, from: arrivalDate),
                totalSpent: nil,
                rating: newLocation.rating,
                priceLevel: newLocation.priceLevel
            )
            newLocation.pillarTags = PlaceIntelligence.pillarTags(
                category: newLocation.inferredType,
                googleTypes: newLocation.googleTypes,
                totalSpent: nil,
                visitCount: 1
            )

            profile.frequentLocations.append(newLocation)

            // Keep top N locations
            if profile.frequentLocations.count > Config.Location.maxFrequentLocations {
                profile.frequentLocations.sort { $0.visitCount > $1.visitCount }
                profile.frequentLocations = Array(profile.frequentLocations.prefix(Config.Location.maxFrequentLocations))
            }
        }

        await UserProfileStore.shared.update(profile)
    }

    // MARK: - Cross-Service Broadcasting

    /// After a place visit is resolved and profile updated, broadcast signals
    /// so HabitAutoTracker, PatternEngine, and other engines react in real-time.
    private func broadcastPlaceVisit(lat: Double, lon: Double, place: PlaceResolver.ResolvedPlace?) async {
        // Small delay to allow the profile write from updateFrequentLocations to persist
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Find the FrequentLocation we just updated/created
        let profile = await UserProfileStore.shared.currentProfile()
        guard let frequentLoc = profile.frequentLocations.first(where: {
            $0.distance(to: lat, lon) < Config.Location.sameLocationRadiusMeters
        }) else {
            // Fallback: still broadcast with basic info so habits can evaluate
            let category = place?.category ?? "other"
            let info: [String: String] = [
                "category": category,
                "behaviorTag": "",
                "locationId": ""
            ]
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("PlaceVisitDetected"),
                    object: nil,
                    userInfo: info
                )
            }
            return
        }

        // Generate cross-pillar signals from PlaceIntelligence
        let recentSpend = await MainActor.run {
            let label = frequentLoc.label?.lowercased() ?? ""
            guard !label.isEmpty, label != "unknown" else { return nil as Double? }
            let cal = Calendar.current
            return TransactionStore.shared.transactions
                .filter { cal.isDateInToday($0.date) && $0.type.lowercased() != "credit" }
                .filter { $0.merchant.lowercased().contains(label) || label.contains($0.merchant.lowercased()) }
                .reduce(0.0) { $0 + $1.amount } as Double?
        }

        // Generate signals — these can be consumed by any listener that reads the profile
        let _ = PlaceIntelligence.crossPillarSignals(
            place: frequentLoc,
            recentSpend: recentSpend
        )

        // Post lightweight notification — listeners (HabitAutoTracker, etc.) re-gather
        // their own signals from the now-updated profile. This avoids passing Swift
        // value types through NSNotification userInfo.
        let info: [String: String] = [
            "category": frequentLoc.inferredType ?? "other",
            "behaviorTag": frequentLoc.behaviorTag ?? "",
            "locationId": frequentLoc.id
        ]

        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("PlaceVisitDetected"),
                object: nil,
                userInfo: info
            )
        }

        // Trigger PatternEngine analysis (it has its own 60s debounce)
        await PatternEngine.shared.runAnalysis()
    }

    /// Populate Google Places enrichment fields on a FrequentLocation.
    private func enrichLocation(_ location: inout FrequentLocation, with place: PlaceResolver.ResolvedPlace?) {
        guard let place = place else { return }

        // Google Place ID for future lookups
        if let placeId = place.placeId {
            location.googlePlaceId = placeId
        }

        // Address
        if let address = place.address {
            location.address = address
        }

        // Rich details from Place Details API
        if let details = place.details {
            location.priceLevel = details.priceLevel
            location.rating = details.rating
            location.editorialSummary = details.editorialSummary

            // Store all Google types for behavioral analysis
            if !details.allTypes.isEmpty {
                location.googleTypes = details.allTypes
            } else if !details.cuisineTypes.isEmpty {
                location.googleTypes = details.cuisineTypes
            }

            // Popular items (from review extraction)
            if !details.popularItems.isEmpty {
                location.popularItems = details.popularItems
            }
        }
    }
}
