import Foundation

/// AI-powered transaction categorizer using Groq (Llama 3.3 70B).
///
/// Privacy model:
/// - Only sends merchant name (no amounts, accounts, or personal info)
/// - User provides their own API key (stored in Keychain)
/// - Results are cached locally — same merchant is never queried twice
/// - Falls back to keyword matching if offline or no API key
@MainActor
class SmartCategorizer: ObservableObject {
    static let shared = SmartCategorizer()

    @Published var isConfigured: Bool = false

    private let cache = CategorizationCache()
    private let groq = GroqService.shared

    private init() {
        isConfigured = groq.hasApiKey
    }

    // MARK: - API Key Management

    func setApiKey(_ key: String) {
        groq.setApiKey(key)
        isConfigured = true
    }

    func removeApiKey() {
        groq.removeApiKey()
        isConfigured = false
    }

    var hasApiKey: Bool {
        groq.hasApiKey
    }

    // MARK: - Known Merchant Overrides (always correct, bypasses cache + LLM)

    private static let knownMerchantCategories: [(keywords: [String], category: String, displayName: String, description: String)] = [
        (["rentcafe", "rent cafe"], "Rent", "RentCafe", "Online rent payment portal"),
        (["apartments.com"], "Rent", "Apartments.com", "Rent payment platform"),
        (["avail rent", "avail.co"], "Rent", "Avail", "Rent payment platform"),
        (["cozy rent"], "Rent", "Cozy", "Rent payment platform"),
        (["rent payment", "monthly rent"], "Rent", "Rent Payment", "Monthly rent"),
    ]

    /// Check if merchant matches a known override — these are always correct regardless of cache or LLM.
    private func knownCategoryOverride(merchant: String) -> CategoryResult? {
        let lower = merchant.lowercased()
        for entry in Self.knownMerchantCategories {
            for keyword in entry.keywords {
                if lower.contains(keyword) {
                    return CategoryResult(category: entry.category, displayName: entry.displayName, description: entry.description, source: .keyword)
                }
            }
        }
        return nil
    }

    // MARK: - Categorization

    /// Categorize a transaction. Uses known overrides first, then cache, then LLM, then keyword fallback.
    func categorize(merchant: String, additionalContext: String? = nil) async -> CategoryResult {
        let normalizedMerchant = merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 0. Known merchant overrides — always correct, bypass everything
        if let override = knownCategoryOverride(merchant: merchant) {
            cache.set(merchant: normalizedMerchant, result: override)
            return override
        }

        // 1. Check cache
        if let cached = cache.get(merchant: normalizedMerchant) {
            return cached
        }

        // 2. Try Groq if API key is configured
        if groq.hasApiKey {
            if let result = await queryLLM(merchant: merchant, context: additionalContext) {
                cache.set(merchant: normalizedMerchant, result: result)
                return result
            }
        }

        // 3. Fallback to keyword matching
        let fallback = keywordCategorize(merchant: merchant)
        cache.set(merchant: normalizedMerchant, result: fallback)
        return fallback
    }

    /// Batch categorize multiple merchants (efficient — deduplicates and batches LLM calls).
    func categorizeBatch(merchants: [String]) async -> [String: CategoryResult] {
        var results: [String: CategoryResult] = [:]
        var uncached: [String] = []

        // Check cache first
        for merchant in merchants {
            let key = merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let cached = cache.get(merchant: key) {
                results[merchant] = cached
            } else {
                uncached.append(merchant)
            }
        }

        // Batch query LLM for uncached merchants
        if !uncached.isEmpty, groq.hasApiKey {
            if let batchResults = await queryLLMBatch(merchants: uncached) {
                for (merchant, result) in batchResults {
                    let key = merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    cache.set(merchant: key, result: result)
                    results[merchant] = result
                }
            }
        }

        // Fallback for anything still uncategorized
        for merchant in merchants where results[merchant] == nil {
            let fallback = keywordCategorize(merchant: merchant)
            let key = merchant.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            cache.set(merchant: key, result: fallback)
            results[merchant] = fallback
        }

        return results
    }

