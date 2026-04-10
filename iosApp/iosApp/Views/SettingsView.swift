import SwiftUI
import CoreLocation

struct SettingsView: View {
    @StateObject private var categorizer = SmartCategorizer.shared
    @StateObject private var locationState = LocationSettingsState()
    @EnvironmentObject var store: TransactionStore
    @State private var showGeminiSetup: Bool = false
    @State private var showLocationSetup: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var isRecategorizing: Bool = false
    @State private var healthEnabled: Bool = UserDefaults.standard.bool(forKey: "healthKitAuthorized")

    var body: some View {
        NavigationStack {
            List {
                // MARK: - AI Features
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(categorizer.isConfigured
                                      ? NC.teal.opacity(0.12)
                                      : Color(.systemGray5))
                                .frame(width: 40, height: 40)
                            Image(systemName: categorizer.isConfigured ? "brain.fill" : "brain")
                                .foregroundStyle(categorizer.isConfigured ? NC.teal : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Categorization")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(categorizer.isConfigured
                                 ? "AI-powered (Llama 3.3)"
                                 : "Keyword-based (basic)")
                                .font(.caption)
                                .foregroundStyle(categorizer.isConfigured ? NC.teal : .secondary)
                        }
                        Spacer()
                        if categorizer.isConfigured {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NC.teal)
                        }
                    }

