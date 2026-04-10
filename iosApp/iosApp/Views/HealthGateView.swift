import SwiftUI
import HealthKit

/// Observable state that tracks whether HealthKit permission has been granted.
class HealthGateState: ObservableObject {
    @Published var isHealthEnabled: Bool = false
    @Published var isRequesting = false

    init() {
        // HealthKit doesn't have a simple "is authorized" check for read types,
        // so we rely on our own flag set after successful authorization.
        self.isHealthEnabled = UserDefaults.standard.bool(forKey: "healthKitAuthorized")
    }

    func refresh() {
        isHealthEnabled = UserDefaults.standard.bool(forKey: "healthKitAuthorized")
    }
}

/// Full-screen gate shown when HealthKit is not enabled.
/// User must grant health access to use the app.
struct HealthGateView: View {
    @ObservedObject var gateState: HealthGateState
    @State private var currentStep = 0
    @State private var showPulse = false
    @State private var showError: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero
            ZStack {
                Circle()
                    .stroke(Color.pink.opacity(0.08), lineWidth: 1)
                    .frame(width: 180, height: 180)
                Circle()
                    .stroke(Color.pink.opacity(0.05), lineWidth: 1)
                    .frame(width: 240, height: 240)
                    .scaleEffect(showPulse ? 1.1 : 1.0)
                    .opacity(showPulse ? 0 : 1)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: showPulse)

                Circle()
                    .fill(Color.pink.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "heart.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.pink)
            }
            .padding(.bottom, 32)

            // Swipeable info cards
            TabView(selection: $currentStep) {
                cardView(
                    title: "Connect Your Health Data",
                    subtitle: "NodeCompass reads from Apple Health to understand your fitness, sleep, and activity — including data from Apple Watch, Whoop, and other wearables.",
                    features: [
                        ("figure.run", "Workouts — type, duration, calories burned"),
                        ("bed.double.fill", "Sleep — duration, bedtime consistency"),
                        ("shoeprints.fill", "Steps — daily count, trends, streaks"),
                        ("heart.fill", "Heart rate — resting averages"),
                    ]
                ).tag(0)

                cardView(
                    title: "Smart Cross-Referencing",
                    subtitle: "The real power is connecting health with your spending and location data — no other app does this.",
                    features: [
                        ("fork.knife", "$15 at Smoothie King after your 45 min run"),
                        ("sofa.fill", "Lazy days → 2x more food delivery spending"),
                        ("moon.zzz.fill", "Poor sleep nights → more coffee purchases"),
                        ("flame.fill", "5-day workout streak! Keep it going!"),
                    ]
                ).tag(1)

                cardView(
                    title: "Private & Read-Only",
                    subtitle: "NodeCompass only reads health data — it never writes or modifies anything. All processing happens on your device.",
                    features: [
                        ("eye.slash.fill", "Read-only — we never write to Health"),
                        ("iphone.gen3", "100% on-device processing"),
                        ("arrow.triangle.merge", "Auto-deduplicates Watch + Whoop + Fitbit"),
                        ("gearshape", "Revoke anytime in Settings → Privacy → Health"),
                    ]
                ).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(height: 300)

            Spacer()

            // Bottom action
            VStack(spacing: 14) {
                if let error = showError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button {
                    enableHealth()
                } label: {
                    HStack(spacing: 8) {
                        if gateState.isRequesting {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "heart.fill")
                        }
                        Text(gateState.isRequesting ? "Connecting..." : "Connect Health Data")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.pink, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                }
                .disabled(gateState.isRequesting)
                .padding(.horizontal, 24)

                if !HKHealthStore.isHealthDataAvailable() {
                    Text("HealthKit is not available on this device")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption2)
                        Text("Toggle individual data types on the next screen")
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

    private func enableHealth() {
        gateState.isRequesting = true
        showError = nil

        Task {
            do {
                try await HealthCollector.shared.requestAuthorization()
                // Collect initial data
                await HealthCollector.shared.collectAndStore()
                HealthCollector.shared.enableBackgroundDelivery()

                await MainActor.run {
                    gateState.isRequesting = false
                    gateState.isHealthEnabled = true
                }
            } catch {
                await MainActor.run {
                    gateState.isRequesting = false
                    showError = error.localizedDescription
                }
            }
        }
    }

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
                            .foregroundStyle(.pink)
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
