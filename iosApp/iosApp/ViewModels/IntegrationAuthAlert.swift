import SwiftUI

/// Checks all integrations for auth issues and surfaces them as alerts on the Dashboard.
@MainActor
class IntegrationAuthAlert: ObservableObject {
    struct AuthIssue {
        let service: String
        let message: String
        let action: () -> Void
    }

    @Published var issues: [AuthIssue] = []

    /// Check all integrations for problems. Called on app foreground +
    /// dashboard appear.
    ///
    /// IMPORTANT — what we deliberately DON'T check:
    /// Email "session expired" used to fire here whenever a connected Gmail
    /// wasn't in GmailService.authenticatedUsers. But the Google Sign-In SDK
    /// only auto-restores ONE account per cold launch, so for users with
    /// multiple Gmails the secondary one ALWAYS shows as not-in-memory —
    /// even though the keychain refresh token is fine. That meant the
    /// dashboard banner kept reappearing on every foreground.
    ///
    /// EmailSyncViewModel.syncNow now auto-runs reAuthenticate when the
    /// SDK lacks a fresh session, so the user gets a one-tap Google picker
    /// confirmation when they actually tap Sync. No alarmist persistent
    /// banner needed.
    func check() async {
        // Currently a no-op. Kept as a hook so future integrations (Plaid,
        // bank, etc.) can surface real auth failures here without rewiring
        // the dashboard banner.
        issues = []
    }
}
