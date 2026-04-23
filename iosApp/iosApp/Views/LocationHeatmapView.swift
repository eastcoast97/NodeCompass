import SwiftUI
import MapKit

/// Location heatmap — shows where you spend time and money.
struct LocationHeatmapView: View {
    @StateObject private var vm = LocationHeatmapViewModel()
    @State private var selectedPlace: LocationHeatmapViewModel.PlaceCluster?
    @State private var showDetail = false
    @State private var selectedFilter: PlaceCategoryFilter = .all

    enum PlaceCategoryFilter: String, CaseIterable {
        case all = "All"
        case restaurant = "Food & Drink"
        case store = "Shopping"
        case gym = "Fitness"
        case medical = "Medical"
        case park = "Outdoors"
        case transit = "Transit"
        case education = "Education"
        case office = "Work"
        case other = "Other"

        var icon: String {
            switch self {
            case .all: return "map.fill"
            case .restaurant: return "fork.knife"
            case .store: return "bag.fill"
            case .gym: return "figure.run"
            case .medical: return "cross.fill"
            case .park: return "leaf.fill"
            case .transit: return "tram.fill"
            case .education: return "book.fill"
            case .office: return "building.2.fill"
            case .other: return "mappin.circle.fill"
            }
        }

        func matches(_ category: String?) -> Bool {
            guard self != .all else { return true }
            guard let cat = category?.lowercased() else { return self == .other }
            switch self {
            case .all: return true
            case .restaurant: return ["restaurant", "cafe", "food", "bar"].contains(cat)
            case .store: return ["store", "shopping"].contains(cat)
            case .gym: return ["gym", "fitness"].contains(cat)
            case .medical: return ["medical", "health"].contains(cat)
            case .park: return ["park", "outdoor"].contains(cat)
            case .transit: return ["transit", "transport"].contains(cat)
            case .education: return ["education"].contains(cat)
            case .office: return ["office", "work"].contains(cat)
            case .other: return !["restaurant", "cafe", "food", "bar", "store", "shopping",
                                   "gym", "fitness", "medical", "health", "park", "outdoor",
                                   "transit", "transport", "education", "office", "work"].contains(cat)
            }
        }
    }

