import Foundation

/// Extracts restaurant name and address from food delivery receipt emails.
/// Uses regex patterns specific to each delivery service to reliably identify
/// the actual restaurant, even when the LLM fails or returns the app name.
struct FoodDeliveryParser {

    struct RestaurantInfo {
        let name: String
        let address: String?
    }

    /// Extract the actual restaurant name and address from a food delivery email body.
    /// Returns nil if no pattern matches.
    static func extractRestaurant(from html: String, sender: String) -> RestaurantInfo? {
        let lowerSender = sender.lowercased()

        // Strip HTML for text-based matching
        let text = stripHtml(html)

        if lowerSender.contains("uber") {
            return extractFromUberEats(html: html, text: text)
        } else if lowerSender.contains("doordash") {
            return extractFromDoorDash(html: html, text: text)
        } else if lowerSender.contains("grubhub") {
            return extractFromGrubHub(html: html, text: text)
        } else if lowerSender.contains("swiggy") {
            return extractFromSwiggy(html: html, text: text)
        } else if lowerSender.contains("zomato") {
            return extractFromZomato(html: html, text: text)
        } else if lowerSender.contains("deliveroo") {
            return extractFromDeliveroo(html: html, text: text)
        } else if lowerSender.contains("postmates") {
            return extractFromUberEats(html: html, text: text) // Postmates uses Uber format
        }

        // Generic fallback patterns
        return extractGeneric(html: html, text: text)
    }

    // MARK: - Uber Eats

