import Foundation
import GoogleSignIn

/// Manages multiple Gmail accounts for receipt fetching.
/// Each account has its own sync state (historyId, processedIds).
///
/// SDK constraint: `GIDSignIn` only holds ONE "currentUser" at a time.
/// On app restart, only the last signed-in account auto-restores.
/// Other accounts show "Re-authenticate" until the user taps to sign in again.
class GmailService {
    static let shared = GmailService()

    private let gmailReadonlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    private let gmailBaseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    /// In-memory map of authenticated users, keyed by email.
    /// Populated on sign-in and restore. Lost on app restart except for the last user.
    private var authenticatedUsers: [String: GIDGoogleUser] = [:]

    /// List of connected account emails (persisted).
    var connectedEmails: [String] {
        get { UserDefaults.standard.stringArray(forKey: "gmail_connected_emails") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_connected_emails") }
    }

    private init() {}

    // MARK: - Authentication

    /// Sign in with Google and request gmail.readonly scope.
    /// If the email is already connected, this re-authenticates it.
    /// Returns the signed-in user's email.
    func signInNewAccount() async throws -> String {
        let rootVC = try await getRootVC()

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootVC,
            hint: nil,
            additionalScopes: [gmailReadonlyScope]
        )

        let user = result.user
        guard let email = user.profile?.email else {
            throw GmailServiceError.noAccessToken
        }

        authenticatedUsers[email] = user

        // Add to connected list if not already there
        if !connectedEmails.contains(email) {
            connectedEmails.append(email)
        }

        return email
    }

    /// Re-authenticate a specific account (e.g., after app restart for non-primary accounts).
    /// Uses `hint` to pre-select the account in Google's picker.
    func reAuthenticate(email: String) async throws {
        let rootVC = try await getRootVC()

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: rootVC,
            hint: email,
            additionalScopes: [gmailReadonlyScope]
        )

