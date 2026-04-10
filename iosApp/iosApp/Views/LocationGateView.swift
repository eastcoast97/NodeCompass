import SwiftUI
import CoreLocation

/// Observable state that tracks whether location permission has been granted.
/// Used as a gate at app launch — user cannot proceed without enabling location.
class LocationGateState: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isLocationEnabled: Bool = false
    @Published var authStatus: CLAuthorizationStatus

    private let manager = CLLocationManager()

    override init() {
        let status = manager.authorizationStatus
        self.authStatus = status
        self.isLocationEnabled = (status == .authorizedAlways || status == .authorizedWhenInUse)
        super.init()
        manager.delegate = self
    }

    func requestPermission() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authStatus = manager.authorizationStatus
            let granted = manager.authorizationStatus == .authorizedAlways ||
                          manager.authorizationStatus == .authorizedWhenInUse
            self.isLocationEnabled = granted

            if granted {
                // Auto-enable tracking and start collector
                UserDefaults.standard.set(true, forKey: "locationTrackingEnabled")
                LocationCollector.shared.startTracking()
            }
        }
    }
}

/// Full-screen gate shown when location is not enabled.
/// User must grant location permission to use the app.
struct LocationGateView: View {
    @ObservedObject var gateState: LocationGateState
    @State private var currentStep = 0
    @State private var showPulse = false

    private var isDenied: Bool {
        gateState.authStatus == .denied || gateState.authStatus == .restricted
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero section
            ZStack {
                // Animated rings
                Circle()
                    .stroke(Color.blue.opacity(0.08), lineWidth: 1)
                    .frame(width: 180, height: 180)
                Circle()
                    .stroke(Color.blue.opacity(0.05), lineWidth: 1)
                    .frame(width: 240, height: 240)
                    .scaleEffect(showPulse ? 1.1 : 1.0)
                    .opacity(showPulse ? 0 : 1)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: showPulse)

                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "location.fill.viewfinder")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
            }
            .padding(.bottom, 32)

            // Content cards — swipeable
            TabView(selection: $currentStep) {
                cardView(
                    title: "NodeCompass Needs Your Location",
                    subtitle: "Location is the foundation of how NodeCompass understands your life — connecting where you go with how you spend.",
                    features: [
                        ("mappin.and.ellipse", "Link spending to restaurants, shops, and gyms"),
                        ("clock.arrow.2.circlepath", "Detect routines and daily patterns"),
                        ("lightbulb.fill", "Surface insights like \"Eating out 4x/week\""),
                    ]
                ).tag(0)

                cardView(
                    title: "Private & Battery-Friendly",
                    subtitle: "NodeCompass uses iOS visit detection — not continuous GPS. Near-zero battery impact, and your data never leaves your phone.",
                    features: [
                        ("battery.100percent.bolt", "< 1% battery per hour (not continuous GPS)"),
                        ("iphone.gen3", "100% on-device — we have no servers"),
                        ("eye.slash.fill", "Turn off anytime in Settings"),
                    ]
                ).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 280)

            Spacer()

            // Bottom action area
            VStack(spacing: 14) {
                if isDenied {
                    // Permission was denied — direct to Settings
                    Text("Location access was denied. Please enable it in Settings to continue.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gear")
                            Text("Open Settings")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Not determined or when-in-use → request
                    Button {
                        gateState.requestPermission()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "location.fill")
                            Text("Enable Location")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    }
                    .padding(.horizontal, 24)
                }

                // Permission hint
                if !isDenied {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap.fill")
                            .font(.caption2)
                        Text("Choose \"Allow While Using\" or \"Always Allow\"")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .onAppear { showPulse = true }
    }

    // MARK: - Card View

    private func cardView(title: String, subtitle: String, features: [(String, String)]) -> some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(features, id: \.1) { icon, text in
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .font(.callout)
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text(text)
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal, 32)
        }
    }
}