    private var filteredPlaces: [LocationHeatmapViewModel.PlaceCluster] {
        vm.places.filter { selectedFilter.matches($0.category) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    // Category filter chips
                    categoryFilterBar
                        .padding(.top, 4)

                    // Map
                    Map(position: $vm.cameraPosition, selection: $selectedPlace) {
                        ForEach(filteredPlaces) { place in
                            Annotation(place.name, coordinate: place.coordinate) {
                                PlacePin(place: place, isSelected: selectedPlace?.id == place.id)
                            }
                            .tag(place)
                        }
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                }

                // Bottom panel
                VStack(spacing: 0) {
                    if let place = selectedPlace {
                        placeDetailCard(place)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        summaryPanel
                    }
                }
                .animation(.spring(response: 0.3), value: selectedPlace?.id)
            }
            .navigationTitle("Places")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
        }
    }

    // MARK: - Summary Panel

    private var summaryPanel: some View {
        VStack(spacing: 12) {
            // Stats row
            HStack(spacing: 0) {
                statColumn(value: "\(filteredPlaces.count)", label: "Places", icon: "mappin.circle.fill", color: .blue)
                Divider().frame(height: 30)
                statColumn(value: "\(filteredPlaces.reduce(0) { $0 + $1.visitCount })", label: "Visits", icon: "figure.walk", color: .orange)
                Divider().frame(height: 30)
                statColumn(value: NC.money(filteredPlaces.reduce(0) { $0 + $1.totalSpent }), label: "Spent", icon: NC.currencyIconCircle, color: NC.teal)
            }

            // Top places list
            let topFiltered = filteredPlaces.sorted { $0.visitCount > $1.visitCount }
            if !topFiltered.isEmpty {
                VStack(spacing: 8) {
                    ForEach(topFiltered.prefix(3)) { place in
                        Button {
                            selectedPlace = place
                            vm.focusOn(place)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: categoryIcon(place.category))
                                    .font(.caption)
                                    .foregroundStyle(categoryColor(place.category))
                                    .frame(width: 30, height: 30)
                                    .background(categoryColor(place.category).opacity(0.1), in: Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 4) {
                                        Text("\(place.visitCount) visits")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if let tag = place.behaviorTag {
                                            Text("\u{2022} \(formatBehaviorTag(tag))")
                                                .font(.caption2)
                                                .foregroundStyle(behaviorTagColor(tag))
                                        }
                                    }
                                }

                                Spacer()

                                if place.totalSpent > 0 {
                                    Text(NC.money(place.totalSpent))
                                        .font(.caption.bold())
                                        .foregroundStyle(NC.teal)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(NC.hPad)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, NC.hPad)
        .padding(.bottom, 8)
    }

    // MARK: - Place Detail Card

    private func placeDetailCard(_ place: LocationHeatmapViewModel.PlaceCluster) -> some View {
        VStack(spacing: 14) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: categoryIcon(place.category))
                    .font(.title3)
                    .foregroundStyle(categoryColor(place.category))
                    .frame(width: 44, height: 44)
                    .background(categoryColor(place.category).opacity(0.1), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.headline)
                    if let category = place.category {
                        Text(category.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    selectedPlace = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5), in: Circle())
                }
            }

            // Stats
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("\(place.visitCount)")
                        .font(.title3.bold())
                    Text("Visits")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text(place.avgDuration)
                        .font(.title3.bold())
                    Text("Avg Time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                if place.totalSpent > 0 {
                    Divider().frame(height: 30)
                    VStack(spacing: 4) {
                        Text(NC.money(place.totalSpent))
                            .font(.title3.bold())
                            .foregroundStyle(NC.teal)
                        Text("Spent")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Behavior tag + pillar badges
            if place.behaviorTag != nil || !(place.pillarTags ?? []).isEmpty {
                HStack(spacing: 6) {
                    if let tag = place.behaviorTag {
                        Text(formatBehaviorTag(tag))
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(behaviorTagColor(tag), in: Capsule())
                    }
                    ForEach(place.pillarTags ?? [], id: \.self) { pillar in
                        Image(systemName: pillarIcon(pillar))
                            .font(.caption2)
                            .foregroundStyle(pillarColor(pillar))
                    }
                    Spacer()
                    if let rating = place.rating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", rating))
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Editorial summary
            if let summary = place.editorialSummary {
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Popular items
            if let items = place.popularItems, !items.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text(items.prefix(3).joined(separator: " \u{2022} "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Last visit + address
            HStack(spacing: 6) {
                if let lastVisit = place.lastVisit {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(lastVisit, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let address = place.address {
                    Spacer()
                    Text(address)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(NC.hPad)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, NC.hPad)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private func statColumn(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryIcon(_ category: String?) -> String {
        switch category?.lowercased() {
        case "restaurant", "food": return "fork.knife"
        case "gym", "fitness": return "figure.run"
        case "store", "shopping": return "bag.fill"
        case "medical", "health": return "cross.fill"
        case "transit", "transport": return "tram.fill"
        case "park", "outdoor": return "leaf.fill"
        case "work", "office": return "building.2.fill"
        case "home", "residence": return "house.fill"
        default: return "mappin.circle.fill"
        }
    }

    private func categoryColor(_ category: String?) -> Color {
        switch category?.lowercased() {
        case "restaurant", "food": return NC.food
        case "gym", "fitness": return .pink
        case "store", "shopping": return .purple
        case "medical", "health": return NC.teal
        case "park", "outdoor": return .green
        case "work", "office": return .blue
        case "home", "residence": return .orange
        default: return .blue
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlaceCategoryFilter.allCases, id: \.rawValue) { filter in
                    let isActive = selectedFilter == filter
                    let count = vm.places.filter { filter.matches($0.category) }.count
                    if filter == .all || count > 0 {
                        Button {
                            Haptic.light()
                            withAnimation(.spring(response: 0.3)) {
                                selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(filter == .all ? "All" : filter.rawValue)
                                    .font(.caption2.weight(.medium))
                                if filter != .all {
                                    Text("\(count)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(isActive ? .white.opacity(0.8) : .secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isActive ? categoryColor(filter == .all ? nil : filter.rawValue.lowercased()) : Color(.systemGray6),
                                        in: Capsule())
                            .foregroundStyle(isActive ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, NC.hPad)
        }
    }

    // MARK: - Intelligence Helpers

    private func pillarIcon(_ pillar: String) -> String {
        switch pillar {
        case "wealth": return NC.currencyIconCircle
        case "health": return "heart.fill"
        case "mind": return "brain.head.profile"
        default: return "circle.fill"
        }
    }

    private func pillarColor(_ pillar: String) -> Color {
        switch pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "mind": return .purple
        default: return .gray
        }
    }

    private func formatBehaviorTag(_ tag: String) -> String {
        tag.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func behaviorTagColor(_ tag: String) -> Color {
        if tag.contains("routine") { return .blue }
        if tag.contains("coffee") || tag.contains("breakfast") { return .brown }
        if tag.contains("fitness") || tag.contains("outdoor") { return .pink }
        if tag.contains("dining") || tag.contains("lunch") || tag.contains("dinner") { return NC.food }
        if tag.contains("shopping") || tag.contains("grocery") { return .purple }
        if tag.contains("impulse") { return NC.warning }
        if tag.contains("dispensary") || tag.contains("liquor") { return .green }
        if tag.contains("commute") || tag.contains("work") { return .blue }
        if tag.contains("nightlife") { return .indigo }
        return .gray
    }
}

// MARK: - Place Pin

private struct PlacePin: View {
    let place: LocationHeatmapViewModel.PlaceCluster
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(pinColor.opacity(isSelected ? 0.3 : 0.15))
                .frame(width: pinSize + 12, height: pinSize + 12)

            Circle()
                .fill(pinColor)
                .frame(width: pinSize, height: pinSize)

            if place.visitCount > 1 {
                Text("\(place.visitCount)")
                    .font(.system(size: pinSize > 24 ? 10 : 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isSelected ? 1.3 : 1.0)
        .animation(.spring(response: 0.3), value: isSelected)
    }

    private var pinSize: CGFloat {
        let base: CGFloat = 20
        let scale = min(CGFloat(place.visitCount) * 3, 20)
        return base + scale
    }

    private var pinColor: Color {
        if place.totalSpent > 0 { return NC.teal }
        switch place.category?.lowercased() {
        case "restaurant": return NC.food
        case "gym": return .pink
        default: return .blue
        }
    }
}

// MARK: - ViewModel

@MainActor
class LocationHeatmapViewModel: ObservableObject {
    struct PlaceCluster: Identifiable, Hashable {
        let id: String
        let name: String
        let category: String?
        let coordinate: CLLocationCoordinate2D
        let visitCount: Int
        let totalSpent: Double
        let avgDuration: String
        let lastVisit: Date?

        // Enriched Place Intelligence
        let behaviorTag: String?
        let pillarTags: [String]?
        let rating: Double?
        let priceLevel: Int?
        let editorialSummary: String?
        let popularItems: [String]?
        let address: String?

        func hash(into hasher: inout Hasher) { hasher.combine(id) }
        static func == (lhs: PlaceCluster, rhs: PlaceCluster) -> Bool { lhs.id == rhs.id }
    }

    @Published var places: [PlaceCluster] = []
    @Published var cameraPosition: MapCameraPosition = .automatic

    var totalVisits: Int { places.reduce(0) { $0 + $1.visitCount } }
    var totalSpent: Double { places.reduce(0) { $0 + $1.totalSpent } }
    var topPlaces: [PlaceCluster] { places.sorted { $0.visitCount > $1.visitCount } }

    func load() async {
        let profile = await UserProfileStore.shared.profile
        let frequentLocations = profile.frequentLocations

        // Get transactions for spending correlation
        let transactions = await MainActor.run { TransactionStore.shared.transactions }

        places = frequentLocations.map { loc in
            let durationStr: String
            if loc.averageDurationMinutes >= 60 {
                durationStr = String(format: "%.1fh", loc.averageDurationMinutes / 60)
            } else if loc.averageDurationMinutes > 0 {
                durationStr = "\(Int(loc.averageDurationMinutes))m"
            } else {
                durationStr = "—"
            }

            // Correlate spending: match transactions whose merchant name
            // loosely matches the place label
            let placeName = (loc.label ?? "").lowercased()
            let spent: Double
            if !placeName.isEmpty && placeName != "unknown" {
                spent = transactions
                    .filter { $0.type != "credit" }
                    .filter { txn in
                        let merchant = txn.merchant.lowercased()
                        return merchant.contains(placeName) || placeName.contains(merchant)
                    }
                    .reduce(0) { $0 + $1.amount }
            } else {
                spent = 0
            }

            return PlaceCluster(
                id: loc.id,
                name: loc.label ?? loc.inferredType?.capitalized ?? "Unknown",
                category: loc.inferredType,
                coordinate: CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude),
                visitCount: loc.visitCount,
                totalSpent: spent,
                avgDuration: durationStr,
                lastVisit: loc.lastVisit,
                behaviorTag: loc.behaviorTag,
                pillarTags: loc.pillarTags,
                rating: loc.rating,
                priceLevel: loc.priceLevel,
                editorialSummary: loc.editorialSummary,
                popularItems: loc.popularItems,
                address: loc.address
            )
        }
    }

    func focusOn(_ place: PlaceCluster) {
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
    }
}
