import SwiftUI
import MapKit

/// Location heatmap — shows where you spend time and money.
struct LocationHeatmapView: View {
    @StateObject private var vm = LocationHeatmapViewModel()
    @State private var selectedPlace: LocationHeatmapViewModel.PlaceCluster?
    @State private var showDetail = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map
                Map(position: $vm.cameraPosition, selection: $selectedPlace) {
                    ForEach(vm.places) { place in
                        Annotation(place.name, coordinate: place.coordinate) {
                            PlacePin(place: place, isSelected: selectedPlace?.id == place.id)
                        }
                        .tag(place)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .ignoresSafeArea(edges: .top)

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
                statColumn(value: "\(vm.places.count)", label: "Places", icon: "mappin.circle.fill", color: .blue)
                Divider().frame(height: 30)
                statColumn(value: "\(vm.totalVisits)", label: "Visits", icon: "figure.walk", color: .orange)
                Divider().frame(height: 30)
                statColumn(value: NC.money(vm.totalSpent), label: "Spent", icon: NC.currencyIconCircle, color: NC.teal)
            }

            // Top places list
            if !vm.topPlaces.isEmpty {
                VStack(spacing: 8) {
                    ForEach(vm.topPlaces.prefix(3)) { place in
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
                                    Text("\(place.visitCount) visits")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
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

            // Last visit
            if let lastVisit = place.lastVisit {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Last visit: \(lastVisit, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                lastVisit: loc.lastVisit
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
