import Foundation

/// Extracts food item details from food delivery order pages.
/// When receipt emails don't contain items (e.g., Uber Eats), this service:
/// 1. Extracts "View Order" / "View Receipt" URLs from the email HTML
/// 2. Fetches the linked page (often has an embedded auth token)
/// 3. Parses the page HTML for food item names and prices
struct FoodOrderScraper {

    // MARK: - Public API

    /// Try to extract food items from a food delivery email by following order links.
    /// Returns nil if no links found or page requires authentication.
    static func extractItems(fromEmailHTML html: String, sender: String) async -> [LineItem]? {
        let urls = extractOrderURLs(from: html, sender: sender)
        guard !urls.isEmpty else { return nil }

        for url in urls {
            if let items = await fetchAndParseOrderPage(url: url) {
                return items.isEmpty ? nil : items
            }
        }

        return nil
    }

    // MARK: - URL Extraction

    /// Extract order detail URLs from email HTML.
    /// Looks for "View Order", "View Receipt", "Order Details" links.
    static func extractOrderURLs(from html: String, sender: String) -> [URL] {
        var urls: [URL] = []
        let lowerSender = sender.lowercased()

        // Patterns for href="..." extraction
        // Look for links with order-related anchor text or URL patterns
        let linkPattern = #"<a[^>]*href\s*=\s*["']([^"']+)["'][^>]*>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches {
            guard let hrefRange = Range(match.range(at: 1), in: html),
                  let textRange = Range(match.range(at: 2), in: html) else { continue }

            let href = String(html[hrefRange])
            let anchorText = String(html[textRange])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            // Check anchor text for order-related keywords
            let orderKeywords = ["view order", "view your order", "view receipt",
                                 "order details", "see order", "see your order",
                                 "view my order", "receipt details", "your receipt"]

            let isOrderLink = orderKeywords.contains { anchorText.contains($0) }

            // Also check URL patterns
            let orderURLPatterns = ["/orders/", "/receipt", "/order-details",
                                     "/order/receipt", "getreceipt", "order_id"]
            let isOrderURL = orderURLPatterns.contains { href.lowercased().contains($0) }

            if (isOrderLink || isOrderURL), let url = URL(string: href) {
                // Skip obviously non-order links
                let skip = ["unsubscribe", "privacy", "terms", "help", "support",
                           "feedback", "mailto:", "tel:", "#", "javascript:"]
                if skip.contains(where: { href.lowercased().contains($0) }) { continue }
                urls.append(url)
            }
        }

        // Also look for URLs in plain href attributes matching order patterns
        // (sometimes the anchor text is an image, not text)
        if urls.isEmpty {
            let hrefOnly = #"href\s*=\s*["']([^"']*(?:order|receipt)[^"']*)["']"#
            if let hrefRegex = try? NSRegularExpression(pattern: hrefOnly, options: .caseInsensitive) {
                let hrefMatches = hrefRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
                for match in hrefMatches {
                    if let range = Range(match.range(at: 1), in: html) {
                        let href = String(html[range])
                        let skip = ["unsubscribe", "privacy", "terms", "mailto:", "javascript:"]
                        if skip.contains(where: { href.lowercased().contains($0) }) { continue }
                        if let url = URL(string: href) {
                            urls.append(url)
                        }
                    }
                }
            }
        }

