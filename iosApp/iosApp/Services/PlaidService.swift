import Foundation

/// Handles communication with the Plaid backend server for bank connections.
/// Flow: iOS → your backend server → Plaid API → bank data → your server → iOS
///
/// Privacy: Bank credentials go through Plaid (SOC 2 certified), never through NodeCompass.
/// Transaction data is fetched via your backend and stored locally on-device.
class PlaidService {
    static let shared = PlaidService()

    /// Base URL of your backend server.
    /// For development: your Mac's local IP. For production: your deployed server.
    private var serverBaseURL: String {
        get {
            UserDefaults.standard.string(forKey: "plaid_server_url")
                ?? "https://server-sage-ten.vercel.app"  // Vercel deployment
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "plaid_server_url")
        }
    }

    private init() {}

    // MARK: - Configuration

    func setServerURL(_ url: String) {
        UserDefaults.standard.set(url, forKey: "plaid_server_url")
    }

    var currentServerURL: String { serverBaseURL }

    // MARK: - Link Token (Step 1: Get a token to launch Plaid Link)

    /// Request a link_token from your backend server.
    /// Your server calls Plaid's /link/token/create with your secret key.
    func createLinkToken() async throws -> String {
        guard let url = URL(string: "\(serverBaseURL)/api/create_link_token") else {
            throw PlaidError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PlaidError.serverError("Server returned status \(statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let linkToken = json?["link_token"] as? String else {
            throw PlaidError.invalidResponse("Missing link_token in response")
        }

        return linkToken
    }

    // MARK: - Exchange Token (Step 2: After user connects bank)

    /// Send the public_token from Plaid Link to your backend.
    /// Your server exchanges it for an access_token and stores it.
    func exchangePublicToken(_ publicToken: String, institutionName: String?) async throws {
        guard let url = URL(string: "\(serverBaseURL)/api/exchange_token") else {
            throw PlaidError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "public_token": publicToken,
            "institution_name": institutionName ?? "Unknown Bank"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PlaidError.serverError("Token exchange failed with status \(statusCode)")
        }
    }

    // MARK: - Fetch Transactions (Step 3: Sync bank transactions)

    /// Fetch transactions from your backend server.
    /// Your server calls Plaid's /transactions/sync and returns the data.
    func syncTransactions() async throws -> [PlaidTransaction] {
        guard let url = URL(string: "\(serverBaseURL)/api/transactions") else {
            throw PlaidError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw PlaidError.serverError("Transaction sync failed with status \(statusCode)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let transactionsArray = json?["transactions"] as? [[String: Any]] ?? []

        return transactionsArray.compactMap { PlaidTransaction.from(json: $0) }
    }

    // MARK: - Connected Accounts

    /// Fetch the list of connected bank accounts.
    func getConnectedAccounts() async throws -> [PlaidAccount] {
        guard let url = URL(string: "\(serverBaseURL)/api/accounts") else {
            throw PlaidError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return [] // No accounts connected yet
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let accountsArray = json?["accounts"] as? [[String: Any]] ?? []

        return accountsArray.compactMap { PlaidAccount.from(json: $0) }
    }

    // MARK: - Lightweight Update Check

    /// Check if server has new data — returns immediately, no Plaid API call.
    /// This is the key to event-driven sync: app asks "anything new?" every 30s
    /// and only does a full transaction fetch when the answer is yes.
    func checkForUpdates(since counter: Int) async -> UpdateCheckResult? {
        guard let url = URL(string: "\(serverBaseURL)/api/updates?since=\(counter)") else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return UpdateCheckResult(
                hasUpdates: json?["hasUpdates"] as? Bool ?? false,
                counter: json?["counter"] as? Int ?? counter,
                pendingCount: json?["pendingTransactions"] as? Int ?? 0
            )
        } catch {
            return nil
        }
    }

    // MARK: - Health Check

    /// Check if the backend server is reachable.
    func isServerReachable() async -> Bool {
        guard let url = URL(string: "\(serverBaseURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Data Models

struct PlaidTransaction {
    let transactionId: String
    let accountId: String
    let amount: Double          // Positive = debit, Negative = credit (Plaid convention)
    let isoCurrencyCode: String?
    let name: String            // Raw transaction name from bank
    let merchantName: String?   // Clean merchant name (Plaid resolved)
    let personalFinanceCategory: String?  // Plaid's own category
    let date: Date
    let pending: Bool

    static func from(json: [String: Any]) -> PlaidTransaction? {
        guard let id = json["transaction_id"] as? String,
              let accountId = json["account_id"] as? String,
              let amount = json["amount"] as? Double,
              let name = json["name"] as? String,
              let dateStr = json["date"] as? String else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.date(from: dateStr) ?? Date()

        // Extract Plaid's personal finance category
        var category: String? = nil
        if let pfc = json["personal_finance_category"] as? [String: Any],
           let primary = pfc["primary"] as? String {
            category = mapPlaidCategory(primary)
        }

        return PlaidTransaction(
            transactionId: id,
            accountId: accountId,
            amount: amount,
            isoCurrencyCode: json["iso_currency_code"] as? String,
            name: name,
            merchantName: json["merchant_name"] as? String,
            personalFinanceCategory: category,
            date: date,
            pending: json["pending"] as? Bool ?? false
        )
    }

    /// Map Plaid's detailed categories to our simpler categories.
    private static func mapPlaidCategory(_ plaidCategory: String) -> String {
        switch plaidCategory {
        case "FOOD_AND_DRINK": return "Food & Dining"
        case "GROCERIES": return "Groceries"
        case "TRANSPORTATION": return "Transport"
        case "SHOPPING", "GENERAL_MERCHANDISE": return "Shopping"
        case "ENTERTAINMENT": return "Entertainment"
        case "RENT_AND_UTILITIES": return "Bills & Utilities"
        case "MEDICAL": return "Health"
        case "EDUCATION": return "Education"
        case "TRAVEL": return "Travel"
        case "TRANSFER_IN", "TRANSFER_OUT": return "Transfers"
        case "INCOME": return "Income"
        case "LOAN_PAYMENTS": return "Bills & Utilities"
        case "PERSONAL_CARE": return "Health"
        default: return "Other"
        }
    }
}

struct PlaidAccount {
    let accountId: String
    let name: String
    let officialName: String?
    let type: String           // "depository", "credit", "investment"
    let subtype: String?       // "checking", "savings", "credit card"
    let institutionName: String
    let mask: String?          // Last 4 digits

    static func from(json: [String: Any]) -> PlaidAccount? {
        guard let id = json["account_id"] as? String,
              let name = json["name"] as? String,
              let type = json["type"] as? String else {
            return nil
        }
        return PlaidAccount(
            accountId: id,
            name: name,
            officialName: json["official_name"] as? String,
            type: type,
            subtype: json["subtype"] as? String,
            institutionName: json["institution_name"] as? String ?? "Bank",
            mask: json["mask"] as? String
        )
    }
}

struct UpdateCheckResult {
    let hasUpdates: Bool
    let counter: Int
    let pendingCount: Int
}

// MARK: - Errors

enum PlaidError: LocalizedError {
    case invalidURL
    case serverError(String)
    case invalidResponse(String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .serverError(let msg): return msg
        case .invalidResponse(let msg): return msg
        case .notConnected: return "No bank account connected"
        }
    }
}