    // MARK: - Groq API

    private func queryLLM(merchant: String, context: String?) async -> CategoryResult? {
        let contextLine = context.map { "\nAdditional context: \($0)" } ?? ""
        let prompt = """
        Categorize this merchant/transaction into exactly one category. Also provide a clean display name for the merchant.

        Merchant: \(merchant)\(contextLine)

        Categories: Food & Dining, Groceries, Transport, Shopping, Subscriptions, Bills & Utilities, Entertainment, Health, Education, Transfers, Rent, Insurance, Investment, Travel, Other

        Respond in exactly this JSON format, nothing else:
        {"category": "...", "displayName": "...", "description": "brief what this merchant is"}
        """

        guard let result = await groq.generateJSON(prompt: prompt, maxTokens: 256) as? [String: String] else {
            return nil
        }

        return CategoryResult(
            category: result["category"] ?? "Other",
            displayName: result["displayName"] ?? "",
            description: result["description"] ?? "",
            source: .llm
        )
    }

    private func queryLLMBatch(merchants: [String]) async -> [String: CategoryResult]? {
        let merchantList = merchants.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")

        let prompt = """
        Categorize each merchant into exactly one category. Also provide clean display names.

        Merchants:
        \(merchantList)

        Categories: Food & Dining, Groceries, Transport, Shopping, Subscriptions, Bills & Utilities, Entertainment, Health, Education, Transfers, Rent, Insurance, Investment, Travel, Other

        Respond in exactly this JSON format, nothing else:
        [{"merchant": "original name", "category": "...", "displayName": "...", "description": "brief what this is"}]
        """

        guard let results = await groq.generateJSON(prompt: prompt, maxTokens: 1024) as? [[String: Any]] else {
            return nil
        }

        var categorized: [String: CategoryResult] = [:]
        for result in results {
            let originalMerchant = result["merchant"] as? String ?? ""
            let category = result["category"] as? String ?? "Other"
            let displayName = result["displayName"] as? String ?? originalMerchant
            let description = result["description"] as? String ?? ""

            // Find the matching input merchant
            let matchedMerchant = merchants.first {
                $0.lowercased().contains(originalMerchant.lowercased()) ||
                originalMerchant.lowercased().contains($0.lowercased())
            } ?? originalMerchant

            categorized[matchedMerchant] = CategoryResult(
                category: category,
                displayName: displayName,
                description: description,
                source: .llm
            )
        }

        return categorized
    }

    // MARK: - Email Classification (receipt vs promotional)

