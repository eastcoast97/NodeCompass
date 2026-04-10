import SwiftUI
import GoogleSignIn

/// Per-account state displayed in the UI.
struct GmailAccountState: Identifiable {
    let email: String
    var isAuthenticated: Bool
    var isSyncing: Bool = false
    var lastSyncText: String = "Never"
    var receiptsFound: Int = 0
    var newReceiptsThisSync: Int = 0
    var errorMessage: String? = nil

    var id: String { email }
}

/// ViewModel for Gmail email receipt sync — supports multiple accounts.
/// Each account syncs independently with its own historyId and processed set.
@MainActor
class EmailSyncViewModel: ObservableObject {
    @Published var accounts: [GmailAccountState] = []
    @Published var isAddingAccount: Bool = false
    @Published var addAccountError: String? = nil

    private let gmail = GmailService.shared
    private let store = TransactionStore.shared
    private var autoSyncTimer: Timer?
    private var foregroundObserver: Any?

    var hasConnectedAccounts: Bool { !accounts.isEmpty }

    /// Total receipts across all accounts.
    var totalReceipts: Int { accounts.reduce(0) { $0 + $1.receiptsFound } }

    init() {
        Task {
            // Migrate old single-account data if needed
            gmail.migrateFromSingleAccount()

            // Restore the last signed-in user (SDK only restores one)
            let restoredEmail = await gmail.restorePreviousSignIn()

            // Build account states from the persisted connected list
            let connectedEmails = gmail.connectedEmails
            let emailReceiptCounts = store.transactions
                .filter { $0.source == "EMAIL" }
                .count

            for email in connectedEmails {
                let isAuth = gmail.isAuthenticated(email: email)
                let count = store.transactions.filter { $0.source == "EMAIL" }.count
                accounts.append(GmailAccountState(
                    email: email,
                    isAuthenticated: isAuth,
                    receiptsFound: connectedEmails.count == 1 ? count : 0
                ))
            }

            // If we restored a user, do incremental sync
            if let restoredEmail, accounts.contains(where: { $0.email == restoredEmail }) {
                startAutoSync()
                await incrementalSync(for: restoredEmail)
            }
        }

        // Auto-sync when app comes to foreground + try to restore expired sessions
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.tryRestoreExpiredSessions()
                await self?.syncAllAuthenticated()
            }
        }
    }

    deinit {
        autoSyncTimer?.invalidate()
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Session Restore

    /// Try to silently restore Google sessions for accounts that lost auth.
    /// GIDSignIn only restores the last account, but calling restorePreviousSignIn()
    /// on foreground can pick up sessions that Google refreshed in the background.
    private func tryRestoreExpiredSessions() async {
        let expiredAccounts = accounts.filter { !$0.isAuthenticated }
        guard !expiredAccounts.isEmpty else { return }

        // Try the SDK restore — may recover the primary account
        if let restoredEmail = await gmail.restorePreviousSignIn() {
            if let idx = accounts.firstIndex(where: { $0.email == restoredEmail && !$0.isAuthenticated }) {
                accounts[idx].isAuthenticated = true
                accounts[idx].errorMessage = nil
            }
        }
    }

    // MARK: - Auto-Sync

    private func startAutoSync() {
        autoSyncTimer?.invalidate()
        autoSyncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.syncAllAuthenticated()
            }
        }
    }

    /// Sync all accounts that have valid auth sessions.
    private func syncAllAuthenticated() async {
        for account in accounts where account.isAuthenticated {
            await incrementalSync(for: account.email)
        }
    }

    // MARK: - Add / Remove Accounts

    func addAccount() {
        isAddingAccount = true
        addAccountError = nil

        Task {
            do {
                let email = try await gmail.signInNewAccount()

                // Update or add account state
                if let idx = accounts.firstIndex(where: { $0.email == email }) {
                    accounts[idx].isAuthenticated = true
                    accounts[idx].errorMessage = nil
                } else {
                    accounts.append(GmailAccountState(email: email, isAuthenticated: true))
                }

                isAddingAccount = false
                startAutoSync()

                // First sync for the new account
                await fullSync(for: email)
            } catch {
                isAddingAccount = false
                if (error as NSError).code == GIDSignInError.canceled.rawValue { return }
                addAccountError = "Sign-in failed: \(error.localizedDescription)"
            }
        }
    }

    func removeAccount(email: String) {
        gmail.signOut(email: email)
        accounts.removeAll { $0.email == email }

        if accounts.isEmpty {
            autoSyncTimer?.invalidate()
            autoSyncTimer = nil
        }
    }

    // MARK: - Re-authenticate (for accounts that lost their session)

    func reAuthenticate(email: String) {
        guard let idx = accounts.firstIndex(where: { $0.email == email }) else { return }
        accounts[idx].errorMessage = nil

        Task {
            do {
                try await gmail.reAuthenticate(email: email)
                accounts[idx].isAuthenticated = true
                await incrementalSync(for: email)
            } catch {
                if (error as NSError).code == GIDSignInError.canceled.rawValue { return }
                accounts[idx].errorMessage = "Re-auth failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Sync (per account)

    func syncNow(email: String) {
        Task { await fullSync(for: email) }
    }

    /// Re-scan all emails from scratch (clears processed cache, re-parses everything).
    /// Useful when parser is improved to extract items that were missed before.
    func rescanAll() {
        gmail.clearAllProcessedIds()
        for account in accounts where account.isAuthenticated {
            Task { await fullSync(for: account.email) }
        }
    }

    private func fullSync(for email: String) async {
        guard let idx = accounts.firstIndex(where: { $0.email == email }) else { return }
        guard !accounts[idx].isSyncing else { return }

        accounts[idx].isSyncing = true
        accounts[idx].errorMessage = nil
        accounts[idx].newReceiptsThisSync = 0

        do {
            // Clear sync state if store is empty (user cleared data)
            if store.transactions.filter({ $0.source == "EMAIL" }).isEmpty {
                gmail.clearSyncState(for: email)
            }
            let emails = try await gmail.fetchReceiptEmails(for: email, newerThanDays: 30)
            await processEmails(emails, for: email)
            accounts[idx].isSyncing = false
        } catch let error as GmailServiceError {
            handleSyncError(error, for: email, at: idx)
        } catch {
            accounts[idx].errorMessage = "Sync failed: \(error.localizedDescription)"
            accounts[idx].isSyncing = false
        }
    }

    private func incrementalSync(for email: String) async {
        guard let idx = accounts.firstIndex(where: { $0.email == email }) else { return }
        guard accounts[idx].isAuthenticated, !accounts[idx].isSyncing else { return }

        do {
            if let newEmails = try await gmail.fetchNewReceiptEmails(for: email) {
                if newEmails.isEmpty { return }
                await processEmails(newEmails, for: email)
            } else {
                // No historyId yet — need full sync
                await fullSync(for: email)
            }
        } catch let error as GmailServiceError {
            handleSyncError(error, for: email, at: idx)
        } catch {
        }
    }

    private func handleSyncError(_ error: GmailServiceError, for email: String, at idx: Int) {
        switch error {
        case .needsReAuth:
            accounts[idx].isAuthenticated = false
            accounts[idx].isSyncing = false
            accounts[idx].errorMessage = "Session expired. Tap to re-authenticate."
        default:
            accounts[idx].errorMessage = error.localizedDescription
            accounts[idx].isSyncing = false
        }
    }

    // MARK: - Process Emails

    private func processEmails(_ emails: [EmailMessage], for email: String) async {
        guard let idx = accounts.firstIndex(where: { $0.email == email }) else { return }
        var newCount = 0

        for emailMsg in emails {
            let promoScore = SwiftEmailReceiptParser.promoScore(for: emailMsg)

            if promoScore >= 60 { continue }

            if promoScore >= 20 {
                let isReal = await SmartCategorizer.shared.classifyEmail(
                    subject: emailMsg.subject, sender: emailMsg.senderEmail
                )
                if !isReal { continue }
            }

            let emailDate = DateFormatter.emailDate(from: emailMsg.dateString) ?? Date()

            var parseResult: EmailParseResult? = nil

            // For food delivery emails, send raw HTML — LLM parses tables better than stripped text
            let lowerSender = emailMsg.senderEmail.lowercased()
            let isFoodDelivery = ["uber", "swiggy", "zomato", "doordash", "grubhub",
                                   "deliveroo", "postmates", "dunzo"].contains { lowerSender.contains($0) }

            // Extract real restaurant name + address from food delivery emails
            var restaurantInfo: FoodDeliveryParser.RestaurantInfo? = nil
            if isFoodDelivery {
                restaurantInfo = FoodDeliveryParser.extractRestaurant(
                    from: emailMsg.body, sender: emailMsg.senderEmail
                )
            }

            let bodyForLLM = isFoodDelivery ? emailMsg.body : SwiftEmailReceiptParser.stripHtmlPublic(emailMsg.body)
            if let llmResult = await SmartCategorizer.shared.parseReceiptWithLLM(
                subject: emailMsg.subject, body: bodyForLLM, sender: emailMsg.senderEmail
            ) {
                var lineItems = llmResult.lineItems

                // If food delivery email has no items, try following "View Order" links
                if lineItems.isEmpty && isFoodDelivery {
                    if let scraped = await FoodOrderScraper.extractItems(
                        fromEmailHTML: emailMsg.body, sender: emailMsg.senderEmail
                    ) {
                        lineItems = scraped
                    }
                }

                // Use the regex-extracted restaurant name if LLM returned the delivery app name
                var merchantName = llmResult.merchant
                if isFoodDelivery, let info = restaurantInfo {
                    let llmLower = llmResult.merchant.lowercased()
                    let isAppName = ["uber eats", "uber", "doordash", "swiggy", "zomato",
                                     "grubhub", "deliveroo", "postmates", "dunzo"].contains(llmLower)
                    if isAppName {
                        merchantName = info.name
                    }
                }

                parseResult = EmailParseResult(
                    amount: llmResult.amount,
                    currencySymbol: llmResult.currencySymbol,
                    currencyCode: llmResult.currencyCode,
                    merchant: merchantName,
                    type: llmResult.type,
                    date: emailDate,
                    description: llmResult.description,
                    lineItems: lineItems.isEmpty ? nil : lineItems
                )
            }

            if parseResult == nil {
                parseResult = SwiftEmailReceiptParser.parse(email: emailMsg)
                if parseResult != nil {
                    parseResult!.date = emailDate
                    // Override merchant for food delivery even with fallback parser
                    if isFoodDelivery, let info = restaurantInfo {
                        parseResult = EmailParseResult(
                            amount: parseResult!.amount,
                            currencySymbol: parseResult!.currencySymbol,
                            currencyCode: parseResult!.currencyCode,
                            merchant: info.name,
                            type: parseResult!.type,
                            date: emailDate,
                            description: parseResult!.description,
                            lineItems: parseResult!.lineItems
                        )
                    }
                }
            }

            if let result = parseResult {
                let countBefore = store.transactions.count
                store.addFromEmail(result)
                if store.transactions.count > countBefore {
                    newCount += 1
                }

                // Pass restaurant info to FoodAutoDetector for accurate food logs
                if isFoodDelivery {
                    // Find the transaction we just stored
                    if let txn = store.transactions.first(where: {
                        $0.amount == result.amount &&
                        abs($0.date.timeIntervalSince(result.date)) < 86400 &&
                        $0.source == "EMAIL"
                    }) {
                        FoodAutoDetector.checkEmailOrder(
                            transaction: txn,
                            restaurantName: restaurantInfo?.name ?? result.merchant,
                            restaurantAddress: restaurantInfo?.address
                        )
                    }
                }
            }
        }

        if newCount > 0 {
            accounts[idx].newReceiptsThisSync = newCount
            Task { await PatternEngine.shared.runAnalysis() }
        }
        accounts[idx].receiptsFound = store.transactions.filter { $0.source == "EMAIL" }.count
        accounts[idx].lastSyncText = formatNow()
    }

    private func formatNow() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

// MARK: - Date Parsing Helper

extension DateFormatter {
    /// Parse email date strings like "Wed, 9 Apr 2026 00:10:00 +0000"
    static func emailDate(from string: String) -> Date? {
        let formats = [
            "EEE, d MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "EEE, d MMM yyyy HH:mm:ss",
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}