    private static func extractFromUberEats(html: String, text: String) -> RestaurantInfo? {
        var name: String?
        var address: String?

        // Pattern 1: "Here's your receipt for Restaurant (City)."
        // Also: "Here's your receipt for Restaurant."
        let receiptPatterns = [
            #"(?:receipt|order)\s+(?:for|from)\s+(.+?)(?:\s*\([\w\s]+\))?\s*\."#,
            #"(?:receipt|order)\s+(?:for|from)\s+(.+?)(?:\s*\([\w\s,]+\))?\s*[.\n]"#,
        ]
        for pattern in receiptPatterns {
            if let match = firstMatch(pattern: pattern, in: text, options: .caseInsensitive) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) {
                    name = cleanRestaurantName(extracted)
                    break
                }
            }
        }

        // Pattern 2: "Your order from Restaurant"
        if name == nil {
            if let match = firstMatch(pattern: #"[Yy]our\s+order\s+from\s+(.+?)[\s]*[\.\n\r]"#, in: text) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) {
                    name = cleanRestaurantName(extracted)
                }
            }
        }

        // Pattern 3: Check HTML for restaurant name in specific elements
        // Uber Eats often has the restaurant name in a bold/heading element
        if name == nil {
            let htmlPatterns = [
                #"<(?:h[1-3]|strong|b)[^>]*>\s*(.+?)\s*</(?:h[1-3]|strong|b)>"#,
            ]
            for pattern in htmlPatterns {
                if let match = firstMatch(pattern: pattern, in: html, options: .caseInsensitive) {
                    let stripped = stripHtml(match).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isValidRestaurantName(stripped) && !isDeliveryAppName(stripped) {
                        name = cleanRestaurantName(stripped)
                        break
                    }
                }
            }
        }

        // Extract pickup address (= restaurant address)
        // Pattern: "Pickup\n63 Salem St, Boston, MA 02113"
        let addressPatterns = [
            #"[Pp]ickup\s*[\n\r:]+\s*(.+?,\s*\w{2}\s*\d{5}(?:-\d{4})?)"#,
            #"[Pp]ickup\s*[\n\r:]+\s*(.+?,\s*[A-Z]{2}\s*\d{5})"#,
            #"[Pp]ick-?up\s+(?:from|at)\s+(.+?,\s*\w{2}\s*\d{5})"#,
            // Uber format: "8:59 PM - Pickup\n63 Salem St, Boston, MA 02113, US"
            #"Pickup\s*\n?\s*(.+?,\s*[A-Z]{2}\s+\d{5}[^,]*)"#,
        ]
        for pattern in addressPatterns {
            if let match = firstMatch(pattern: pattern, in: text, options: []) {
                let cleaned = match.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ", US", with: "")
                    .trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
                if cleaned.count > 5 {
                    address = cleaned
                    break
                }
            }
        }

        // Also try HTML href patterns for address
        if address == nil {
            // Uber emails often have addresses as links
            if let match = firstMatch(
                pattern: #"Pickup.*?href[^>]*>([^<]+\d{5}[^<]*)<"#,
                in: html, options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) {
                let cleaned = match.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: ", US", with: "")
                if cleaned.count > 5 { address = cleaned }
            }
        }

        guard let restaurantName = name else { return nil }
        return RestaurantInfo(name: restaurantName, address: address)
    }

    // MARK: - DoorDash

    private static func extractFromDoorDash(html: String, text: String) -> RestaurantInfo? {
        // "Your DoorDash order from Restaurant is confirmed"
        // "Your order from Restaurant"
        let patterns = [
            #"order\s+from\s+(.+?)\s+(?:is|has|was)"#,
            #"order\s+from\s+(.+?)[\.\n\r]"#,
            #"delivery\s+from\s+(.+?)[\.\n\r]"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text, options: .caseInsensitive) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) {
                    return RestaurantInfo(name: cleanRestaurantName(extracted), address: nil)
                }
            }
        }
        return nil
    }

    // MARK: - GrubHub

    private static func extractFromGrubHub(html: String, text: String) -> RestaurantInfo? {
        let patterns = [
            #"order\s+from\s+(.+?)[\.\n\r!]"#,
            #"picked\s+up\s+from\s+(.+?)[\.\n\r]"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text, options: .caseInsensitive) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) {
                    return RestaurantInfo(name: cleanRestaurantName(extracted), address: nil)
                }
            }
        }
        return nil
    }

    // MARK: - Swiggy

    private static func extractFromSwiggy(html: String, text: String) -> RestaurantInfo? {
        // "Your order from Restaurant Name has been delivered"
        // "Restaurant Name | Swiggy"
        let patterns = [
            #"order\s+from\s+(.+?)\s+(?:has|is|was)"#,
            #"ordered\s+from\s+(.+?)[\.\n\r]"#,
            #"(.+?)\s*\|\s*Swiggy"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text, options: .caseInsensitive) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) && !isDeliveryAppName(extracted) {
                    return RestaurantInfo(name: cleanRestaurantName(extracted), address: nil)
                }
            }
        }
        return nil
    }

    // MARK: - Zomato

    private static func extractFromZomato(html: String, text: String) -> RestaurantInfo? {
        let patterns = [
            #"order\s+from\s+(.+?)\s+(?:has|is|was)"#,
            #"ordered\s+from\s+(.+?)[\.\n\r]"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text, options: .caseInsensitive) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) && !isDeliveryAppName(extracted) {
                    return RestaurantInfo(name: cleanRestaurantName(extracted), address: nil)
                }
            }
        }
        return nil
    }

    // MARK: - Deliveroo

    private static func extractFromDeliveroo(html: String, text: String) -> RestaurantInfo? {
        let patterns = [
            #"order\s+from\s+(.+?)[\.\n\r]"#,
            #"delivered\s+from\s+(.+?)[\.\n\r]"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text, options: .caseInsensitive) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) && !isDeliveryAppName(extracted) {
                    return RestaurantInfo(name: cleanRestaurantName(extracted), address: nil)
                }
            }
        }
        return nil
    }

    // MARK: - Generic

    private static func extractGeneric(html: String, text: String) -> RestaurantInfo? {
        // Common cross-platform patterns
        let patterns = [
            #"(?:receipt|order)\s+(?:for|from)\s+(.+?)(?:\s*\([^)]+\))?\s*[.\n]"#,
            #"ordered\s+from\s+(.+?)[\.\n\r]"#,
            #"your\s+(.+?)\s+order"#,
        ]
        for pattern in patterns {
            if let match = firstMatch(pattern: pattern, in: text, options: .caseInsensitive) {
                let extracted = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidRestaurantName(extracted) && !isDeliveryAppName(extracted) {
                    return RestaurantInfo(name: cleanRestaurantName(extracted), address: nil)
                }
            }
        }
        return nil
    }

    // MARK: - Helpers

    private static func firstMatch(pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        // Return first capture group
        guard match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }

    private static func isValidRestaurantName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 && trimmed.count <= 60 else { return false }

        // Reject strings that are obviously not restaurant names
        let lower = trimmed.lowercased()
        let rejects = ["your order", "your delivery", "thank you", "thanks for",
                       "here's your", "view receipt", "download", "total",
                       "track your", "rate your", "get help"]
        return !rejects.contains(where: { lower.hasPrefix($0) })
    }

    private static func isDeliveryAppName(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let apps = ["uber eats", "uber", "doordash", "grubhub", "swiggy", "zomato",
                     "deliveroo", "postmates", "dunzo", "blinkit"]
        return apps.contains(lower)
    }

    private static func cleanRestaurantName(_ name: String) -> String {
        var cleaned = name
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        // Remove trailing city in parens: "Ernesto's (Boston)" → "Ernesto's"
        if let regex = try? NSRegularExpression(pattern: #"\s*\([^)]+\)\s*$"#) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ""
            )
        }

        // Remove "via Uber Eats" etc.
        if let regex = try? NSRegularExpression(pattern: #"\s*(?:via|through|on)\s+(?:Uber|DoorDash|Swiggy|Zomato|GrubHub|Deliveroo).*$"#, options: .caseInsensitive) {
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ""
            )
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHtml(_ html: String) -> String {
        var text = html
        // Remove script/style
        if let regex = try? NSRegularExpression(pattern: "<(style|script)[^>]*>.*?</\\1>", options: [.dotMatchesLineSeparators]) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        // Block elements → newline
        if let regex = try? NSRegularExpression(pattern: "<(?:br|/p|/div|/tr|/li|/h[1-6])[^>]*>", options: .caseInsensitive) {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "\n")
        }
        // Remove remaining tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        }
        // Decode entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&apos;", with: "'")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        return text
    }
}
