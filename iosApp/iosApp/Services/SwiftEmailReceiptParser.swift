import Foundation

/// Swift-side email receipt parser that mirrors the shared Kotlin EmailReceiptParser.
/// This will be replaced by the Kotlin shared module once KMP framework is linked.
///
/// Parses email bodies from Gmail to extract transaction data.
/// Supports vendor-specific parsers (Amazon, Uber, Netflix) with a generic fallback.
struct SwiftEmailReceiptParser {

    /// Parse an email into a transaction result.
    /// Returns nil if the email doesn't look like a receipt.
    /// Headers-based overload for smart classification.
    static func parse(email: EmailMessage) -> EmailParseResult? {
        return parse(subject: email.subject, body: email.body, senderEmail: email.senderEmail,
                     hasListUnsubscribe: email.hasListUnsubscribe,
                     precedence: email.precedence,
                     hasCampaignHeaders: email.hasCampaignHeaders)
    }

    /// Parse an email into a transaction result.
    /// Returns nil if the email doesn't look like a receipt.
    static func parse(subject: String, body: String, senderEmail: String,
                      hasListUnsubscribe: Bool = false,
                      precedence: String? = nil,
                      hasCampaignHeaders: Bool = false) -> EmailParseResult? {
        let lowerSender = senderEmail.lowercased()
        let lowerSubject = subject.lowercased()
        let strippedBody = stripHtml(body)
        let lowerBody = strippedBody.lowercased()

        // MARK: - Score-based promotional detection (not hardcoded keywords)
        let promoScore = calculatePromoScore(
            subject: lowerSubject, body: lowerBody, sender: lowerSender,
            hasListUnsubscribe: hasListUnsubscribe,
            precedence: precedence,
            hasCampaignHeaders: hasCampaignHeaders
        )

        // High promo score = definitely promotional, skip it
        if promoScore >= 60 {
            return nil
        }

        // Try vendor-specific parsers first — with tighter sender matching
        // Amazon: only match actual order/shipping/billing emails, not amazonmusic, amazongames, etc.
        let amazonTransactionalSenders = ["auto-confirm@amazon", "ship-confirm@amazon", "digital-no-reply@amazon",
                                           "payments-messages@amazon", "order-update@amazon", "returns@amazon"]
        if amazonTransactionalSenders.contains(where: { lowerSender.contains($0) }) {
            return parseAmazon(subject: subject, body: body)
        }
        // Also match generic amazon.com sender IF subject indicates a real order
        if lowerSender.hasSuffix("@amazon.com") &&
            (lowerSubject.contains("order") || lowerSubject.contains("receipt") ||
             lowerSubject.contains("invoice") || lowerSubject.contains("refund") ||
             lowerSubject.contains("payment") || lowerSubject.contains("shipped")) {
            return parseAmazon(subject: subject, body: body)
        }

        if lowerSender.contains("uber") && !lowerSender.contains("uberdirect") {
            return parseUber(subject: subject, body: body)
        }
        if lowerSender.contains("netflix") && (lowerSubject.contains("payment") || lowerSubject.contains("billing") || lowerSubject.contains("receipt") || lowerSubject.contains("charged")) {
            return parseSubscription(body: body, merchant: "Netflix")
        }
        if lowerSender.contains("spotify") && (lowerSubject.contains("receipt") || lowerSubject.contains("payment") || lowerSubject.contains("premium")) {
            return parseSubscription(body: body, merchant: "Spotify")
        }
        if lowerSender.contains("apple") && lowerSubject.contains("receipt") {
            return parseSubscription(body: body, merchant: "Apple")
        }
        if lowerSender.contains("google") && (lowerSubject.contains("receipt") || lowerSubject.contains("payment")) {
            return parseSubscription(body: body, merchant: "Google")
        }

        // Generic fallback — look for receipt patterns
        return parseGeneric(subject: subject, body: body, senderEmail: senderEmail)
    }