        // Deduplicate
        var seen = Set<String>()
        return urls.filter { seen.insert($0.absoluteString).inserted }
    }

    // MARK: - Fetch & Parse

    /// Fetch an order detail URL and parse food items from the response.
    private static func fetchAndParseOrderPage(url: URL) async -> [LineItem]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        // Set a browser-like user agent so the service doesn't block us
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            // If we got redirected to a login page, the token is expired/invalid
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return nil
            }

            // Check if we were redirected to a login/auth page
            if let finalURL = httpResponse.url?.absoluteString.lowercased() {
                let authIndicators = ["login", "signin", "sign-in", "auth", "accounts.google",
                                       "accounts.uber", "sso", "oauth"]
                if authIndicators.contains(where: { finalURL.contains($0) }) {
                    return nil // Redirected to login — token expired
                }
            }

            guard httpResponse.statusCode == 200,
                  let html = String(data: data, encoding: .utf8) else { return nil }

            // Check the page has actual content (not a login page)
            let lowerHTML = html.lowercased()
            if lowerHTML.contains("sign in") && lowerHTML.contains("password") {
                return nil // It's a login page
            }

            return parseOrderPageForItems(html: html)
        } catch {
            return nil
        }
    }

    /// Parse an order detail HTML page for food items.
    private static func parseOrderPageForItems(html: String) -> [LineItem] {
        var items: [LineItem] = []

        // Strategy 1: Send to LLM if available (most reliable for HTML parsing)
        // We'll do this synchronously as part of the pipeline

        // Strategy 2: Regex-based extraction from common order page patterns

        let text = stripHtmlPreservingStructure(html)

        // Look for item + price patterns
        let patterns = [
            // "1x Item Name $12.99" or "1 × Item Name ₹199"
            #"(\d+)\s*[xX×]\s+([A-Za-z][\w\s&'.,/()-]{2,50}?)\s+[\$₹£€]?\s*([\d,]+\.?\d{0,2})"#,
            // "Item Name  $12.99" (name then price, separated by whitespace)
            #"([A-Za-z][\w\s&'.,/()-]{2,50}?)\s{2,}[\$₹£€]\s*([\d,]+\.?\d{0,2})"#,
        ]

        // Try qty x name amount
        if let regex = try? NSRegularExpression(pattern: patterns[0]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let qtyRange = Range(match.range(at: 1), in: text),
                   let nameRange = Range(match.range(at: 2), in: text),
                   let amtRange = Range(match.range(at: 3), in: text) {
                    let qty = Int(String(text[qtyRange])) ?? 1
                    let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
                    let amount = Double(String(text[amtRange]).replacingOccurrences(of: ",", with: "")) ?? 0
                    if isValidItem(name) {
                        items.append(LineItem(name: name, quantity: qty, amount: amount))
                    }
                }
            }
        }

        // Try name amount (if nothing found yet)
        if items.isEmpty, let regex = try? NSRegularExpression(pattern: patterns[1]) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: text),
                   let amtRange = Range(match.range(at: 2), in: text) {
                    let name = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
                    let amount = Double(String(text[amtRange]).replacingOccurrences(of: ",", with: "")) ?? 0
                    if isValidItem(name) {
                        items.append(LineItem(name: name, quantity: 1, amount: amount))
                    }
                }
            }
        }

        // Strategy 3: Look for JSON-LD structured data (some order pages include this)
        if items.isEmpty {
            items = parseJSONLDItems(from: html)
        }

        return items
    }

    /// Parse JSON-LD structured data for order items.
    private static func parseJSONLDItems(from html: String) -> [LineItem] {
        var items: [LineItem] = []

        // Look for <script type="application/ld+json">...</script>
        let pattern = #"<script[^>]*type\s*=\s*["']application/ld\+json["'][^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let jsonStr = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            // Check for Order schema
            if let orderedItems = json["orderedItem"] as? [[String: Any]] {
                for item in orderedItems {
                    if let name = item["name"] as? String {
                        let qty = item["orderQuantity"] as? Int ?? 1
                        let price = (item["price"] as? Double) ?? 0
                        items.append(LineItem(name: name, quantity: qty, amount: price))
                    }
                }
            }

            // Check for itemListElement
            if let listElements = json["itemListElement"] as? [[String: Any]] {
                for elem in listElements {
                    if let item = elem["item"] as? [String: Any],
                       let name = item["name"] as? String {
                        items.append(LineItem(name: name, quantity: 1, amount: 0))
                    }
                }
            }
        }

        return items
    }

    // MARK: - Helpers

    private static func isValidItem(_ name: String) -> Bool {
        let lower = name.lowercased()
        let skip = ["subtotal", "total", "tax", "tip", "fee", "delivery", "service",
                     "discount", "promo", "packaging", "surge", "amount"]
        if skip.contains(where: { lower.contains($0) }) { return false }
        if SwiftEmailReceiptParser.looksLikeAddress(name) { return false }
        return name.count >= 2 && name.count <= 60
    }

    /// Strip HTML but preserve some structure for item extraction.
    private static func stripHtmlPreservingStructure(_ html: String) -> String {
        var text = html
        // Remove script/style blocks
        if let regex = try? NSRegularExpression(pattern: "<(style|script)[^>]*>.*?</\\1>", options: [.dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        // Replace block elements with newlines
        if let regex = try? NSRegularExpression(pattern: "<(?:br|/p|/div|/tr|/li|/td|/th)[^>]*>", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        }
        // Replace <td> with tab (preserves table columns)
        if let regex = try? NSRegularExpression(pattern: "<td[^>]*>", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\t")
        }
        // Remove remaining tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        // Decode entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#36;", with: "$")
        text = text.replacingOccurrences(of: "&#8377;", with: "₹")
        return text
    }
}
