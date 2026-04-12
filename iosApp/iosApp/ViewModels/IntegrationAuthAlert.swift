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

    /// Check all integrations for problems. Called on app foreground + dashboard appear.
    /// Async so we can attempt a silent token restore before judging auth state.
    func check() async {
        var newIssues: [AuthIssue] = []

        // Gmail — attempt silent restore, then check for expired sessions
        let gmail = GmailService.shared
        let connectedEmails = gmail.connectedEmails
        if !connectedEmails.isEmpty {
            // Await restore so we don't race against the token refresh
            await gmail.restorePreviousSignIn()

            let expiredEmails = connectedEmails.filter { !gmail.isAuthenticated(email: $0) }
            if !expiredEmails.isEmpty {
                let emailList = expiredEmails.count == 1
                    ? expiredEmails[0]
                    : "\(expiredEmails.count) accounts"
                newIssues.append(AuthIssue(
                    service: "Email",
                    message: "\(emailList) — session expired, tap to re-authenticate",
                    action: {
                        // Navigate to You tab — post a notification
                        NotificationCenter.default.post(
                            name: NSNotification.Name("navigateToYouTab"),
                            object: nil
                        )
                    }
                ))
            }
        }

        // Plaid — check if server is reachable (async, so skip if not already known)
        // We just check if there are accounts but last sync had an error
        // This is a lightweight check — the real error surfaces when sync fails

        issues = newIssues
    }
}