                    if categorizer.isConfigured {
                        Button("Remove API Key", role: .destructive) {
                            categorizer.removeApiKey()
                        }
                    } else {
                        Button {
                            showGeminiSetup = true
                        } label: {
                            Label("Setup AI (Free)", systemImage: "key.fill")
                        }
                    }
                } header: {
                    Label("AI Features", systemImage: "sparkles")
                } footer: {
                    Text("Get your free key from console.groq.com")
                }

                // MARK: - Re-categorize
                if categorizer.isConfigured && !store.transactions.isEmpty {
                    Section {
                        Button {
                            recategorizeAll()
                        } label: {
                            HStack {
                                Label("Re-categorize All", systemImage: "arrow.triangle.2.circlepath")
                                if isRecategorizing {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(isRecategorizing)
                    } footer: {
                        Text("AI re-categorizes all \(store.transactions.count) transactions for better accuracy.")
                    }
                }

                // MARK: - Privacy
                Section {
                    PrivacyRow(icon: "lock.shield.fill", color: .blue,
                               title: "On-device storage",
                               detail: "All data stays on your phone")
                    PrivacyRow(icon: "icloud.slash.fill", color: .orange,
                               title: "No cloud, no servers",
                               detail: "Zero telemetry or analytics")
                    if categorizer.isConfigured {
                        PrivacyRow(icon: "brain.fill", color: NC.teal,
                                   title: "AI: merchant names only",
                                   detail: "Amounts & accounts never leave device")
                    }
                    if locationState.isTrackingEnabled {
                        PrivacyRow(icon: "location.fill", color: .blue,
                                   title: "Location: on-device only",
                                   detail: "GPS data never leaves your phone")
                    }
                    if healthEnabled {
                        PrivacyRow(icon: "heart.fill", color: .pink,
                                   title: "Health: read-only access",
                                   detail: "Never writes to or modifies your health data")
                    }
                } header: {
                    Label("Privacy", systemImage: "lock.fill")
                }

                // MARK: - Location Intelligence
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(locationState.isTrackingEnabled
                                      ? Color.blue.opacity(0.12)
                                      : Color(.systemGray5))
                                .frame(width: 40, height: 40)
                            Image(systemName: locationState.isTrackingEnabled
                                  ? "location.fill" : "location.slash")
                                .foregroundStyle(locationState.isTrackingEnabled ? .blue : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Location Intelligence")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(locationState.isTrackingEnabled
                                 ? "Learning your places"
                                 : "Not enabled")
                                .font(.caption)
                                .foregroundStyle(locationState.isTrackingEnabled ? .blue : .secondary)
                        }
                        Spacer()
                        if locationState.isTrackingEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }

                    if locationState.isTrackingEnabled {
                        Button("Disable Location Tracking", role: .destructive) {
                            LocationCollector.shared.stopTracking()
                            locationState.isTrackingEnabled = false
                        }
                    } else {
                        Button {
                            showLocationSetup = true
                        } label: {
                            Label("Enable Location Intelligence", systemImage: "location.fill")
                        }
                    }
                } header: {
                    Label("Location Intelligence", systemImage: "location.fill")
                } footer: {
                    Text(locationState.isTrackingEnabled
                         ? "Battery-efficient tracking is active. Insights appear as you visit places."
                         : "Connects spending to places you visit. Battery-friendly & 100% on-device.")
                }

                // MARK: - Health Data
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(healthEnabled
                                      ? Color.pink.opacity(0.12)
                                      : Color(.systemGray5))
                                .frame(width: 40, height: 40)
                            Image(systemName: healthEnabled
                                  ? "heart.fill" : "heart.slash")
                                .foregroundStyle(healthEnabled ? .pink : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health Data")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(healthEnabled
                                 ? "Connected (steps, workouts, sleep)"
                                 : "Not connected")
                                .font(.caption)
                                .foregroundStyle(healthEnabled ? .pink : .secondary)
                        }
                        Spacer()
                        if healthEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.pink)
                        }
                    }

                    if healthEnabled {
                        Button("Disconnect Health Data", role: .destructive) {
                            UserDefaults.standard.set(false, forKey: "healthKitAuthorized")
                            healthEnabled = false
                        }
                    } else {
                        Button {
                            reconnectHealth()
                        } label: {
                            Label("Connect Health Data", systemImage: "heart.fill")
                        }
                    }
                } header: {
                    Label("Health Intelligence", systemImage: "heart.fill")
                } footer: {
                    Text(healthEnabled
                         ? "Reading from Apple Health (includes Apple Watch, Whoop, Fitbit). Read-only."
                         : "Connect to track workouts, steps, sleep, and cross-reference with spending.")
                }

                // MARK: - Data
                Section {
                    HStack {
                        Text("Total transactions")
                        Spacer()
                        Text("\(store.transactions.count)")
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("From Bank")
                        Spacer()
                        Text("\(store.transactions.filter { $0.source == "BANK" }.count)")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("From Email")
                        Spacer()
                        Text("\(store.transactions.filter { $0.source == "EMAIL" }.count)")
                            .foregroundStyle(.secondary)
                    }

                    Button("Clear All Data", role: .destructive) {
                        showClearConfirm = true
                    }
                } header: {
                    Label("Data", systemImage: "externaldrive.fill")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Button("Re-run Onboarding") {
                        UserDefaults.standard.set(false, forKey: "onboardingComplete")
                        // Force app to re-evaluate by posting notification
                        NotificationCenter.default.post(name: NSNotification.Name("resetOnboarding"), object: nil)
                    }
                } header: {
                    Label("About", systemImage: "info.circle")
                }
            }
            .navigationTitle("Settings")
            .alert("API Key Saved", isPresented: $showSavedAlert) {
                Button("OK") {}
            } message: {
                Text("Smart categorization is now active.")
            }
            .alert("Clear All Data?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    store.clearAll()
                    Task {
                        await EventStore.shared.clearAll()
                        await PatternEngine.shared.clearAll()
                        await UserProfileStore.shared.clearAll()
                        await FoodStore.shared.clearAll()
                    }
                }
            } message: {
                Text("This will delete all \(store.transactions.count) transactions. This cannot be undone.")
            }
            .sheet(isPresented: $showGeminiSetup) {
                GeminiSetupView(isPresented: $showGeminiSetup)
            }
            .sheet(isPresented: $showLocationSetup, onDismiss: {
                locationState.refreshStatus()
            }) {
                LocationSetupView(isPresented: $showLocationSetup)
            }
        }
    }

    private func reconnectHealth() {
        Task {
            try? await HealthCollector.shared.requestAuthorization()
            await HealthCollector.shared.collectAndStore()
            HealthCollector.shared.enableBackgroundDelivery()
            await MainActor.run { healthEnabled = true }
        }
    }

    private func recategorizeAll() {
        isRecategorizing = true
        Task {
            let uniqueMerchants = Array(Set(store.transactions.map(\.merchant)))
            let results = await SmartCategorizer.shared.categorizeBatch(merchants: uniqueMerchants)

            for (merchant, result) in results {
                for i in store.transactions.indices where store.transactions[i].merchant == merchant {
                    let old = store.transactions[i]
                    if old.category != result.category {
                        let updated = StoredTransaction(
                            id: old.id, amount: old.amount,
                            currencySymbol: old.currencySymbol, currencyCode: old.currencyCode,
                            merchant: result.displayName.isEmpty ? old.merchant : result.displayName,
                            category: result.category,
                            description: result.description.isEmpty ? old.description : result.description,
                            lineItems: old.lineItems, type: old.type, source: old.source,
                            account: old.account, rawText: old.rawText,
                            date: old.date, createdAt: old.createdAt, categorizedByAI: true
                        )
                        store.updateTransaction(at: i, with: updated)
                    }
                }
            }
            isRecategorizing = false
        }
    }
}

/// Observable state for the location tracking toggle in Settings.
class LocationSettingsState: ObservableObject {
    @Published var isTrackingEnabled: Bool
    @Published var permissionDenied: Bool = false

    var statusText: String {
        if permissionDenied {
            return "Permission denied — tap below to fix"
        }
        return isTrackingEnabled ? "Learning your places" : "Disabled"
    }

    init() {
        let status = CLLocationManager().authorizationStatus
        let wasEnabled = UserDefaults.standard.bool(forKey: "locationTrackingEnabled")
        self.isTrackingEnabled = wasEnabled && (status == .authorizedAlways || status == .authorizedWhenInUse)
        self.permissionDenied = (status == .denied || status == .restricted)

        // Observe auth changes
        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshStatus),
            name: UIApplication.didBecomeActiveNotification, object: nil
        )
    }

    @objc func refreshStatus() {
        let status = CLLocationManager().authorizationStatus
        let wasEnabled = UserDefaults.standard.bool(forKey: "locationTrackingEnabled")
        DispatchQueue.main.async {
            self.permissionDenied = (status == .denied || status == .restricted)
            self.isTrackingEnabled = wasEnabled && (status == .authorizedAlways || status == .authorizedWhenInUse)
        }
    }
}

private struct PrivacyRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