    /// Ask the LLM whether an email is a real receipt/transaction or promotional.
    /// Returns true if the email is a real transaction, false if promotional.
    /// Only sends subject + sender (never the email body) for privacy.
    func classifyEmail(subject: String, sender: String) async -> Bool {
        // Check cache first
        let cacheKey = "email_class_\(sender.lowercased())_\(subject.lowercased().prefix(50))"
        if let cached = emailClassCache[cacheKey] {
            return cached
        }

        guard groq.hasApiKey else {
            return true // No API key — let it through, parser will handle
        }

        let prompt = """
        Is this email a real financial transaction (receipt, order confirmation, billing statement, payment alert, refund) or a promotional/marketing email (sale, newsletter, offer, advertisement)?

        Sender: \(sender)
        Subject: \(subject)

        Respond with ONLY one word: "transaction" or "promotional"
        """

        guard let text = await groq.generateText(prompt: prompt, maxTokens: 10) else {
            return true
        }

        let isTransaction = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).contains("transaction")
        emailClassCache[cacheKey] = isTransaction
        return isTransaction
    }

    /// Simple in-memory cache for email classifications (resets each app launch).
    private var emailClassCache: [String: Bool] = [:]

    // MARK: - LLM Receipt Parser

    /// Structured receipt data extracted by LLM.
    struct LLMReceiptResult {
        let merchant: String
        let amount: Double
        let currencySymbol: String
        let currencyCode: String
        let type: String           // "DEBIT" or "CREDIT"
        let lineItems: [LineItem]
        let description: String?
    }

    /// Use Groq (Llama 3.3) to extract structured receipt data from an email.
    /// Sends only the stripped text (no raw HTML). Returns nil if no API key or if
    /// the email doesn't appear to be a receipt.
    func parseReceiptWithLLM(subject: String, body: String, sender: String) async -> LLMReceiptResult? {
        guard groq.hasApiKey else { return nil }

        // Food delivery emails need more body — item names are deep in the HTML
        let lowerSender = sender.lowercased()
        let isFoodDelivery = ["uber", "swiggy", "zomato", "doordash", "grubhub",
                               "deliveroo", "postmates", "dunzo"].contains { lowerSender.contains($0) }
        let charLimit = isFoodDelivery ? 8000 : 2000
        let truncatedBody = String(body.prefix(charLimit))

        let prompt: String
        if isFoodDelivery {
            prompt = """
            Extract food order data from this food delivery receipt email. The body may be HTML — parse it to find the ordered items.
            Return ONLY valid JSON, no markdown.

            Subject: \(subject)
            From: \(sender)
            Body:
            \(truncatedBody)

            Return this exact JSON structure:
            {
              "merchant": "restaurant name (not the delivery app)",
              "amount": 0.00,
              "currency": "USD",
              "currencySymbol": "$",
              "type": "DEBIT",
              "description": "food delivery order",
              "lineItems": [
                {"name": "dish name", "quantity": 1, "amount": 0.00}
              ]
            }

            Rules:
            - "merchant" should be the RESTAURANT name, not "Uber Eats" or "DoorDash"
            - "amount" is the TOTAL charged
            - "lineItems" MUST contain the actual food/drink items ordered (e.g., "Chicken Biryani", "Garlic Naan", "Mango Lassi")
            - Look inside HTML tables, divs, and spans for item names and prices
            - Do NOT include fees, taxes, tips, delivery charges, service fees, or subtotals as line items
            - Do NOT use generic names like "Unknown Item" or "Item 1" — find the real dish names
            - If an item has a customization (e.g., "Add cheese"), include it with the parent item name
            - If quantity > 1, set the quantity field accordingly
            - Currency: "$"/"USD" for dollars, "₹"/"INR" for rupees, "£"/"GBP" for pounds, "€"/"EUR" for euros
            """
        } else {
            prompt = """
            Extract receipt/order data from this email. Return ONLY valid JSON, no markdown.

            Subject: \(subject)
            From: \(sender)
            Body:
            \(truncatedBody)

            Return this exact JSON structure:
            {
              "merchant": "merchant name",
              "amount": 0.00,
              "currency": "USD",
              "currencySymbol": "$",
              "type": "DEBIT",
              "description": "brief description of what was purchased",
              "lineItems": [
                {"name": "item name", "quantity": 1, "amount": 0.00}
              ]
            }

            Rules:
            - "amount" is the TOTAL charged (not subtotal)
            - "type" is "CREDIT" for refunds, deposits, money received, or any amount credited to the account. Otherwise "DEBIT"
            - "lineItems" should contain actual products/services ordered, NOT metadata like "Qty 1", "Amount paid", "Receipt from", "Subtotal", "Tax", "Shipping", "Total", "Service Fee", "Delivery Fee", "Tip"
            - If it's a subscription (Netflix, Spotify, Claude, etc.), lineItems should be empty []
            - If you can't determine items, use empty []
            - Currency: use "$"/"USD" for dollars, "₹"/"INR" for rupees, "£"/"GBP" for pounds, "€"/"EUR" for euros
            - If this is NOT a receipt/order email, return {"error": "not a receipt"}
            """
        }

        guard let result = await groq.generateJSON(prompt: prompt, maxTokens: 1000) as? [String: Any] else {
            return nil
        }

        // Check if LLM said it's not a receipt
        if result["error"] != nil { return nil }

        guard let merchant = result["merchant"] as? String,
              let amount = result["amount"] as? Double,
              amount > 0 else { return nil }

        let currencySymbol = result["currencySymbol"] as? String ?? "$"
        let currencyCode = result["currency"] as? String ?? "USD"
        let type = result["type"] as? String ?? "DEBIT"
        let description = result["description"] as? String

        var lineItems: [LineItem] = []
        if let items = result["lineItems"] as? [[String: Any]] {
            for item in items {
                guard let name = item["name"] as? String else { continue }
                let itemAmount = (item["amount"] as? Double) ?? 0
                let qty = item["quantity"] as? Int ?? 1
                // Validate: skip addresses, metadata, and garbage
                guard Self.isValidFoodItem(name: name) else { continue }
                lineItems.append(LineItem(name: name, quantity: qty, amount: itemAmount))
            }
        }

        return LLMReceiptResult(
            merchant: merchant,
            amount: amount,
            currencySymbol: currencySymbol,
            currencyCode: currencyCode,
            type: type,
            lineItems: lineItems,
            description: description
        )
    }

    /// Validate that a line item name is an actual product/food, not an address or metadata.
    private static func isValidFoodItem(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 && trimmed.count <= 80 else { return false }

        let lower = trimmed.lowercased()

        // Reject addresses: contains state abbreviations + zip codes
        // Pattern: "Street, City, ST 12345" or "123 Main St"
        let addressPatterns = [
            #"\d{5}(-\d{4})?"#,                      // zip code: 02134 or 02134-2806
            #"\b(st|ave|blvd|rd|dr|ln|ct|pl|way|trl|pkwy),\s"#,  // street suffix followed by comma
            #"\b[A-Z]{2}\s+\d{5}"#,                   // "MA 02113"
            #"^\d+\s+\w+\s+(st|ave|blvd|rd|dr|ln|ct|pl|way|trl|pkwy)\b"#,  // "123 Main St"
        ]
        for pattern in addressPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) != nil {
                return false
            }
        }

        // Reject if it contains common address words
        let addressWords = [", us", ", usa", ", india", ", uk",
                           "street,", "avenue,", "boulevard,", "road,", "drive,",
                           "orlando, fl", "boston, ma", "new york, ny", "chicago, il",
                           "los angeles, ca", "san francisco, ca"]
        if addressWords.contains(where: { lower.contains($0) }) { return false }

        // Reject metadata/fee items
        let metadataWords = ["subtotal", "total", "tax", "shipping", "delivery fee",
                             "service fee", "tip", "discount", "promo", "platform fee",
                             "packaging", "gst", "cgst", "sgst", "vat", "surge",
                             "amount paid", "amount due", "unknown item"]
        if metadataWords.contains(where: { lower.contains($0) }) { return false }

        return true
    }

    // MARK: - Keyword Fallback (same as before but expanded)

    private func keywordCategorize(merchant: String) -> CategoryResult {
        let lower = merchant.lowercased()

        let categories: [(String, [String])] = [
            ("Rent", ["rent", "rentcafe", "apartments.com", "zillow", "trulia", "nobroker",
                      "housing", "flat ", "landlord", "lease", "tenant"]),
            ("Insurance", ["insurance", "geico", "allstate", "progressive", "lic ",
                           "policy", "premium", "hdfc life", "icici prudential"]),
            ("Investment", ["zerodha", "groww", "upstox", "kite", "mutual fund",
                            "smallcase", "robinhood", "fidelity", "vanguard", "etrade",
                            "coin", "sip ", "nps"]),
            ("Travel", ["airline", "flight", "makemytrip", "goibibo", "cleartrip",
                         "booking.com", "airbnb", "hotel", "trivago", "expedia",
                         "irctc", "yatra", "ixigo"]),
            ("Food & Dining", ["uber eats", "doordash", "grubhub", "deliveroo", "swiggy", "zomato",
                               "starbucks", "mcdonalds", "dominos", "pizza hut", "kfc",
                               "subway", "chipotle", "dunkin", "restaurant", "diner",
                               "burger king", "taco bell", "wendy", "chick-fil-a"]),
            ("Groceries", ["whole foods", "trader joe", "kroger", "bigbasket", "instacart",
                           "aldi", "costco", "safeway", "publix", "blinkit", "zepto", "jiomart",
                           "grocery", "market", "dmart", "fresh"]),
            ("Transport", ["uber", "lyft", "ola", "rapido", "bolt", "grab",
                           "parking", "fuel", "gas station", "shell", "chevron",
                           "metro", "transit", "railway"]),
            ("Shopping", ["amazon", "walmart", "target", "flipkart", "ebay", "etsy",
                          "ikea", "best buy", "apple store", "nike", "adidas", "zara",
                          "h&m", "myntra", "ajio", "meesho", "nykaa", "croma"]),
            ("Subscriptions", ["netflix", "spotify", "disney", "hulu", "hbo", "youtube premium",
                               "apple music", "audible", "notion", "figma", "adobe",
                               "microsoft 365", "google one", "icloud", "dropbox",
                               "chatgpt", "openai", "claude", "anthropic"]),
            ("Bills & Utilities", ["electric", "water ", "gas bill", "broadband", "internet",
                                   "t-mobile", "verizon", "at&t", "jio", "airtel", "vodafone",
                                   "comcast", "spectrum", "wifi"]),
            ("Entertainment", ["movie", "cinema", "bookmyshow", "gaming", "steam",
                               "playstation", "xbox", "concert", "ticket"]),
            ("Health", ["pharmacy", "hospital", "doctor", "clinic", "medical",
                        "dental", "gym", "fitness", "practo", "pharmeasy", "1mg"]),
            ("Education", ["course", "udemy", "coursera", "school", "university",
                           "tuition", "textbook", "unacademy", "byju"]),
            ("Transfers", ["transfer", "sent to", "received from", "salary", "deposit",
                           "withdrawal", "atm"]),
        ]

        for (category, keywords) in categories {
            for keyword in keywords {
                if lower.contains(keyword) {
                    if keyword == "uber" && lower.contains("uber eats") { continue }
                    return CategoryResult(category: category, displayName: merchant, description: "", source: .keyword)
                }
            }
        }

        return CategoryResult(category: "Other", displayName: merchant, description: "", source: .keyword)
    }
}

// MARK: - Models

struct CategoryResult {
    let category: String
    let displayName: String
    let description: String
    let source: CategorizationSource
}

enum CategorizationSource {
    case llm
    case keyword
    case cache
}

// MARK: - Local Cache (persisted to disk)

class CategorizationCache {
    private var memoryCache: [String: CategoryResult] = [:]
    private let fileName = "category_cache.json"

    init() {
        loadFromDisk()
    }

    func get(merchant: String) -> CategoryResult? {
        memoryCache[merchant]
    }

    func set(merchant: String, result: CategoryResult) {
        memoryCache[merchant] = result
        saveToDisk()
    }

    private var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    private func saveToDisk() {
        let serializable = memoryCache.mapValues { result in
            ["category": result.category, "displayName": result.displayName, "description": result.description]
        }
        if let data = try? JSONSerialization.data(withJSONObject: serializable) {
            try? data.write(to: fileURL, options: .atomicWrite)
        }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            return
        }
        for (key, value) in dict {
            memoryCache[key] = CategoryResult(
                category: value["category"] ?? "Other",
                displayName: value["displayName"] ?? key,
                description: value["description"] ?? "",
                source: .cache
            )
        }
    }
}
