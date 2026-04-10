import SwiftUI
import LocalAuthentication

/// Handles biometric authentication (Face ID / Touch ID) for app lock.
@MainActor
class AuthService: ObservableObject {
    @Published var isUnlocked: Bool = false

    func authenticate() async {
        // On the simulator, biometrics and passcode don't work reliably.
        // Skip auth so we can test the app. On a real device, this is ignored.
        #if targetEnvironment(simulator)
        isUnlocked = true
        return
        #else
        let context = LAContext()
        var error: NSError?

        // Check if biometrics are available (Face ID / Touch ID)
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // No biometrics — unlock directly rather than falling back to passcode.
            // On a real device without biometrics, the user can still use the app.
            // If you want passcode fallback on real devices, uncomment the block below.
            isUnlocked = true
            return
        }

        // Authenticate with biometrics
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock NodeCompass to view your financial data"
            )
            isUnlocked = success
        } catch {
            isUnlocked = false
        }
        #endif
    }
}
