import SwiftUI
import CoreLocation
import HealthKit
import GoogleSignIn
import LinkKit

// MARK: - Modern Onboarding Flow
//
// 4 steps — smooth, non-blocking, delightful:
//   Step 0: Welcome (pillars + privacy)
//   Step 1: Permissions (Location + Health — both optional, skip-friendly)
//   Step 2: Connect Data (Bank + Email)
//   Step 3: Ready — celebration + what's next

struct OnboardingView: View {
    @StateObject private var state = OnboardingState()
    @Binding var isComplete: Bool

    @State private var currentStep = 0
    @State private var appeared = false

    private let totalSteps = 4

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.09),
                    Color(red: 0.08, green: 0.09, blue: 0.14),
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (visible on steps 1-3)
                if currentStep > 0 {
                    progressBar
                        .padding(.top, 8)
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Step content
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: permissionsStep
                    case 2: connectDataStep
                    case 3: readyStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 12)

                // Bottom action
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(1..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? NC.teal : Color.white.opacity(0.08))
                    .frame(height: 3)
                    .animation(.spring(response: 0.4), value: currentStep)
            }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Logo
                VStack(spacing: 10) {
                    // App icon / logo
                    ZStack {
                        Circle()
                            .fill(NC.teal.opacity(appeared ? 0.12 : 0))
                            .frame(width: 100, height: 100)
                            .blur(radius: 30)

                        Image("NodeCompassLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .scaleEffect(appeared ? 1 : 0.85)
                    .opacity(appeared ? 1 : 0)

                    VStack(spacing: 6) {
                        Text("Node")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(.white.opacity(0.6)) +
                        Text("Compass")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Your life, understood.")
                            .font(.callout)
                            .foregroundStyle(NC.teal.opacity(0.9))
                    }
                }
                .padding(.top, 48)
                .padding(.bottom, 32)

                // Pillars
                VStack(spacing: 0) {
                    PillarRow(icon: NC.currencyIconCircle, color: NC.teal,
                              title: "Wealth", desc: "Every transaction, subscription & charge — tracked automatically",
                              delay: 0.1, appeared: appeared)
                    Divider().padding(.leading, 56).opacity(0.15)
                    PillarRow(icon: "heart.circle.fill", color: .pink,
                              title: "Health", desc: "Steps, workouts, sleep — synced from Apple Health",
                              delay: 0.2, appeared: appeared)
                    Divider().padding(.leading, 56).opacity(0.15)
                    PillarRow(icon: "fork.knife.circle.fill", color: .orange,
                              title: "Food", desc: "What you eat, where you order, nutrition over time",
                              delay: 0.3, appeared: appeared)
                    Divider().padding(.leading, 56).opacity(0.15)
                    PillarRow(icon: "location.circle.fill", color: .blue,
                              title: "Places", desc: "Where you go, your routines, spending tied to locations",
                              delay: 0.4, appeared: appeared)
                }
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                // Privacy
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.title3)
                        .foregroundStyle(NC.teal)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("100% On-Device")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Text("Your data never leaves your phone. No servers, no accounts, no tracking.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NC.teal.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(NC.teal.opacity(0.12), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Step 1: Permissions (Location + Health — both optional)

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Enable Permissions")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("These help NodeCompass learn your patterns — enable what you're comfortable with")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // Location Permission Card
                    PermissionCard(
                        icon: "location.fill",
                        color: .blue,
                        title: "Location",
                        subtitle: "Link spending to places, detect routines",
                        detail: "Uses iOS visit detection — less than 1% battery",
                        isGranted: state.locationConnected,
                        isDenied: state.locationDenied,
                        isLoading: state.locationLoading,
                        action: { state.enableLocation() }
                    )

                    // Health Permission Card
                    PermissionCard(
                        icon: "heart.fill",
                        color: .pink,
                        title: "Apple Health",
                        subtitle: "Sync steps, workouts, sleep & heart rate",
                        detail: "Read-only — NodeCompass never writes health data",
                        isGranted: state.healthConnected,
                        isDenied: state.healthDenied,
                        isLoading: state.healthLoading,
                        action: { state.enableHealth() }
                    )

                    // Privacy reassurance
                    HStack(spacing: 10) {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(NC.teal.opacity(0.6))
                        Text("Both are optional. You can change these anytime in Settings.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Step 2: Connect Data

    private var connectDataStep: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Connect Your Data")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Set up one or both — or skip for now")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // Bank
                    DataSourceCard(
                        icon: "building.columns.fill",
                        color: .blue,
                        title: "Bank Account",
                        subtitle: "Auto-sync all transactions via Plaid",
                        isConnected: state.bankConnected,
                        isLoading: state.bankLoading,
                        error: state.bankError,
                        action: { state.connectBank() },
                        actionLabel: "Connect"
                    )

                    // Email
                    DataSourceCard(
                        icon: "envelope.fill",
                        color: .purple,
                        title: "Gmail",
                        subtitle: state.emailConnected
                            ? (state.connectedEmail ?? "Connected")
                            : "Find receipts from Amazon, Uber Eats & more",
                        isConnected: state.emailConnected,
                        isLoading: state.emailLoading,
                        error: state.emailError,
                        action: { state.connectEmail() },
                        actionLabel: "Connect"
                    )

                    // Privacy footnote
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .font(.caption)
                                .foregroundStyle(NC.teal.opacity(0.6))
                            Text("Secure & Private")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        PrivacyLine(icon: "lock.fill", text: "Plaid handles bank login — we never see passwords")
                        PrivacyLine(icon: "eye.slash.fill", text: "Gmail is read-only — only receipt emails")
                        PrivacyLine(icon: "iphone", text: "All data stays on this device")
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Step 3: Ready

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                // Celebration icon
                ZStack {
                    Circle()
                        .fill(NC.teal.opacity(0.1))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(NC.teal)
                        .symbolEffect(.bounce, options: .speed(0.5))
                }

                VStack(spacing: 8) {
                    Text("You're All Set!")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Text("NodeCompass will start learning your patterns and building your life dashboard.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Summary of what was connected
                VStack(spacing: 10) {
                    if state.locationConnected {
                        ReadyCheckRow(icon: "location.fill", color: .blue, text: "Location tracking active")
                    }
                    if state.healthConnected {
                        ReadyCheckRow(icon: "heart.fill", color: .pink, text: "Apple Health connected")
                    }
                    if state.bankConnected {
                        ReadyCheckRow(icon: "building.columns.fill", color: .blue, text: "Bank account linked")
                    }
                    if state.emailConnected {
                        ReadyCheckRow(icon: "envelope.fill", color: .purple, text: state.connectedEmail ?? "Gmail connected")
                    }
                    if !state.locationConnected && !state.healthConnected && !state.bankConnected && !state.emailConnected {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.3))
                            Text("You can connect data sources anytime from the You tab")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.35))
                        }
                    }
                }
                .padding(.top, 8)
            }

            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                // Back button (steps 1-2 only, not on welcome or ready)
                if currentStep > 0 && currentStep < totalSteps - 1 {
                    Button {
                        withAnimation(.spring(response: 0.35)) { currentStep -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 50, height: 54)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                // Main CTA
                Button { handleNext() } label: {
                    Text(nextLabel)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            LinearGradient(
                                colors: [NC.teal, NC.teal.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: NC.teal.opacity(0.3), radius: 12, y: 4)
                }
            }

            // Skip option (steps 1 and 2 only)
            if currentStep == 1 || currentStep == 2 {
                Button {
                    withAnimation(.spring(response: 0.35)) { currentStep += 1 }
                } label: {
                    Text("Skip for now")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
    }

    private var nextLabel: String {
        switch currentStep {
        case 0: return "Get Started"
        case 1: return "Continue"
        case 2: return "Continue"
        case 3: return "Open NodeCompass"
        default: return "Next"
        }
    }

    private func handleNext() {
        if currentStep < totalSteps - 1 {
            withAnimation(.spring(response: 0.35)) { currentStep += 1 }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        if state.locationConnected {
            UserDefaults.standard.set(true, forKey: "locationTrackingEnabled")
            LocationCollector.shared.startTracking()
        }
        if state.healthConnected {
            UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
            Task { await HealthCollector.shared.collectAndStore() }
        }
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        withAnimation(.easeInOut(duration: 0.3)) { isComplete = true }
    }
}

// MARK: - Permission Card

private struct PermissionCard: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let detail: String
    let isGranted: Bool
    let isDenied: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isGranted ? .green.opacity(0.12) : color.opacity(0.08))
                        .frame(width: 46, height: 46)
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.subheadline.bold())
                        .foregroundStyle(isGranted ? .green : color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else if isLoading {
                    ProgressView()
                        .tint(color)
                        .scaleEffect(0.8)
                } else if isDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Settings")
                            .font(.caption.bold())
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                } else {
                    Button(action: action) {
                        Text("Enable")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(color, in: Capsule())
                    }
                }
            }

            // Detail text
            if !isGranted {
                HStack(spacing: 8) {
                    Image(systemName: isDenied ? "exclamationmark.circle" : "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(isDenied ? .orange.opacity(0.6) : .white.opacity(0.25))
                    Text(isDenied ? "Permission denied — tap Settings to enable" : detail)
                        .font(.caption2)
                        .foregroundStyle(isDenied ? .orange.opacity(0.7) : .white.opacity(0.3))
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 60)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isGranted ? 0.04 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isGranted ? Color.green.opacity(0.15) : Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}

// MARK: - Data Source Card

private struct DataSourceCard: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    let isConnected: Bool; let isLoading: Bool; let error: String?
    let action: () -> Void; let actionLabel: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isConnected ? .green.opacity(0.12) : color.opacity(0.08))
                        .frame(width: 46, height: 46)
                    Image(systemName: isConnected ? "checkmark" : icon)
                        .font(.subheadline.bold())
                        .foregroundStyle(isConnected ? .green : color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(isConnected ? .green.opacity(0.8) : .white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                } else if isLoading {
                    ProgressView().tint(color).scaleEffect(0.8)
                } else {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(color, in: Capsule())
                    }
                }
            }

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.leading, 60)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isConnected ? 0.04 : 0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isConnected ? Color.green.opacity(0.15) : Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }
}

