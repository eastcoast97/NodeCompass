import SwiftUI
import GoogleSignIn
import CoreLocation
import HealthKit

@main
struct NodeCompassApp: App {
    @StateObject private var authService = AuthService()
    @StateObject private var transactionStore = TransactionStore.shared
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")

    init() {
        // Configure Google Sign-In with the client ID from Info.plist
        if let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String {
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
        }

        // Register background tasks for intelligence analysis
        BackgroundScheduler.register()

        // Initialize intelligence layer — migrate existing transactions into EventStore
        initializeIntelligenceLayer()

        // Resume passive location tracking if previously enabled by user
        if UserDefaults.standard.bool(forKey: "locationTrackingEnabled") {
            LocationCollector.shared.startTracking()
        }
    }

    private func initializeIntelligenceLayer() {
        Task {
            let eventCount = await EventStore.shared.totalCount
            if eventCount == 0 {
                let transactions = await MainActor.run { TransactionStore.shared.transactions }
                if !transactions.isEmpty {
                    TransactionBridge.migrateExistingTransactions(from: transactions)
                }
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !authService.isUnlocked {
                    LockScreenView(authService: authService)
                } else if !onboardingComplete {
                    OnboardingView(isComplete: $onboardingComplete)
                } else {
                    ContentView()
                        .environmentObject(transactionStore)
                        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("resetOnboarding"))) { _ in
                            onboardingComplete = false
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                            Task {
                                if UserDefaults.standard.bool(forKey: "healthKitAuthorized") {
                                    await HealthCollector.shared.collectAndStore()
                                }
                                await PatternEngine.shared.runAnalysis()
                            }
                            BackgroundScheduler.scheduleNextTasks()
                        }
                }
            }
            // IMPORTANT: This must be OUTSIDE the if/else so it always
            // catches the Google Sign-In callback URL, even if the lock
            // screen is showing when the app returns from Safari.
            .onOpenURL { url in
                // Handle Google Sign-In callback
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
