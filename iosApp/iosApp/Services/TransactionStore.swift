import Foundation

/// Time period for spending filters.
enum SpendPeriod: String, CaseIterable {
    case today = "Today"
    case week = "Week"
    case month = "Month"
}

/// Persistent local transaction store using JSON file storage.
/// This replaces the hardcoded sample data and will eventually be replaced
/// by the shared Kotlin TransactionRepository once KMP framework is linked.
///
/// All data stays on-device in the app's private Documents directory.
@MainActor
class TransactionStore: ObservableObject {
    static let shared = TransactionStore()

    @Published private(set) var transactions: [StoredTransaction] = []

    private let fileName = "transactions.json"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        loadFromDisk()
        cleanupBadLineItems()
        deduplicateEmailTransactions()
        fixKnownMerchantCategories()
    }

    /// Re-categorize transactions that match known merchant overrides (e.g., RentCafe → Rent).
    private func fixKnownMerchantCategories() {
        var changed = false
        for i in transactions.indices {
            let txn = transactions[i]
            let lower = txn.merchant.lowercased()

            // Known rent portals
            let rentKeywords = ["rentcafe", "rent cafe", "apartments.com", "avail rent"]
            if rentKeywords.contains(where: { lower.contains($0) }) && txn.category != "Rent" {
                transactions[i] = StoredTransaction(
                    id: txn.id, amount: txn.amount, currencySymbol: txn.currencySymbol,
                    currencyCode: txn.currencyCode, merchant: txn.merchant, category: "Rent",
                    description: "Online rent payment", lineItems: txn.lineItems,
                    type: txn.type, source: txn.source, account: txn.account,
                    rawText: txn.rawText, date: txn.date, createdAt: txn.createdAt,
                    categorizedByAI: true
                )
                changed = true
            }
        }
        if changed { saveToDisk() }
    }

    /// Remove lineItems that are addresses (from bad LLM parsing).
    private func cleanupBadLineItems() {
        var changed = false
        for i in transactions.indices {
            guard let items = transactions[i].lineItems, !items.isEmpty else { continue }
            let validItems = items.filter { !SwiftEmailReceiptParser.looksLikeAddress($0.name) }
            if validItems.count < items.count {
                let old = transactions[i]
                transactions[i] = StoredTransaction(
                    id: old.id, amount: old.amount,
                    currencySymbol: old.currencySymbol, currencyCode: old.currencyCode,
                    merchant: old.merchant, category: old.category,
                    description: old.description,
                    lineItems: validItems.isEmpty ? nil : validItems,
                    type: old.type, source: old.source,
                    account: old.account, rawText: old.rawText,
                    date: old.date, createdAt: old.createdAt,
                    categorizedByAI: old.categorizedByAI
                )
                changed = true
            }
        }
        if changed { saveToDisk() }
    }

    /// Remove duplicate EMAIL transactions (same amount + date within 1 day).
    /// This cleans up duplicates created by re-scanning with improved merchant name extraction.
    private func deduplicateEmailTransactions() {
        var seen: [(amount: Double, date: Date)] = []
        var indicesToRemove: [Int] = []

        // Keep the most recently created version (last in array) which has the best merchant name
        let emailTxns = transactions.enumerated().filter { $0.element.source == "EMAIL" }
        for (idx, txn) in emailTxns {
            if seen.contains(where: { $0.amount == txn.amount && abs($0.date.timeIntervalSince(txn.date)) < 86400 }) {
                indicesToRemove.append(idx)
            } else {
                seen.append((txn.amount, txn.date))
            }
        }

        if !indicesToRemove.isEmpty {
            for idx in indicesToRemove.reversed() {
                transactions.remove(at: idx)
            }
            saveToDisk()
        }
    }

    // MARK: - Public API

    /// Add a transaction from Plaid bank sync.
    func addFromBank(_ plaidTxn: PlaidTransaction) {
        let cleanMerchant = MerchantNameResolver.resolve(plaidTxn.merchantName ?? plaidTxn.name)
        // Deduplicate by Plaid transaction ID
        guard !transactions.contains(where: { $0.id == plaidTxn.transactionId }) else { return }

        let txn = StoredTransaction(
            id: plaidTxn.transactionId,
            amount: abs(plaidTxn.amount),
            currencySymbol: plaidTxn.isoCurrencyCode == "INR" ? "₹" : "$",
            currencyCode: plaidTxn.isoCurrencyCode ?? "USD",
            merchant: cleanMerchant,
            category: plaidTxn.personalFinanceCategory ?? categorize(merchant: cleanMerchant),
            description: plaidTxn.name,
            lineItems: nil,
            type: plaidTxn.amount < 0 ? "CREDIT" : "DEBIT",
            source: "BANK",
            account: plaidTxn.accountId,
            rawText: nil,
            date: plaidTxn.date,
            createdAt: Date(),
            categorizedByAI: plaidTxn.personalFinanceCategory != nil
        )
        addTransaction(txn)
        TransactionBridge.bridgeInBackground(txn)

        // Re-categorize with LLM in background if Plaid didn't provide a category
        if plaidTxn.personalFinanceCategory == nil {
            Task { await smartRecategorize(id: txn.id, merchant: cleanMerchant) }
        }
    }

    /// Add a transaction from email receipt parsing.
    func addFromEmail(_ result: EmailParseResult) {
        // Don't resolve through MerchantNameResolver if the merchant is already
        // a specific restaurant name (not a generic app name like "Uber Eats").
        // The email pipeline extracts real restaurant names for food delivery.
        let genericApps = ["uber eats", "doordash", "swiggy", "zomato", "grubhub",
                           "deliveroo", "postmates", "dunzo", "blinkit"]
        let isGenericApp = genericApps.contains(result.merchant.lowercased())
        let cleanMerchant = isGenericApp ? MerchantNameResolver.resolve(result.merchant) : result.merchant
        // Check for duplicates (same amount + date within 1 day from EMAIL source).
        // We match on amount+date only (not merchant name) because re-scanning
        // may extract a different merchant name (e.g., "Ernesto's" instead of "Uber Eats").
        if let existingIdx = transactions.firstIndex(where: { existing in
            existing.source == "EMAIL" &&
            existing.amount == result.amount &&
            abs(existing.date.timeIntervalSince(result.date)) < 86400
        }) {
            // Duplicate exists — update if we have better data (new lineItems or better merchant name)
            let existing = transactions[existingIdx]
            let hasNewItems = (existing.lineItems == nil || existing.lineItems?.isEmpty == true) &&
                              (result.lineItems != nil && !(result.lineItems?.isEmpty ?? true))
            let hasBetterMerchant = !isGenericApp && genericApps.contains(existing.merchant.lowercased())

            if hasNewItems || hasBetterMerchant {
                let updatedMerchant = hasBetterMerchant ? cleanMerchant : existing.merchant
                let updatedCategory = hasBetterMerchant ? categorize(merchant: updatedMerchant) : existing.category
                let updated = StoredTransaction(
                    id: existing.id, amount: existing.amount,
                    currencySymbol: existing.currencySymbol, currencyCode: existing.currencyCode,
                    merchant: updatedMerchant, category: updatedCategory,
                    description: result.description ?? existing.description,
                    lineItems: hasNewItems ? result.lineItems! : existing.lineItems,
                    type: existing.type, source: existing.source,
                    account: existing.account, rawText: existing.rawText,
                    date: existing.date, createdAt: existing.createdAt,
                    categorizedByAI: existing.categorizedByAI
                )
                transactions[existingIdx] = updated
                saveToDisk()
                if hasNewItems {
                    FoodAutoDetector.checkEmailOrder(transaction: updated)
                }
                // Re-categorize with LLM if merchant name improved
                if hasBetterMerchant {
                    Task { await smartRecategorize(id: existing.id, merchant: updatedMerchant) }
                }
            }
            return
        }

        let txn = StoredTransaction(
            id: UUID().uuidString,
            amount: result.amount,
            currencySymbol: result.currencySymbol,
            currencyCode: result.currencyCode,
            merchant: cleanMerchant,
            category: categorize(merchant: cleanMerchant),
            description: result.description,
            lineItems: result.lineItems,
            type: result.type,
            source: "EMAIL",
            account: nil,
            rawText: nil,
            date: result.date,
            createdAt: Date()
        )
        addTransaction(txn)
        TransactionBridge.bridgeInBackground(txn)

        // Auto-detect food orders from email receipts
        FoodAutoDetector.checkEmailOrder(transaction: txn)

        // Re-categorize with LLM in background
        Task { await smartRecategorize(id: txn.id, merchant: cleanMerchant) }
    }

    /// Re-categorize a transaction using Claude API (runs in background).
    private func smartRecategorize(id: String, merchant: String) async {
        let result = await SmartCategorizer.shared.categorize(merchant: merchant)

        // Update if LLM, cache, or keyword override gave a different/better result
        if result.source == .llm || result.source == .cache || result.source == .keyword {
            if let index = transactions.firstIndex(where: { $0.id == id }) {
                let old = transactions[index]
                if old.category != result.category || old.merchant != result.displayName {
                    transactions[index] = StoredTransaction(
                        id: old.id,
                        amount: old.amount,
                        currencySymbol: old.currencySymbol,
                        currencyCode: old.currencyCode,
                        merchant: result.displayName.isEmpty ? old.merchant : result.displayName,
                        category: result.category,
                        description: result.description.isEmpty ? old.description : result.description,
                        lineItems: old.lineItems,
                        type: old.type,
                        source: old.source,
                        account: old.account,
                        rawText: old.rawText,
                        date: old.date,
                        createdAt: old.createdAt,
                        categorizedByAI: true
                    )
                    saveToDisk()
                }
            }
        }
    }

    /// Delete a transaction by ID.
    func delete(id: String) {
        transactions.removeAll { $0.id == id }
        saveToDisk()
    }

    /// Clear all transactions.
    func clearAll() {
        transactions = []
        saveToDisk()
    }

    /// Update a transaction at a specific index (used by batch recategorization).
    func updateTransaction(at index: Int, with txn: StoredTransaction) {
        guard transactions.indices.contains(index) else { return }
        transactions[index] = txn
        saveToDisk()
    }

    // MARK: - Computed Properties for Dashboard

    var totalSpendToday: Double {
        transactions
            .filter { $0.type.uppercased() == "DEBIT" && Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    var totalSpendThisMonth: Double {
        let calendar = Calendar.current
        let now = Date()
        return transactions
            .filter { $0.type.uppercased() == "DEBIT" && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var totalIncomeThisMonth: Double {
        let calendar = Calendar.current
        let now = Date()
        return transactions
            .filter { $0.type.uppercased() == "CREDIT" && calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }

    var categoryBreakdown: [(category: String, amount: Double)] {
        categoryBreakdown(for: .month)
    }

    /// Spending breakdown filtered by time period.
    func categoryBreakdown(for period: SpendPeriod) -> [(category: String, amount: Double)] {
        let calendar = Calendar.current
        let now = Date()
        let filtered = transactions.filter { txn in
            guard txn.type.uppercased() == "DEBIT" else { return false }
            switch period {
            case .today:
                return calendar.isDateInToday(txn.date)
            case .week:
                return calendar.isDate(txn.date, equalTo: now, toGranularity: .weekOfYear)
            case .month:
                return calendar.isDate(txn.date, equalTo: now, toGranularity: .month)
            }
        }

        var byCategory: [String: Double] = [:]
        for txn in filtered {
            byCategory[txn.category, default: 0] += txn.amount
        }
        return byCategory.map { (category: $0.key, amount: $0.value) }
            .sorted { $0.amount > $1.amount }
    }

    /// Total spend filtered by time period.
    func totalSpend(for period: SpendPeriod) -> Double {
        let calendar = Calendar.current
        let now = Date()
        return transactions
            .filter { txn in
                guard txn.type.uppercased() == "DEBIT" else { return false }
                switch period {
                case .today: return calendar.isDateInToday(txn.date)
                case .week: return calendar.isDate(txn.date, equalTo: now, toGranularity: .weekOfYear)
                case .month: return calendar.isDate(txn.date, equalTo: now, toGranularity: .month)
                }
            }
            .reduce(0) { $0 + $1.amount }
    }

    var recentTransactions: [StoredTransaction] {
        Array(transactions.sorted { $0.date > $1.date }.prefix(20))
    }

    /// Detect ghost subscriptions: same merchant + similar amount recurring 2+ times.
    var ghostSubscriptions: [(merchant: String, amount: Double, currencySymbol: String, occurrences: Int, frequency: String)] {
        // Group by merchant (lowercased) + rounded amount
        var groups: [String: [StoredTransaction]] = [:]
        for txn in transactions where txn.type.uppercased() == "DEBIT" {
            let key = "\(txn.merchant.lowercased())_\(Int(txn.amount * 100))"
            groups[key, default: []].append(txn)
        }

        return groups.compactMap { _, txns in
            guard txns.count >= Config.Wealth.ghostMinOccurrences else { return nil }
            let first = txns[0]
            let frequency = estimateGhostFrequency(txns: txns)
            return (merchant: first.merchant, amount: first.amount,
                    currencySymbol: first.currencySymbol, occurrences: txns.count, frequency: frequency)
        }.sorted { $0.occurrences > $1.occurrences }
    }

    /// Estimate recurring charge frequency from actual timestamp intervals.
    /// Uses the full date span and individual intervals to classify correctly.
    /// Monthly subscriptions with only a few data points default to "Monthly"
    /// rather than being misclassified as "Weekly" from short-span math.
    private func estimateGhostFrequency(txns: [StoredTransaction]) -> String {
        guard txns.count >= 2 else { return "Recurring" }
        let sorted = txns.sorted { $0.date < $1.date }
        let spanDays = sorted.last!.date.timeIntervalSince(sorted.first!.date) / 86_400

        // If the total span is less than 14 days, we don't have enough data
        // to distinguish weekly from monthly — default to "Monthly" since
        // most subscriptions are monthly and we'd rather be right for the
        // common case than wrong for the rare one.
        guard spanDays >= 14 else { return "Monthly" }

        let avgIntervalDays = spanDays / Double(sorted.count - 1)

        // For weekly, require at least 3 data points AND a short average interval.
        // This prevents 2 monthly charges that happen to be ~7 days apart
        // (e.g., prorated first charge + regular charge) from being called weekly.
        if avgIntervalDays < 10 && sorted.count >= 3 {
            return "Weekly"
        }

        switch avgIntervalDays {
        case ..<45:    return "Monthly"
        case 45..<120: return "Quarterly"
        case 120..<400: return "Yearly"
        default:        return "Recurring"
        }
    }

    // MARK: - Manual Transaction (for voice input / cash expenses)

    func addManualTransaction(amount: Double, merchant: String, category: String?, type: String = "DEBIT") {
        let txn = StoredTransaction(
            id: UUID().uuidString,
            amount: amount,
            currencySymbol: NC.currencySymbol,
            currencyCode: Locale.current.currency?.identifier ?? "USD",
            merchant: merchant,
            category: category ?? categorize(merchant: merchant),
            description: nil,
            lineItems: nil,
            type: type,
            source: "MANUAL",
            account: nil,
            rawText: nil,
            date: Date(),
            createdAt: Date(),
            categorizedByAI: false
        )
        addTransaction(txn)
    }

    // MARK: - Private

    private func addTransaction(_ txn: StoredTransaction) {
        transactions.insert(txn, at: 0)
        // Keep sorted by date (newest first)
        transactions.sort { $0.date > $1.date }
        saveToDisk()
    }

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private func saveToDisk() {
        do {
            let data = try encoder.encode(transactions)
            try data.write(to: fileURL, options: .atomicWrite)
        } catch {
            print("[TransactionStore] Save failed: \(error.localizedDescription)")
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            transactions = try decoder.decode([StoredTransaction].self, from: data)
        } catch {
            print("[TransactionStore] Load failed: \(error.localizedDescription)")
            transactions = []
        }
    }

    // MARK: - Simple Categorizer (mirrors shared Kotlin logic)

    private func categorize(merchant: String) -> String {
        let lower = merchant.lowercased()

        let categories: [(String, [String])] = [
            ("Food & Dining", ["uber eats", "doordash", "grubhub", "deliveroo", "swiggy", "zomato",
                               "starbucks", "mcdonalds", "mcdonald", "dominos", "pizza hut", "kfc",
                               "subway", "chipotle", "dunkin", "restaurant", "cafe", "diner",
                               "burger king", "taco bell", "wendy", "chick-fil-a", "panda express"]),
            ("Groceries", ["whole foods", "trader joe", "kroger", "bigbasket", "instacart",
                           "walmart grocery", "aldi", "costco", "safeway", "publix", "fresh",
                           "grocery", "market", "blinkit", "zepto", "jiomart"]),
            ("Transport", ["uber", "lyft", "ola", "rapido", "bolt", "grab", "gojek",
                           "parking", "fuel", "gas station", "shell", "bp ", "chevron",
                           "metro", "transit", "railway"]),
            ("Shopping", ["amazon", "walmart", "target", "flipkart", "ebay", "etsy",
                          "ikea", "best buy", "apple store", "nike", "adidas", "zara",
                          "h&m", "myntra", "ajio", "meesho"]),
            ("Subscriptions", ["netflix", "spotify", "disney+", "hulu", "hbo", "youtube premium",
                               "apple music", "audible", "notion", "figma", "adobe",
                               "microsoft 365", "google one", "icloud", "dropbox",
                               "chatgpt", "openai", "claude", "anthropic"]),
            ("Bills & Utilities", ["electric", "water ", "gas bill", "broadband", "internet",
                                   "t-mobile", "verizon", "at&t", "jio", "airtel", "vodafone",
                                   "comcast", "spectrum", "rent", "insurance", "mortgage"]),
            ("Entertainment", ["movie", "cinema", "theatre", "ticket", "bookmyshow",
                               "gaming", "steam", "playstation", "xbox", "concert"]),
            ("Health", ["pharmacy", "hospital", "doctor", "clinic", "medical",
                        "dental", "gym", "fitness", "health", "wellness"]),
            ("Education", ["course", "udemy", "coursera", "school", "university",
                           "tuition", "book", "textbook"]),
            ("Transfers", ["transfer", "sent to", "received from", "salary", "deposit",
                           "withdrawal", "atm"]),
        ]

        for (category, keywords) in categories {
            for keyword in keywords {
                if lower.contains(keyword) {
                    // Avoid "uber" matching for "uber eats" (food takes priority)
                    if keyword == "uber" && lower.contains("uber eats") { continue }
                    return category
                }
            }
        }

        return "Other"
    }
}

// MARK: - Stored Transaction Model

struct StoredTransaction: Codable, Identifiable {
    let id: String
    let amount: Double
    let currencySymbol: String
    let currencyCode: String
    let merchant: String
    let category: String
    let description: String?  // AI-generated description of what this merchant/transaction is
    let lineItems: [LineItem]?  // Items in the receipt (from email parsing)
    let type: String // "Debit" or "Credit"
    let source: String // "SMS", "EMAIL", or "MANUAL"
    let account: String?
    let rawText: String?
    let date: Date
    let createdAt: Date
    let categorizedByAI: Bool  // true if categorized by Claude, false if keyword-based

    var isCredit: Bool { type.uppercased() == "CREDIT" }

    // Coding keys with default for backwards compatibility
    enum CodingKeys: String, CodingKey {
        case id, amount, currencySymbol, currencyCode, merchant, category
        case description, lineItems, type, source, account, rawText
        case date, createdAt, categorizedByAI
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        amount = try c.decode(Double.self, forKey: .amount)
        currencySymbol = try c.decode(String.self, forKey: .currencySymbol)
        currencyCode = try c.decode(String.self, forKey: .currencyCode)
        merchant = try c.decode(String.self, forKey: .merchant)
        category = try c.decode(String.self, forKey: .category)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        lineItems = try c.decodeIfPresent([LineItem].self, forKey: .lineItems)
        type = try c.decode(String.self, forKey: .type)
        source = try c.decode(String.self, forKey: .source)
        account = try c.decodeIfPresent(String.self, forKey: .account)
        rawText = try c.decodeIfPresent(String.self, forKey: .rawText)
        date = try c.decode(Date.self, forKey: .date)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        categorizedByAI = (try? c.decode(Bool.self, forKey: .categorizedByAI)) ?? false
    }

    init(id: String, amount: Double, currencySymbol: String, currencyCode: String,
         merchant: String, category: String, description: String?, lineItems: [LineItem]?,
         type: String, source: String, account: String?, rawText: String?,
         date: Date, createdAt: Date, categorizedByAI: Bool = false) {
        self.id = id; self.amount = amount; self.currencySymbol = currencySymbol
        self.currencyCode = currencyCode; self.merchant = merchant; self.category = category
        self.description = description; self.lineItems = lineItems; self.type = type
        self.source = source; self.account = account; self.rawText = rawText
        self.date = date; self.createdAt = createdAt; self.categorizedByAI = categorizedByAI
    }

    var formattedAmount: String {
        let prefix = isCredit ? "+" : "-"
        return "\(prefix)\(currencySymbol)\(String(format: "%.2f", amount))"
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    var sourceIcon: String {
        switch source {
        case "BANK": return "building.columns.fill"
        case "EMAIL": return "envelope.fill"
        case "SMS": return "message.fill"
        default: return "pencil.circle.fill"
        }
    }
}

// MARK: - Line Item Model

struct LineItem: Codable, Identifiable {
    let id: String
    let name: String
    let quantity: Int
    let amount: Double

    init(name: String, quantity: Int = 1, amount: Double) {
        self.id = UUID().uuidString
        self.name = name
        self.quantity = quantity
        self.amount = amount
    }
}

// MARK: - Email Parse Result

struct EmailParseResult {
    let amount: Double
    let currencySymbol: String
    let currencyCode: String
    let merchant: String
    let type: String
    var date: Date
    let description: String?
    let lineItems: [LineItem]?
}
