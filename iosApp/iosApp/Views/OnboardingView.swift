import SwiftUI
import CoreLocation
import HealthKit
import GoogleSignIn
import LinkKit

// MARK: - Step-by-Step Onboarding

/// Clean 3-step onboarding:
/// Step 0: Welcome — purpose + privacy promise
/// Step 1: Location (MANDATORY)
/// Step 2: Connect Data (Bank + Email combined)
/// → Health/AI setup lives in the "You" tab after onboarding
struct OnboardingView: View {
    @StateObject private var state = OnboardingState()
    @Binding var isComplete: Bool

    @State private var currentStep = 0
    @State private var appeared = false

    private let totalSteps = 3

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.06, green: 0.07, blue: 0.10)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Step content
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: locationStep
                    case 2: connectDataStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 16)

                // Bottom
                bottomBar
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Logo + tagline
                VStack(spacing: 8) {
                    Text("Node")
                        .font(.system(size: 38, weight: .light, design: .default))
                        .foregroundStyle(.white.opacity(0.6)) +
                    Text("Compass")
                        .font(.system(size: 38, weight: .bold, design: .default))
                        .foregroundStyle(.white)

                    Text("Your life, understood.")
                        .font(.subheadline)
                        .foregroundStyle(NC.teal.opacity(0.8))
                }
                .padding(.top, 72)
                .padding(.bottom, 36)

                // Pillars — structured card
                VStack(spacing: 0) {
                    PillarRow(icon: "indianrupeesign.circle.fill", color: NC.teal,
                              title: "Wealth", desc: "Every transaction, subscription & charge — tracked automatically")
                    Divider().padding(.leading, 56).opacity(0.3)
                    PillarRow(icon: "heart.circle.fill", color: .pink,
                              title: "Health", desc: "Steps, workouts, sleep — from any wearable via Apple Health")
                    Divider().padding(.leading, 56).opacity(0.3)
                    PillarRow(icon: "fork.knife.circle.fill", color: .orange,
                              title: "Food", desc: "What you eat, where you order, nutrition over time")
                    Divider().padding(.leading, 56).opacity(0.3)
                    PillarRow(icon: "location.circle.fill", color: .blue,
                              title: "Places", desc: "Where you go, your routines, spending tied to locations")
                }
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: NC.cardRadius)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 28)

                // Privacy card
                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(NC.teal)
                        Text("100% Private")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        PrivacyLine(icon: "iphone.gen3", text: "All data stays on your device — nowhere else")
                        PrivacyLine(icon: "icloud.slash.fill", text: "No servers, no cloud, no accounts to create")
                        PrivacyLine(icon: "eye.slash.fill", text: "No one — not even us — can see your data")
                        PrivacyLine(icon: "trash.fill", text: "Delete everything anytime from Settings")
                    }
                }
                .padding(18)
                .background(NC.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: NC.cardRadius)
                        .stroke(NC.teal.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    // MARK: - Step 1: Location (MANDATORY)

    private var locationStep: some View {
        VStack(spacing: 0) {
            // Step indicator
            stepHeader(step: 1, total: 2, title: "Enable Location", subtitle: "Required to use NodeCompass")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Hero
                    ZStack {
                        Circle()
                            .fill(.blue.opacity(0.08))
                            .frame(width: 120, height: 120)
                        Image(systemName: "location.fill.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(.blue)
                    }
                    .padding(.top, 8)

                    InfoCard(icon: "mappin.and.ellipse", color: .blue, title: "Why Location?", bullets: [
                        ("cart.fill", "Link spending to restaurants, shops & gyms"),
                        ("clock.arrow.2.circlepath", "Detect daily routines automatically"),
                        ("lightbulb.fill", "\"You eat out 4x/week\" — insights from movement"),
                    ])

                    InfoCard(icon: "battery.100percent.bolt", color: NC.teal, title: "Private & Efficient", bullets: [
                        ("bolt.fill", "< 1% battery — uses iOS visit detection, not GPS"),
                        ("iphone.gen3", "100% on-device — never leaves your phone"),
                        ("gearshape.fill", "Turn off anytime in Settings"),
                    ])

                    // Action
                    if state.locationConnected {
                        DoneBadge(text: "Location enabled")
                    } else if state.locationDenied {
                        VStack(spacing: 10) {
                            Text("Location was denied. Please enable in Settings.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .multilineTextAlignment(.center)
                            Button {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label("Open Settings", systemImage: "gear")
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(.orange, in: Capsule())
                            }
                        }
                    } else {
                        Button { state.enableLocation() } label: {
                            HStack(spacing: 8) {
                                if state.locationLoading {
                                    ProgressView().tint(.white).scaleEffect(0.8)
                                } else {
                                    Image(systemName: "location.fill")
                                }
                                Text("Enable Location")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(.blue, in: Capsule())
                        }
                        .disabled(state.locationLoading)

                        Text("Tap \"Allow While Using\" or \"Always Allow\"")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Step 2: Connect Data (Bank + Email)

    private var connectDataStep: some View {
        VStack(spacing: 0) {
            stepHeader(step: 2, total: 2, title: "Connect Your Data", subtitle: "Bank & email — set up one or both")

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
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
                        actionLabel: "Connect Bank"
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
                        actionLabel: "Connect Gmail"
                    )

                    // Privacy assurance
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .font(.caption)
                                .foregroundStyle(NC.teal)
                            Text("Both connections are secure & private")
                                .font(.caption.bold())
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        PrivacyLine(icon: "lock.fill", text: "Plaid handles bank login — we never see passwords")
                        PrivacyLine(icon: "eye.slash.fill", text: "Gmail is read-only — only receipt emails")
                        PrivacyLine(icon: "iphone", text: "All data stays on this device")
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Shared Components

    private func stepHeader(step: Int, total: Int, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            // Step dots
            HStack(spacing: 6) {
                ForEach(1...total, id: \.self) { i in
                    Capsule()
                        .fill(i == step ? NC.teal : (i < step ? NC.teal.opacity(0.4) : Color.white.opacity(0.12)))
                        .frame(width: i == step ? 28 : 8, height: 6)
                }
            }

            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button {
                        withAnimation(.spring(response: 0.35)) { currentStep -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 50, height: 52)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    }
                }

                Button { handleNext() } label: {
                    Text(nextLabel)
                        .font(.headline)
                        .foregroundStyle(canProceed ? .white : .white.opacity(0.3))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            canProceed
                                ? AnyShapeStyle(LinearGradient(colors: [NC.teal, NC.teal.opacity(0.7)], startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.white.opacity(0.06))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius))
                }
                .disabled(!canProceed)
            }

            // Skip (only on data step)
            if currentStep == 2 {
                Button {
                    completeOnboarding()
                } label: {
                    Text("Skip — set up later")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
    }

    private var nextLabel: String {
        switch currentStep {
        case 0: return "Let's Set Up"
        case 1: return state.locationConnected ? "Next" : "Enable Location to Continue"
        case 2: return "Get Started"
        default: return "Next"
        }
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0: return true
        case 1: return state.locationConnected
        case 2: return true
        default: return true
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
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        withAnimation(.easeInOut(duration: 0.3)) { isComplete = true }
    }
}

// MARK: - Reusable Components

private struct PillarRow: View {
    let icon: String; let color: Color; let title: String; let desc: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                Text(desc).font(.caption).foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct PrivacyLine: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.caption)
                .foregroundStyle(NC.teal.opacity(0.6)).frame(width: 18)
            Text(text).font(.caption).foregroundStyle(.white.opacity(0.5))
        }
    }
}

private struct InfoCard: View {
    let icon: String; let color: Color; let title: String; let bullets: [(String, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.callout).foregroundStyle(color)
                Text(title).font(.subheadline.bold()).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(bullets, id: \.1) { ic, text in
                    HStack(spacing: 10) {
                        Image(systemName: ic).font(.caption).foregroundStyle(color.opacity(0.6)).frame(width: 18)
                        Text(text).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: NC.cardRadius).stroke(color.opacity(0.1), lineWidth: 1))
    }
}

private struct DoneBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(text).font(.subheadline.bold()).foregroundStyle(.green)
        }
        .padding(.vertical, 12).padding(.horizontal, 20)
        .background(.green.opacity(0.1), in: Capsule())
    }
}