    // MARK: - Line Item Extraction

    /// Extract individual items from an email receipt body.
    static func extractLineItems(from body: String) -> [LineItem] {
        let text = stripHtml(body)
        var items: [LineItem] = []

        // Pattern: "Item Name ... $XX.XX" or "Item Name  Qty  $XX.XX"
        let patterns = [
            // "Product Name $19.99" or "Product Name Rs.199.00"
            #"(?m)^[\s]*([A-Za-z][\w\s&'.,/-]{2,40}?)\s{2,}(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})\s*$"#,
            // "1 x Product Name $19.99"
            #"(\d+)\s*[xX×]\s+([A-Za-z][\w\s&'.,/-]{2,40}?)\s+(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})"#,
            // "Product Name (x2) $19.99"
            #"([A-Za-z][\w\s&'.,/-]{2,40}?)\s*\(x?(\d+)\)\s*(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})"#,
        ]

        // Try first pattern (name ... amount)
        if let regex = try? NSRegularExpression(pattern: patterns[0], options: .anchorsMatchLines) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: text),
                   let amountRange = Range(match.range(at: 2), in: text) {
                    let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
                    let amountStr = String(text[amountRange]).replacingOccurrences(of: ",", with: "")
                    if let amount = Double(amountStr), amount > 0 {
                        // Skip lines that are clearly not items
                        let lowerName = name.lowercased()
                        let skipWords = ["subtotal", "total", "tax", "shipping", "delivery", "discount", "tip", "fee",
                                         "amount paid", "amount due", "amount charged", "payment", "receipt from",
                                         "qty ", "quantity", "balance", "invoice", "billing", "charged to"]
                        if !skipWords.contains(where: { lowerName.contains($0) }) {
                            items.append(LineItem(name: name, amount: amount))
                        }
                    }
                }
            }
        }

        // Try second pattern (qty x name amount)
        if items.isEmpty, let regex = try? NSRegularExpression(pattern: patterns[1]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let qtyRange = Range(match.range(at: 1), in: text),
                   let nameRange = Range(match.range(at: 2), in: text),
                   let amountRange = Range(match.range(at: 3), in: text) {
                    let qty = Int(String(text[qtyRange])) ?? 1
                    let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
                    let amountStr = String(text[amountRange]).replacingOccurrences(of: ",", with: "")
                    if let amount = Double(amountStr), amount > 0 {
                        items.append(LineItem(name: name, quantity: qty, amount: amount))
                    }
                }
            }
        }

        return items.filter { !looksLikeAddress($0.name) }
    }

    // MARK: - Vendor Parsers

    private static func parseAmazon(subject: String, body: String) -> EmailParseResult? {
        let text = stripHtml(body)
        guard let amount = extractAmount(from: text) else { return nil }

        let isCredit = isCreditTransaction(subject: subject.lowercased(), body: text.lowercased())
        let items = extractLineItems(from: body)

        return EmailParseResult(
            amount: amount.value,
            currencySymbol: amount.symbol,
            currencyCode: amount.code,
            merchant: "Amazon",
            type: isCredit ? "CREDIT" : "DEBIT",
            date: Date(),
            description: items.isEmpty ? subject : "Ordered: \(items.map(\.name).joined(separator: ", "))",
            lineItems: items.isEmpty ? nil : items
        )
    }

    private static func parseUber(subject: String, body: String) -> EmailParseResult? {
        let text = stripHtml(body)
        let lower = subject.lowercased()
        let merchant = lower.contains("eats") ? "Uber Eats" : "Uber"

        var items: [LineItem]? = nil
        if merchant == "Uber Eats" {
            items = extractFoodDeliveryItems(from: text)
            if items?.isEmpty ?? true {
                items = extractLineItems(from: body)
            }
        }

        if let totalAmount = extractTotalAmount(from: text) {
            return EmailParseResult(
                amount: totalAmount.value,
                currencySymbol: totalAmount.symbol,
                currencyCode: totalAmount.code,
                merchant: merchant,
                type: "Debit",
                date: Date(),
                description: merchant == "Uber" ? "Ride" : items.map { "Order: \($0.map(\.name).joined(separator: ", "))" },
                lineItems: items
            )
        }

        guard let amount = extractAmount(from: text) else { return nil }

        return EmailParseResult(
            amount: amount.value,
            currencySymbol: amount.symbol,
            currencyCode: amount.code,
            merchant: merchant,
            type: "Debit",
            date: Date(),
            description: nil,
            lineItems: items
        )
    }

    /// Check if a string looks like an address rather than a food/product item.
    static func looksLikeAddress(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Zip code pattern
        if let regex = try? NSRegularExpression(pattern: #"\d{5}(-\d{4})?"#),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        // "City, ST" pattern (2-letter state code after comma)
        if let regex = try? NSRegularExpression(pattern: #",\s*[A-Z]{2}\s+\d"#),
           regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            return true
        }
        // Common address suffixes
        let addressIndicators = [", us", ", usa", "street,", "avenue,", "boulevard,",
                                  "road,", "drive,", ", ma ", ", ny ", ", ca ", ", fl ",
                                  ", tx ", ", il ", ", oh ", ", pa ", ", wa "]
        return addressIndicators.contains { lower.contains($0) }
    }

    /// Extract food items from food delivery email text (Uber Eats, Swiggy, Zomato, etc.)
    /// These emails often have items in formats like:
    ///   "1 x Chicken Biryani $12.99"
    ///   "Butter Naan x2 ₹80"
    ///   "Chicken Biryani 1 $12.99"
    ///   "Chicken Biryani  $12.99" (name followed by price)
    static func extractFoodDeliveryItems(from text: String) -> [LineItem] {
        var items: [LineItem] = []

        let skipWords: Set<String> = [
            "subtotal", "total", "tax", "shipping", "delivery", "discount", "tip", "fee",
            "service fee", "delivery fee", "amount paid", "amount due", "amount charged",
            "payment", "promo", "promotion", "coupon", "packaging", "platform fee",
            "gst", "cgst", "sgst", "vat", "surge", "busy fee", "small order fee"
        ]

        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.lowercased()
            if skipWords.contains(where: { lower.contains($0) }) { continue }

            // Pattern: "1 x Item Name $12.99" or "1x Item Name ₹199"
            if let match = line.range(of: #"^(\d+)\s*[xX×]\s+(.+?)\s+(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})\s*$"#, options: .regularExpression) {
                let matched = String(line[match])
                if let parsed = parseQtyNameAmount(matched, pattern: #"^(\d+)\s*[xX×]\s+(.+?)\s+(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})\s*$"#) {
                    items.append(parsed)
                    continue
                }
            }

            // Pattern: "Item Name x2 $12.99" or "Item Name ×1 ₹199"
            if let match = line.range(of: #"^(.+?)\s+[xX×](\d+)\s+(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})\s*$"#, options: .regularExpression) {
                let matched = String(line[match])
                if let parsed = parseNameQtyAmount(matched, pattern: #"^(.+?)\s+[xX×](\d+)\s+(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})\s*$"#) {
                    items.append(parsed)
                    continue
                }
            }

            // Pattern: "Item Name  $12.99" (name then price, at least 2 spaces or tab between)
            if let match = line.range(of: #"^([A-Za-z][\w\s&'.,/()-]{2,45}?)\s{2,}(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})\s*$"#, options: .regularExpression) {
                let matched = String(line[match])
                if let parsed = parseNameAmount(matched, pattern: #"^([A-Za-z][\w\s&'.,/()-]{2,45}?)\s{2,}(?:[\$₹£€]|Rs\.?\s*)([\d,]+\.?\d{0,2})\s*$"#) {
                    let lowerName = parsed.name.lowercased()
                    if !skipWords.contains(where: { lowerName.contains($0) }) {
                        items.append(parsed)
                        continue
                    }
                }
            }

            // Pattern: "1 Item Name" (qty followed by item name, no price — common in Uber Eats summaries)
            if items.isEmpty, let _ = line.range(of: #"^(\d+)\s+([A-Za-z][\w\s&'.,/()-]{2,45})$"#, options: .regularExpression) {
                let regex = try? NSRegularExpression(pattern: #"^(\d+)\s+([A-Za-z][\w\s&'.,/()-]{2,45})$"#)
                if let m = regex?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                   let qtyRange = Range(m.range(at: 1), in: line),
                   let nameRange = Range(m.range(at: 2), in: line) {
                    let qty = Int(String(line[qtyRange])) ?? 1
                    let name = String(line[nameRange]).trimmingCharacters(in: .whitespaces)
                    let lowerName = name.lowercased()
                    if !skipWords.contains(where: { lowerName.contains($0) }) && name.count > 2 {
                        items.append(LineItem(name: name, quantity: qty, amount: 0))
                    }
                }
            }
        }

        return items.filter { !looksLikeAddress($0.name) }
    }

    private static func parseQtyNameAmount(_ text: String, pattern: String) -> LineItem? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let qtyRange = Range(m.range(at: 1), in: text),
              let nameRange = Range(m.range(at: 2), in: text),
              let amtRange = Range(m.range(at: 3), in: text) else { return nil }
        let qty = Int(String(text[qtyRange])) ?? 1
        let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
        let amount = Double(String(text[amtRange]).replacingOccurrences(of: ",", with: "")) ?? 0
        guard name.count > 1 else { return nil }
        return LineItem(name: name, quantity: qty, amount: amount)
    }

    private static func parseNameQtyAmount(_ text: String, pattern: String) -> LineItem? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(m.range(at: 1), in: text),
              let qtyRange = Range(m.range(at: 2), in: text),
              let amtRange = Range(m.range(at: 3), in: text) else { return nil }
        let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
        let qty = Int(String(text[qtyRange])) ?? 1
        let amount = Double(String(text[amtRange]).replacingOccurrences(of: ",", with: "")) ?? 0
        guard name.count > 1 else { return nil }
        return LineItem(name: name, quantity: qty, amount: amount)
    }

    private static func parseNameAmount(_ text: String, pattern: String) -> LineItem? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let nameRange = Range(m.range(at: 1), in: text),
              let amtRange = Range(m.range(at: 2), in: text) else { return nil }
        let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
        let amount = Double(String(text[amtRange]).replacingOccurrences(of: ",", with: "")) ?? 0
        guard name.count > 1 else { return nil }
        return LineItem(name: name, quantity: 1, amount: amount)
    }

    private static func parseSubscription(body: String, merchant: String) -> EmailParseResult? {
        let text = stripHtml(body)
        guard let amount = extractAmount(from: text) else { return nil }

        return EmailParseResult(
            amount: amount.value,
            currencySymbol: amount.symbol,
            currencyCode: amount.code,
            merchant: merchant,
            type: "Debit",
            date: Date(),
            description: "\(merchant) subscription",
            lineItems: nil
        )
    }

    private static func parseGeneric(subject: String, body: String, senderEmail: String) -> EmailParseResult? {
        let text = stripHtml(body)
        let lowerSubject = subject.lowercased()
        let lowerBody = text.lowercased()

        // Strong signals: these keywords in the SUBJECT are reliable
        let subjectKeywords = ["receipt", "order confirmation", "invoice", "payment received",
                               "payment confirmation", "billing statement", "your purchase",
                               "transaction alert", "debited", "credited", "refund"]
        let hasSubjectSignal = subjectKeywords.contains { lowerSubject.contains($0) }

        // Weak signals: these in the BODY need a price keyword nearby to be reliable
        let bodyKeywords = ["total", "amount charged", "amount paid", "order total",
                            "payment of", "you paid", "has been charged", "has been debited"]
        let hasBodySignal = bodyKeywords.contains { lowerBody.contains($0) }

        guard hasSubjectSignal || hasBodySignal else { return nil }

        let amount = extractTotalAmount(from: text) ?? extractAmount(from: text)
        guard let amount = amount else { return nil }

        let merchant = extractMerchantFromEmail(senderEmail)
        let isCredit = isCreditTransaction(subject: lowerSubject, body: lowerBody)
        let items = extractLineItems(from: body)

        return EmailParseResult(
            amount: amount.value,
            currencySymbol: amount.symbol,
            currencyCode: amount.code,
            merchant: merchant,
            type: isCredit ? "CREDIT" : "DEBIT",
            date: Date(),
            description: items.isEmpty ? subject : "Items: \(items.map(\.name).joined(separator: ", "))",
            lineItems: items.isEmpty ? nil : items
        )
    }

    // MARK: - Score-Based Email Classification

    /// Public access to promo score for the sync flow (to decide if LLM check needed).
    static func promoScore(for email: EmailMessage) -> Int {
        let strippedBody = stripHtml(email.body).lowercased()
        return calculatePromoScore(
            subject: email.subject.lowercased(),
            body: strippedBody,
            sender: email.senderEmail.lowercased(),
            hasListUnsubscribe: email.hasListUnsubscribe,
            precedence: email.precedence,
            hasCampaignHeaders: email.hasCampaignHeaders
        )
    }

    /// Calculate a promotional score for an email. Higher = more likely promotional.
    /// Uses email headers (most reliable), body signals, and subject signals.
    /// Score >= 60 = promotional, Score <= -20 = definitely transactional.
    private static func calculatePromoScore(
        subject: String, body: String, sender: String,
        hasListUnsubscribe: Bool, precedence: String?, hasCampaignHeaders: Bool
    ) -> Int {
        var score = 0

        // ── Layer 1: Email Headers (strongest, most reliable signals) ──
        // List-Unsubscribe header is present in ~95% of marketing emails
        // and almost never in transactional receipts
        if hasListUnsubscribe { score += 35 }

        // Precedence: bulk or list = mass email
        if let prec = precedence, (prec == "bulk" || prec == "list") { score += 25 }

        // Campaign tracking headers (Mailchimp, SendGrid, etc.)
        if hasCampaignHeaders { score += 30 }

        // ── Layer 2: Body signals (receipt indicators push score negative) ──
        let receiptPatterns = [
            "order total", "amount charged", "payment received", "your receipt",
            "transaction id", "order #", "order number", "invoice #", "invoice number",
            "shipped to", "delivery address", "tracking number", "payment confirmed",
            "billing statement", "amount due", "amount paid", "you paid"
        ]
        let receiptHits = receiptPatterns.filter { body.contains($0) }.count
        score -= receiptHits * 15  // Each receipt signal is strong negative

        let promoPatterns = [
            "shop now", "buy now", "add to cart", "view deal", "browse",
            "explore our", "view collection", "limited time offer"
        ]
        let promoHits = promoPatterns.filter { body.contains($0) }.count
        score += promoHits * 10

        // ── Layer 3: Subject signals ──
        let receiptSubjectPatterns = [
            "receipt", "order confirmation", "invoice", "payment received",
            "payment confirmation", "shipped", "delivery", "refund"
        ]
        if receiptSubjectPatterns.contains(where: { subject.contains($0) }) {
            score -= 25
        }

        let promoSubjectPatterns = [
            "% off", "sale", "deal of", "shop now", "limited time",
            "don't miss", "exclusive offer", "free shipping",
            "new arrivals", "just for you", "we miss you",
            "you're eligible", "congratulations", "try for free",
            "earn rewards", "best sellers", "trending"
        ]
        if promoSubjectPatterns.contains(where: { subject.contains($0) }) {
            score += 20
        }

        return score
    }

    // MARK: - Helpers

    private struct AmountResult {
        let value: Double
        let symbol: String
        let code: String
    }

    /// Extract the "Total" amount specifically (avoiding "Subtotal").
    private static func extractTotalAmount(from text: String) -> AmountResult? {
        let patterns: [(regex: String, symbol: String, code: String)] = [
            (#"(?i)(?<!sub)total[:\s]*\$\s*([\d,]+\.\d{2})"#, "$", "USD"),
            (#"(?i)(?<!sub)total[:\s]*₹\s*([\d,]+\.?\d{0,2})"#, "₹", "INR"),
            (#"(?i)(?<!sub)total[:\s]*£\s*([\d,]+\.\d{2})"#, "£", "GBP"),
            (#"(?i)(?<!sub)total[:\s]*€\s*([\d,]+[.,]\d{2})"#, "€", "EUR"),
            (#"(?i)(?<!sub)total[:\s]*(?:Rs\.?\s*|INR\s*)([\d,]+\.?\d{0,2})"#, "₹", "INR"),
            (#"(?i)(?<!sub)total[:\s]*(?:USD\s*|US\$\s*)([\d,]+\.\d{2})"#, "$", "USD"),
        ]

        for p in patterns {
            if let regex = try? NSRegularExpression(pattern: p.regex),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let amountStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                if let value = Double(amountStr), isReasonableAmount(value) {
                    return AmountResult(value: value, symbol: p.symbol, code: p.code)
                }
            }
        }
        return nil
    }

    /// Extract a currency amount near price-related keywords (not just any number in the email).
    private static func extractAmount(from text: String) -> AmountResult? {
        // FIRST: Try amounts near price keywords (much more reliable)
        let contextPatterns: [(regex: String, symbol: String, code: String)] = [
            // "amount: $XX.XX", "charged $XX.XX", "paid $XX.XX", "price: $XX.XX", "cost: $XX.XX"
            (#"(?i)(?:amount|charged|paid|price|cost|fee|due|billed)[:\s]*\$\s*([\d,]+\.\d{2})"#, "$", "USD"),
            (#"(?i)(?:amount|charged|paid|price|cost|fee|due|billed)[:\s]*₹\s*([\d,]+\.?\d{0,2})"#, "₹", "INR"),
            (#"(?i)(?:amount|charged|paid|price|cost|fee|due|billed)[:\s]*(?:Rs\.?\s*|INR\s*)([\d,]+\.?\d{0,2})"#, "₹", "INR"),
            (#"(?i)(?:amount|charged|paid|price|cost|fee|due|billed)[:\s]*£\s*([\d,]+\.\d{2})"#, "£", "GBP"),
            (#"(?i)(?:amount|charged|paid|price|cost|fee|due|billed)[:\s]*€\s*([\d,]+[.,]\d{2})"#, "€", "EUR"),
            // "debited Rs.XX" or "credited Rs.XX"
            (#"(?i)(?:debited|credited|deducted)\s*(?:Rs\.?\s*|₹\s*|INR\s*)([\d,]+\.?\d{0,2})"#, "₹", "INR"),
            (#"(?i)(?:debited|credited|deducted)\s*\$\s*([\d,]+\.\d{2})"#, "$", "USD"),
        ]

        for p in contextPatterns {
            if let regex = try? NSRegularExpression(pattern: p.regex),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let amountStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                if let value = Double(amountStr), isReasonableAmount(value) {
                    return AmountResult(value: value, symbol: p.symbol, code: p.code)
                }
            }
        }

        // FALLBACK: Look for currency amounts with decimal places ($.XX format = likely a price)
        let fallbackPatterns: [(regex: String, symbol: String, code: String)] = [
            (#"\$\s*([\d,]+\.\d{2})\b"#, "$", "USD"),          // Must have exactly 2 decimal places
            (#"₹\s*([\d,]+\.?\d{0,2})\b"#, "₹", "INR"),
            (#"(?i)Rs\.?\s*([\d,]+\.\d{2})\b"#, "₹", "INR"),   // Must have decimals
            (#"£\s*([\d,]+\.\d{2})\b"#, "£", "GBP"),
            (#"€\s*([\d,]+[.,]\d{2})\b"#, "€", "EUR"),
        ]

        for p in fallbackPatterns {
            if let regex = try? NSRegularExpression(pattern: p.regex),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text) {
                let amountStr = String(text[range]).replacingOccurrences(of: ",", with: "")
                if let value = Double(amountStr), isReasonableAmount(value) {
                    return AmountResult(value: value, symbol: p.symbol, code: p.code)
                }
            }
        }

        return nil
    }

    /// Sanity check: reject amounts that are obviously not transaction prices.
    private static func isReasonableAmount(_ value: Double) -> Bool {
        // Reject: zero, negative, or absurdly large amounts
        // Most personal transactions are under $50,000 / ₹50,00,000
        return value > 0.01 && value < 500_000
    }

    /// Extract merchant name from sender email domain.
    private static func extractMerchantFromEmail(_ email: String) -> String {
        // "noreply@example.com" → "Example"
        // "editor@members.wayfair.com" → "Wayfair" (skip subdomains)
        guard let atIndex = email.firstIndex(of: "@") else { return "Unknown" }
        let domain = String(email[email.index(after: atIndex)...])
        let parts = domain.split(separator: ".").map { String($0) }

        // For domains with 3+ parts (subdomain.brand.tld), use the second-to-last as brand
        // e.g., "members.wayfair.com" → "wayfair", "mail.google.com" → "google"
        // For 2-part domains (brand.com), use first part
        let skipNames = Set(["mail", "email", "members", "notifications", "alerts", "noreply",
                             "no-reply", "support", "info", "marketing", "editor", "news"])

        if parts.count >= 3 {
            // Try second-to-last (brand name in most subdomained emails)
            let brandPart = parts[parts.count - 2]
            if !skipNames.contains(brandPart.lowercased()) {
                return brandPart.capitalized
            }
        }

        // Fallback: first non-skip part
        for part in parts {
            if !skipNames.contains(part.lowercased()) && part.count > 2 {
                return part.capitalized
            }
        }

        guard let name = parts.first else { return "Unknown" }
        return String(name).capitalized
    }

    /// Public accessor for HTML stripping (used by LLM parser).
    static func stripHtmlPublic(_ html: String) -> String {
        stripHtml(html)
    }

    /// Detect if a transaction is a credit (refund, deposit, money received).
    private static func isCreditTransaction(subject: String, body: String) -> Bool {
        let creditKeywords = [
            "refund", "credited", "credit to", "deposit", "deposited",
            "money received", "amount received", "cashback", "cash back",
            "reversal", "reimbursement", "payment received"
        ]
        return creditKeywords.contains { subject.contains($0) || body.contains($0) }
    }

    /// Strip HTML tags from email body.
    private static func stripHtml(_ html: String) -> String {
        var text = html
        // Remove style and script blocks
        if let regex = try? NSRegularExpression(pattern: "<(style|script)[^>]*>.*?</\\1>", options: [.dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        // Replace <br>, <p>, <div>, <tr>, <li> with newlines
        if let regex = try? NSRegularExpression(pattern: "<(?:br|/p|/div|/tr|/li)[^>]*>", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        }
        // Remove remaining tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#36;", with: "$")
        text = text.replacingOccurrences(of: "&#8377;", with: "₹")
        // Collapse whitespace
        if let regex = try? NSRegularExpression(pattern: "[ \\t]+") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
