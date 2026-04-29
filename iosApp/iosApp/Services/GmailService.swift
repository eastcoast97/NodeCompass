import Foundation
import GoogleSignIn

/// Manages multiple Gmail accounts for receipt fetching.
/// Each account has its own sync state (historyId, processedIds).
///
/// Multi-account strategy: GoogleSignIn-iOS's `GIDSignIn` only auto-restores
/// ONE user across cold launches (the most recent). To support multiple
/// concurrent Gmail accounts, we persist each account's refresh token in
/// Keychain at sign-in time and exchange it for a fresh access token via
/// Google's OAuth endpoint on demand. This bypasses the SDK's single-user
/// restriction entirely — non-primary accounts sync silently like the
/// primary one, no manual re-auth tap required.
class GmailService {
    static let shared = GmailService()

    private let gmailReadonlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    private let gmailBaseURL = "https://gmail.googleapis.com/gmail/v1/users/me"

    /// Google OAuth client ID — pulled from Info.plist (the iOS reverse-DNS
    /// form Google issues for native apps). Required for the manual refresh
    /// flow that powers non-primary accounts.
    private var oauthClientID: String? {
        Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String
    }

    /// In-memory map of GIDGoogleUser objects, keyed by email. Populated on
    /// sign-in and SDK auto-restore. The SDK only restores one user across
    /// cold launches — the manual refresh path below covers the rest.
    private var authenticatedUsers: [String: GIDGoogleUser] = [:]

    /// In-memory cache of access tokens fetched via the manual refresh path.
    /// Each entry has a token + expiry; we refresh just-in-time when expired.
    /// Resets on cold launch, which is fine — refresh tokens are durable.
    private var manualAccessTokens: [String: (token: String, expiry: Date)] = [:]

    /// List of connected account emails (persisted).
    var connectedEmails: [String] {
        get { UserDefaults.standard.stringArray(forKey: "gmail_connected_emails") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "gmail_connected_emails") }
    }

    private init() {}

    // MARK: - Refresh Token Persistence (Keychain)

    private func keychainKey(for email: String) -> String {
        "com.nodecompass.gmail.refresh.\(email.lowercased())"
    }

    /// Persist a refresh token for a given email account. Called after every
    /// successful sign-in or re-auth so we can silently get fresh access
    /// tokens for that account on future cold launches.
    private func saveRefreshToken(_ token: String, for email: String) {
        let key = keychainKey(for: email)
        let data = Data(token.utf8)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: data
        ]
        // Idempotent: delete any existing entry first.
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ] as CFDictionary)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func loadRefreshToken(for email: String) -> String? {
        let key = keychainKey(for: email)
        var result: AnyObject?
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteRefreshToken(for email: String) {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keychainKey(for: email)
        ] as CFDictionary)
    }

    /// After a successful GIDSignIn flow, capture both the in-memory user
    /// AND the durable refresh token. The refresh token survives cold
    /// launches via Keychain and powers silent token exchange below.
    private func recordSignedInUser(_ user: GIDGoogleUser, email: String) {
        authenticatedUsers[email] = user
        if let refresh = user.refreshToken.tokenString as String?, !refresh.isEmpty {
            saveRefreshToken(refresh, for: email)
        }
        // Drop any stale manual token cache — the new in-memory user is fresher.
        manualAccessTokens.removeValue(forKey: email)
    }

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

        recordSignedInUser(user, email: email)

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
        recordSignedInUser(user, email: actualEmail)
    }

    /// Restore the last signed-in user on app launch.
    /// Returns the restored email, or nil if no previous session.
    func restorePreviousSignIn() async -> String? {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            let grantedScopes = user.grantedScopes ?? []
            guard grantedScopes.contains(gmailReadonlyScope) else { return nil }
            guard let email = user.profile?.email else { return nil }
            // Record into in-memory map AND refresh keychain copy of refresh
            // token in case it rotated since last save.
            recordSignedInUser(user, email: email)
            return email
        } catch {
            return nil
        }
    }

    /// Whether we can sync `email` without showing a user-facing OAuth flow.
    /// True if either the SDK has the user in memory OR we have a keychain
    /// refresh token we can silently exchange.
    func isAuthenticated(email: String) -> Bool {
        if authenticatedUsers[email] != nil { return true }
        return loadRefreshToken(for: email) != nil
    }

    /// Sign out and remove a specific account.
    func signOut(email: String) {
        authenticatedUsers.removeValue(forKey: email)
        connectedEmails.removeAll { $0 == email }

        // Clear per-account sync state + persisted refresh token + token cache.
        UserDefaults.standard.removeObject(forKey: historyKey(for: email))
        UserDefaults.standard.removeObject(forKey: processedKey(for: email))
        deleteRefreshToken(for: email)
        manualAccessTokens.removeValue(forKey: email)

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
            deleteRefreshToken(for: email)
        }
        manualAccessTokens.removeAll()
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
        // Fast path: SDK has the user in memory (always true for the one
        // account auto-restored at launch, plus anything signed in this
        // session). Use the SDK's normal refresh.
        if let user = authenticatedUsers[email] {
            try await user.refreshTokensIfNeeded()
            guard let token = user.accessToken.tokenString as String? else {
                throw GmailServiceError.noAccessToken
            }
            return token
        }

        // Silent path: SDK doesn't have this user (it's a non-primary
        // account on a fresh launch). Exchange the persisted refresh token
        // for a new access token via Google's OAuth endpoint.
        return try await fetchAccessTokenViaRefreshToken(for: email)
    }

    /// Manual OAuth refresh-token exchange. Used for accounts the SDK didn't
    /// auto-restore on cold launch. Caches the resulting access token in
    /// memory until just before its expiry to avoid repeated network round
    /// trips. If the refresh token has been revoked (rare — usually only
    /// after 6 months of inactivity or explicit revocation), throws
    /// `.needsReAuth` so the caller can prompt the user to sign in again.
    private func fetchAccessTokenViaRefreshToken(for email: String) async throws -> String {
        // Cache hit?
        if let cached = manualAccessTokens[email],
           cached.expiry > Date().addingTimeInterval(60) {   // 1 min safety margin
            return cached.token
        }

        guard let refreshToken = loadRefreshToken(for: email) else {
            throw GmailServiceError.needsReAuth(email: email)
        }
        guard let clientID = oauthClientID else {
            throw GmailServiceError.noAccessToken
        }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Native iOS apps are public OAuth clients — no client_secret. Google's
        // OAuth endpoint accepts client_id + refresh_token alone for these.
        let body = [
            "client_id":     clientID,
            "refresh_token": refreshToken,
            "grant_type":    "refresh_token"
        ]
        let bodyString = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GmailServiceError.noAccessToken
        }

        // 400/401 with "invalid_grant" means the refresh token itself is dead
        // (user revoked, or 6+ months inactive). Drop it and require a fresh
        // sign-in so we don't keep retrying a doomed exchange.
        if http.statusCode == 400 || http.statusCode == 401 {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errStr = json["error"] as? String,
               errStr == "invalid_grant" {
                deleteRefreshToken(for: email)
                throw GmailServiceError.needsReAuth(email: email)
            }
        }

        guard http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw GmailServiceError.noAccessToken
        }

        // Google returns expires_in seconds (typically 3599). Cache slightly
        // shy of that to give the safety margin some room.
        let expiresIn = (json["expires_in"] as? Double) ?? 3500
        manualAccessTokens[email] = (
            token: accessToken,
            expiry: Date().addingTimeInterval(expiresIn)
        )
        return accessToken
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
