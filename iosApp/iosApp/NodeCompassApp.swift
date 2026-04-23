import SwiftUI
import GoogleSignIn
import CoreLocation
import HealthKit
import UserNotifications

/// Handles notification display and user actions.
class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    /// Show notifications even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Handle notification tap actions
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let categoryId = response.notification.request.content.categoryIdentifier
        let actionId = response.actionIdentifier

        switch categoryId {
        case "FOOD_LOG":
            if actionId == "LOG_FOOD" || actionId == UNNotificationDefaultActionIdentifier {
                NotificationCenter.default.post(name: NSNotification.Name("openFoodLog"), object: nil)
            }
        case "PLACE_VISIT":
            if actionId == UNNotificationDefaultActionIdentifier {
                NotificationCenter.default.post(name: NSNotification.Name("openHeatmap"), object: nil)
            }
        default:
            break
        }

        completionHandler()
    }
}

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

        // Set up notification delegate and categories
        setupNotifications()

        // Initialize intelligence layer — migrate existing transactions into EventStore
        initializeIntelligenceLayer()

        // Resume passive location tracking if previously enabled by user
        if UserDefaults.standard.bool(forKey: "locationTrackingEnabled") {
            LocationCollector.shared.startTracking()
        }

        // Start listening for location events to auto-complete habits in real-time
        HabitAutoTracker.shared.startListening()
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationDelegate.shared

        // Request notification permission proactively
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        let logFoodAction = UNNotificationAction(
            identifier: "LOG_FOOD",
            title: "Log Meal",
            options: .foreground
        )
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Not Now",
            options: .destructive
        )

        let foodCategory = UNNotificationCategory(
            identifier: "FOOD_LOG",
            actions: [logFoodAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let placeCategory = UNNotificationCategory(
            identifier: "PLACE_VISIT",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let habitCategory = UNNotificationCategory(
            identifier: "HABIT_COMPLETE",
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([foodCategory, placeCategory, habitCategory])
    }

    private func initializeIntelligenceLayer() {
        Task {
            let eventCount = await EventStore.shared.totalCount
            if eventCount == 0 {
                let transactions = await MainActor.run { TransactionStore.shared.transactions }
                if !transactions.isEmpty {
                    await TransactionBridge.migrateExistingTransactions(from: transactions)
                }
            }
        }
    }

    @State private var colorScheme = NC.preferredColorScheme

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
                // Handle Plaid OAuth redirect — after bank OAuth completes,
                // Plaid's hosted redirect page (cdn.plaid.com) opens the app
                // via the nodecompass:// custom scheme.
                if url.scheme == "nodecompass" {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PlaidOAuthRedirect"),
                        object: url
                    )
                    return
                }
                // Handle Google Sign-In callback
                GIDSignIn.sharedInstance.handle(url)
            }
            .preferredColorScheme(colorScheme)
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("themeChanged"))) { _ in
                colorScheme = NC.preferredColorScheme
            }
        }
    }
}