        let user = result.user
        let actualEmail = user.profile?.email ?? email
        authenticatedUsers[actualEmail] = user
    }

    /// Restore the last signed-in user on app launch.
    /// Returns the restored email, or nil if no previous session.
    func restorePreviousSignIn() async -> String? {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            let grantedScopes = user.grantedScopes ?? []
            guard grantedScopes.contains(gmailReadonlyScope) else { return nil }
            guard let email = user.profile?.email else { return nil }
            authenticatedUsers[email] = user
            return email
        } catch {
            return nil
        }
    }

    /// Check if we have a valid in-memory auth session for an account.
    func isAuthenticated(email: String) -> Bool {
        authenticatedUsers[email] != nil
    }

    /// Sign out and remove a specific account.
    func signOut(email: String) {
        authenticatedUsers.removeValue(forKey: email)
        connectedEmails.removeAll { $0 == email }

        // Clear per-account sync state
        UserDefaults.standard.removeObject(forKey: historyKey(for: email))
        UserDefaults.standard.removeObject(forKey: processedKey(for: email))

        // If this was the GIDSignIn current user, sign out from SDK too
        if GIDSignIn.sharedInstance.currentUser?.profile?.email == email {
            GIDSignIn.sharedInstance.signOut()
        }
    }

    /// Sign out all accounts.
    func signOutAll() {
        for email in connectedEmails {
            UserDefaults.standard.removeObject(forKey: historyKey(for: email))
            UserDefaults.standard.removeObject(forKey: processedKey(for: email))
        }
        authenticatedUsers.removeAll()
        connectedEmails = []
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Per-Account Sync State

    private func historyKey(for email: String) -> String { "gmail_history_\(email)" }
    private func processedKey(for email: String) -> String { "gmail_processed_\(email)" }

    private func lastHistoryId(for email: String) -> String? {
        UserDefaults.standard.string(forKey: historyKey(for: email))
    }

    private func setLastHistoryId(_ id: String?, for email: String) {
        UserDefaults.standard.set(id, forKey: historyKey(for: email))
    }

    private func processedMessageIds(for email: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: processedKey(for: email)) ?? [])
    }

    private func setProcessedMessageIds(_ ids: Set<String>, for email: String) {
        UserDefaults.standard.set(Array(ids), forKey: processedKey(for: email))
    }

    /// Clear sync state for an account (e.g., when user clears data).
    func clearSyncState(for email: String) {
        UserDefaults.standard.removeObject(forKey: historyKey(for: email))
        UserDefaults.standard.removeObject(forKey: processedKey(for: email))
    }

    /// Clear only processed message IDs so emails get re-parsed on next sync.
    /// Used when parser is improved and we want to re-extract line items.
    func clearProcessedIds(for email: String) {
        UserDefaults.standard.removeObject(forKey: processedKey(for: email))
        // Also clear historyId so full fetch happens instead of incremental
        UserDefaults.standard.removeObject(forKey: historyKey(for: email))
    }

    /// Clear processed IDs for all connected accounts.
    func clearAllProcessedIds() {
        for email in connectedEmails {
            clearProcessedIds(for: email)
        }
    }

    // MARK: - Gmail API (per-account)

    /// Full fetch for a specific account — searches for receipt emails from last N days.
    func fetchReceiptEmails(for email: String, newerThanDays: Int = 30) async throws -> [EmailMessage] {
        let token = try await getValidAccessToken(for: email)

        let query = "subject:(receipt OR \"order confirmation\" OR invoice OR \"payment received\" OR \"payment confirmation\" OR billing OR \"transaction alert\" OR debited OR credited OR refund OR shipped OR \"order #\") -category:promotions -category:social newer_than:\(newerThanDays)d"
        let messageIds = try await searchMessages(query: query, token: token)

        var emails: [EmailMessage] = []
        var processed = processedMessageIds(for: email)
        for messageId in messageIds.prefix(50) {
            if processed.contains(messageId) { continue }
            if let msg = try? await fetchMessage(id: messageId, token: token) {
                emails.append(msg)
                processed.insert(messageId)
            }
        }
        setProcessedMessageIds(processed, for: email)

        await updateHistoryId(for: email, token: token)

        return emails
    }

    /// Incremental fetch for a specific account.
    /// Returns nil if no historyId (caller should do full fetch).
    func fetchNewReceiptEmails(for email: String) async throws -> [EmailMessage]? {
        guard let historyId = lastHistoryId(for: email) else {
            return nil
        }

        let token = try await getValidAccessToken(for: email)

        let newMessageIds = try await getHistorySince(historyId: historyId, email: email, token: token)

        guard !newMessageIds.isEmpty else {
            await updateHistoryId(for: email, token: token)
            return []
        }

        var emails: [EmailMessage] = []
        var processed = processedMessageIds(for: email)
        for messageId in newMessageIds {
            if processed.contains(messageId) { continue }
            if let msg = try? await fetchMessage(id: messageId, token: token) {
                emails.append(msg)
                processed.insert(messageId)
            }
        }
        setProcessedMessageIds(processed, for: email)

        await updateHistoryId(for: email, token: token)
        return emails
    }

    // MARK: - Migration

    /// Migrate old single-account data to multi-account format.
    /// Call once on app launch if old keys exist.
    func migrateFromSingleAccount() {
        let defaults = UserDefaults.standard

        // Check if old single-account keys exist
        guard let oldHistoryId = defaults.string(forKey: "gmail_last_history_id") else { return }
        guard let email = GIDSignIn.sharedInstance.currentUser?.profile?.email ?? connectedEmails.first else { return }

        // Migrate to per-account keys
        if lastHistoryId(for: email) == nil {
            setLastHistoryId(oldHistoryId, for: email)
        }

        let oldProcessed = Set(defaults.stringArray(forKey: "gmail_processed_ids") ?? [])
        if !oldProcessed.isEmpty && processedMessageIds(for: email).isEmpty {
            setProcessedMessageIds(oldProcessed, for: email)
        }

        if !connectedEmails.contains(email) {
            connectedEmails.append(email)
        }

        // Remove old keys
        defaults.removeObject(forKey: "gmail_last_history_id")
        defaults.removeObject(forKey: "gmail_processed_ids")
    }

    // MARK: - Private Helpers

    private func getRootVC() async throws -> UIViewController {
        guard let windowScene = await MainActor.run(body: {
            UIApplication.shared.connectedScenes.first as? UIWindowScene
        }),
        let rootVC = await MainActor.run(body: {
            windowScene.windows.first?.rootViewController
        }) else {
            throw GmailServiceError.noRootViewController
        }
        return rootVC
    }

    private func getValidAccessToken(for email: String) async throws -> String {
        guard let user = authenticatedUsers[email] else {
            throw GmailServiceError.needsReAuth(email: email)
        }

        try await user.refreshTokensIfNeeded()

        guard let token = user.accessToken.tokenString as String? else {
            throw GmailServiceError.noAccessToken
        }

        return token
    }

    private func updateHistoryId(for email: String, token: String) async {
        guard let url = URL(string: "\(gmailBaseURL)/profile") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            if let hid = json?["historyId"] as? String {
                setLastHistoryId(hid, for: email)
            } else if let hidNum = json?["historyId"] as? UInt64 {
                setLastHistoryId(String(hidNum), for: email)
            }
        } catch {}
    }

    private func getHistorySince(historyId: String, email: String, token: String) async throws -> [String] {
        guard let url = URL(string: "\(gmailBaseURL)/history?startHistoryId=\(historyId)&historyTypes=messageAdded&maxResults=100") else {
            return []
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else { return [] }

        if httpResponse.statusCode == 404 {
            setLastHistoryId(nil, for: email)
            return []
        }

        guard httpResponse.statusCode == 200 else { return [] }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let history = json?["history"] as? [[String: Any]] ?? []

        var messageIds: Set<String> = []
        for entry in history {
            if let messagesAdded = entry["messagesAdded"] as? [[String: Any]] {
                for msg in messagesAdded {
                    if let message = msg["message"] as? [String: Any],
                       let id = message["id"] as? String {
                        messageIds.insert(id)
                    }
                }
            }
        }

        return Array(messageIds)
    }

    private func searchMessages(query: String, token: String) async throws -> [String] {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(gmailBaseURL)/messages?q=\(encodedQuery)&maxResults=50") else {
            throw GmailServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw GmailServiceError.apiFailed
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let messages = json?["messages"] as? [[String: Any]] ?? []

        return messages.compactMap { $0["id"] as? String }
    }

    private func fetchMessage(id: String, token: String) async throws -> EmailMessage? {
        guard let url = URL(string: "\(gmailBaseURL)/messages/\(id)?format=full") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return nil
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return parseGmailMessage(json: json)
    }

    private func parseGmailMessage(json: [String: Any]?) -> EmailMessage? {
        guard let json = json,
              let payload = json["payload"] as? [String: Any],
              let headers = payload["headers"] as? [[String: Any]] else {
            return nil
        }

        var subject = ""
        var from = ""
        var date = ""
        var hasListUnsubscribe = false
        var precedence: String? = nil
        var xMailer: String? = nil
        var hasCampaignHeaders = false

        for header in headers {
            let name = (header["name"] as? String)?.lowercased() ?? ""
            let value = header["value"] as? String ?? ""
            switch name {
            case "subject": subject = value
            case "from": from = value
            case "date": date = value
            case "list-unsubscribe": hasListUnsubscribe = true
            case "precedence": precedence = value.lowercased()
            case "x-mailer": xMailer = value
            default:
                if name.hasPrefix("x-campaign") || name.hasPrefix("x-mc-") ||
                   name == "x-mailchimp-id" || name == "feedback-id" ||
                   name.hasPrefix("x-sg-") || name == "x-sendgrid-id" {
                    hasCampaignHeaders = true
                }
            }
        }

        let senderEmail = extractEmail(from: from)
        let body = extractBody(from: payload)

        guard !body.isEmpty else { return nil }

        return EmailMessage(
            subject: subject,
            body: body,
            senderEmail: senderEmail,
            dateString: date,
            hasListUnsubscribe: hasListUnsubscribe,
            precedence: precedence,
            xMailer: xMailer,
            hasCampaignHeaders: hasCampaignHeaders
        )
    }

    private func extractEmail(from headerValue: String) -> String {
        if let start = headerValue.firstIndex(of: "<"),
           let end = headerValue.firstIndex(of: ">") {
            let emailStart = headerValue.index(after: start)
            return String(headerValue[emailStart..<end])
        }
        return headerValue
    }

    private func extractBody(from payload: [String: Any]) -> String {
        if let body = payload["body"] as? [String: Any],
           let data = body["data"] as? String,
           let decoded = base64URLDecode(data) {
            return decoded
        }

        if let parts = payload["parts"] as? [[String: Any]] {
            for mimePreference in ["text/html", "text/plain"] {
                for part in parts {
                    let mimeType = part["mimeType"] as? String ?? ""
                    if mimeType == mimePreference,
                       let body = part["body"] as? [String: Any],
                       let data = body["data"] as? String,
                       let decoded = base64URLDecode(data) {
                        return decoded
                    }

                    if let nestedParts = part["parts"] as? [[String: Any]] {
                        for nested in nestedParts {
                            let nestedMime = nested["mimeType"] as? String ?? ""
                            if nestedMime == mimePreference,
                               let body = nested["body"] as? [String: Any],
                               let data = body["data"] as? String,
                               let decoded = base64URLDecode(data) {
                                return decoded
                            }
                        }
                    }
                }
            }
        }

        return ""
    }

    private func base64URLDecode(_ base64URL: String) -> String? {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Models

struct EmailMessage {
    let subject: String
    let body: String
    let senderEmail: String
    let dateString: String
    let hasListUnsubscribe: Bool
    let precedence: String?
    let xMailer: String?
    let hasCampaignHeaders: Bool
}

enum GmailServiceError: LocalizedError {
    case noRootViewController
    case notAuthenticated
    case noAccessToken
    case invalidURL
    case apiFailed
    case needsReAuth(email: String)

    var errorDescription: String? {
        switch self {
        case .noRootViewController: return "Cannot present sign-in screen"
        case .notAuthenticated: return "Not signed in to Google"
        case .noAccessToken: return "Failed to get access token"
        case .invalidURL: return "Invalid API URL"
        case .apiFailed: return "Gmail API request failed"
        case .needsReAuth(let email): return "Please re-authenticate \(email)"
        }
    }
}