private struct DataSourceCard: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    let isConnected: Bool; let isLoading: Bool; let error: String?
    let action: () -> Void; let actionLabel: String

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: NC.iconRadius)
                        .fill(isConnected ? color.opacity(0.15) : Color.white.opacity(0.05))
                        .frame(width: 44, height: 44)
                    Image(systemName: isConnected ? "checkmark" : icon)
                        .font(.subheadline.bold())
                        .foregroundStyle(isConnected ? .green : color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.bold()).foregroundStyle(.white)
                    Text(subtitle).font(.caption)
                        .foregroundStyle(isConnected ? .green.opacity(0.8) : .white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isLoading {
                    ProgressView().tint(color).scaleEffect(0.8)
                } else {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(color, in: Capsule())
                    }
                }
            }

            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: NC.cardRadius)
                .fill(Color.white.opacity(isConnected ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: NC.cardRadius)
                        .stroke(isConnected ? Color.green.opacity(0.2) : Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
}

// MARK: - Onboarding State

class OnboardingState: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationConnected = false
    @Published var locationLoading = false
    @Published var locationDenied = false

    @Published var bankConnected = false
    @Published var bankLoading = false
    @Published var bankError: String?

    @Published var emailConnected = false
    @Published var emailLoading = false
    @Published var emailError: String?
    @Published var connectedEmail: String?

    private var linkHandler: Handler?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self

        let locStatus = locationManager.authorizationStatus
        locationConnected = (locStatus == .authorizedAlways || locStatus == .authorizedWhenInUse)
        locationDenied = (locStatus == .denied || locStatus == .restricted)

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
                        bankError = "Server offline — set up later in Integrations"
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
                                self.bankError = "Sync failed: \(error.localizedDescription)"
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
                        emailError = "Sign-in failed: \(error.localizedDescription)"
                    }
                    emailLoading = false
                }
            }
        }
    }
}
