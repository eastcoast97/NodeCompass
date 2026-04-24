import Foundation
import UIKit
import UserNotifications

/// Handles APNs registration + device token upload to Supabase + deep-link
/// handling when a reaction push is tapped.
///
/// Lifecycle:
/// 1. `AppDelegate.application(_:didFinishLaunchingWithOptions:)` triggers
///    `requestAuthorizationAndRegister()` (after the user has a Supabase
///    identity — we skip if they haven't signed in yet).
/// 2. iOS asks APNs for a device token, then calls
///    `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
///    on the AppDelegate, which forwards to `handleAPNSToken(_:)` here.
/// 3. We hex-encode the token and upload via the `register_device` RPC.
/// 4. When a push arrives, iOS shows it natively. On tap, the system
///    delivers it to `UNUserNotificationCenterDelegate`, which routes via
///    `NotificationCenter` so views (e.g. the Circles tab) can open the
///    Reaction Inbox.
@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    /// Whether the current APNs build is sandbox (development) or
    /// production. Debug builds hit the sandbox APNs host; App Store /
    /// TestFlight builds hit production. We upload this tag with the token
    /// so the server knows which host to send to.
    enum Environment: String {
        case development, production
        static var current: Environment {
            #if DEBUG
            return .development
            #else
            return .production
            #endif
        }
    }

    /// Call once on app launch (after identity is established) to kick off
    /// the APNs registration dance. Safe to call multiple times — iOS
    /// caches the token internally and will deliver it immediately if
    /// we've already registered.
    func requestAuthorizationAndRegister() {
        // Only register if the user has completed Sign in with Apple — APNs
        // tokens we store without an anon_user_id would be orphans.
        guard AnonymousIdentity.shared.hasIdentity else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Called from AppDelegate with the device token. Hex-encodes + uploads.
    func handleAPNSToken(_ deviceToken: Data) async {
        let hexToken = deviceToken.map { String(format: "%02x", $0) }.joined()

        // Make sure we have a live session before the RPC call — the
        // register_device RPC requires auth.uid() to match the row we
        // insert/upsert. ensureSession refreshes if the access token
        // expired while the app was backgrounded.
        do {
            _ = try await AnonymousIdentity.shared.ensureSession()
        } catch {
            // Not signed in — token will be re-registered next time the
            // user signs in and requestAuthorizationAndRegister runs.
            return
        }

        struct Args: Encodable {
            let p_token: String
            let p_env: String
        }
        do {
            try await NCBackend.shared
                .rpc("register_device",
                     params: Args(p_token: hexToken, p_env: Environment.current.rawValue))
                .execute()
        } catch {
            // Best-effort — next launch re-registers.
            print("[PushNotificationService] register_device failed: \(error)")
        }
    }

    /// Called from AppDelegate when APNs registration fails.
    func handleAPNSError(_ error: Error) {
        print("[PushNotificationService] APNs registration failed: \(error.localizedDescription)")
    }
}