// MARK: - Reusable Components

private struct PillarRow: View {
    let icon: String; let color: Color; let title: String; let desc: String
    let delay: Double; let appeared: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(desc).font(.caption).foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 20)
        .animation(.spring(response: 0.5).delay(delay), value: appeared)
    }
}

private struct PrivacyLine: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.caption)
                .foregroundStyle(NC.teal.opacity(0.5)).frame(width: 18)
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct ReadyCheckRow: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1), in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Onboarding State

class OnboardingState: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationConnected = false
    @Published var locationLoading = false
    @Published var locationDenied = false

    @Published var healthConnected = false
    @Published var healthLoading = false
    @Published var healthDenied = false

    @Published var bankConnected = false
    @Published var bankLoading = false
    @Published var bankError: String?

    @Published var emailConnected = false
    @Published var emailLoading = false
    @Published var emailError: String?
    @Published var connectedEmail: String?

    private var linkHandler: Handler?
    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        locationManager.delegate = self

        let locStatus = locationManager.authorizationStatus
        locationConnected = (locStatus == .authorizedAlways || locStatus == .authorizedWhenInUse)
        locationDenied = (locStatus == .denied || locStatus == .restricted)

        // Check HealthKit
        if HKHealthStore.isHealthDataAvailable() {
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            let status = healthStore.authorizationStatus(for: stepType)
            healthConnected = (status == .sharingAuthorized)
            healthDenied = (status == .sharingDenied)
        }

        // Check if HealthKit was previously authorized
        if UserDefaults.standard.bool(forKey: "healthKitAuthorized") {
            healthConnected = true
        }

        Task {
            let accounts = (try? await PlaidService.shared.getConnectedAccounts()) ?? []
            await MainActor.run { bankConnected = !accounts.isEmpty }
        }

        let emails = GmailService.shared.connectedEmails
        emailConnected = !emails.isEmpty
        connectedEmail = emails.first
    }

    // MARK: - Location

    func enableLocation() {
        locationLoading = true
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        } else if status == .denied || status == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            locationLoading = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            let granted = manager.authorizationStatus == .authorizedAlways ||
                          manager.authorizationStatus == .authorizedWhenInUse
            self.locationConnected = granted
            self.locationDenied = (manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted)
            self.locationLoading = false
            if granted { LocationCollector.shared.requestPermissionAndStart() }
        }
    }

    // MARK: - Health

    func enableHealth() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthDenied = true
            return
        }
        healthLoading = true

        let readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]

        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.healthConnected = success
                self?.healthDenied = !success
                self?.healthLoading = false
                if success {
                    UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
                }
            }
        }
    }

    // MARK: - Bank

    func connectBank() {
        bankLoading = true
        bankError = nil
        Task {
            do {
                let plaid = PlaidService.shared
                let online = await plaid.isServerReachable()
                if !online {
                    await MainActor.run {
                        bankError = "Server offline — set up later in Settings"
                        bankLoading = false
                    }
                    return
                }
                let linkToken = try await plaid.createLinkToken()
                await MainActor.run {
                    var config = LinkTokenConfiguration(token: linkToken) { [weak self] success in
                        Task { @MainActor in
                            guard let self else { return }
                            do {
                                try await plaid.exchangePublicToken(success.publicToken, institutionName: success.metadata.institution.name)
                                let synced = try await plaid.syncTransactions()
                                for txn in synced where !txn.pending { TransactionStore.shared.addFromBank(txn) }
                                self.bankConnected = true; self.bankLoading = false
                            } catch {
                                self.bankError = "Sync failed — try again later"
                                self.bankLoading = false
                            }
                        }
                    }
                    config.onExit = { [weak self] exit in
                        Task { @MainActor in
                            if let e = exit.error { self?.bankError = e.errorMessage }
                            self?.bankLoading = false
                        }
                    }
                    let result = Plaid.create(config)
                    switch result {
                    case .success(let handler):
                        self.linkHandler = handler
                        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let vc = scene.windows.first?.rootViewController else {
                            self.bankError = "Cannot present bank screen"; self.bankLoading = false; return
                        }
                        handler.open(presentUsing: .viewController(vc))
                    case .failure(let e):
                        self.bankError = e.localizedDescription; self.bankLoading = false
                    }
                }
            } catch {
                await MainActor.run { bankError = error.localizedDescription; bankLoading = false }
            }
        }
    }

    // MARK: - Email

    func connectEmail() {
        emailLoading = true; emailError = nil
        Task {
            do {
                let email = try await GmailService.shared.signInNewAccount()
                await MainActor.run { emailConnected = true; connectedEmail = email; emailLoading = false }
            } catch {
                await MainActor.run {
                    if (error as NSError).code != GIDSignInError.canceled.rawValue {
                        emailError = "Sign-in failed — try again"
                    }
                    emailLoading = false
                }
            }
        }
    }
}
