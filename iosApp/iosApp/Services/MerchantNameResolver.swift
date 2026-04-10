import Foundation

/// Resolves messy merchant text from SMS into clean, recognizable brand names.
///
/// Examples:
///   "AMAZON PAY INDIA PRI"  → "Amazon"
///   "netflix.com"           → "Netflix"
///   "SWIGGY ORDER 12345"    → "Swiggy"
///   "UBER BV TRIP"          → "Uber"
///   "paytm@upi"             → "Paytm"
struct MerchantNameResolver {

    /// Resolve a raw merchant string into a clean display name.
    static func resolve(_ raw: String) -> String {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Try matching against known merchants
        for (keywords, displayName) in knownMerchants {
            for keyword in keywords {
                if lower.contains(keyword) {
                    return displayName
                }
            }
        }

        // 2. Handle UPI VPA patterns: "merchant@bank" → "Merchant"
        if lower.contains("@") {
            let parts = lower.split(separator: "@")
            if let name = parts.first {
                let cleaned = String(name)
                    .replacingOccurrences(of: #"\d+"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                if !cleaned.isEmpty {
                    // Check if the VPA name matches a known merchant
                    for (keywords, displayName) in knownMerchants {
                        for keyword in keywords {
                            if cleaned.contains(keyword) { return displayName }
                        }
                    }
                    return cleaned.capitalized
                }
            }
        }

        // 3. Clean up generic text
        var cleaned = raw

        // Remove common noise words
        let noisePatterns = [
            #"(?i)\s*(pvt|ltd|private|limited|inc|corp|llp|llc|india|int'?l|international)\s*\.?"#,
            #"(?i)\s*(pri|pay|payment|payments|services|service|tech|technologies)\s*$"#,
            #"(?i)^(pos|ecom|online|www\.)\s*"#,
            #"(?i)\s*(order|txn|ref|id|no)\s*[:#]?\s*\w*$"#,
            #"\s*\d{4,}.*$"#,  // trailing numbers (order IDs, refs)
            #"\s+[A-Z]{2,3}\s*$"#,  // trailing city/state codes
        ]
        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                cleaned = regex.stringByReplacingMatches(
                    in: cleaned,
                    range: NSRange(cleaned.startIndex..., in: cleaned),
                    withTemplate: ""
                )
            }
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        // 4. Smart capitalization
        if cleaned.isEmpty { return "Unknown" }

        // If all uppercase (like "STARBUCKS"), convert to title case
        if cleaned == cleaned.uppercased() && cleaned.count > 2 {
            cleaned = cleaned.capitalized
        }

        // If still reasonable, return it
        if cleaned.count <= 25 {
            return cleaned
        }

        // Truncate long names gracefully at word boundary
        let words = cleaned.split(separator: " ").prefix(3)
        return words.joined(separator: " ")
    }

    // MARK: - Known Merchant Database

    /// (keywords to match, clean display name)
    private static let knownMerchants: [([String], String)] = [
        // Food & Dining
        (["swiggy"], "Swiggy"),
        (["zomato"], "Zomato"),
        (["uber eats", "ubereats"], "Uber Eats"),
        (["doordash"], "DoorDash"),
        (["grubhub"], "Grubhub"),
        (["deliveroo"], "Deliveroo"),
        (["starbucks"], "Starbucks"),
        (["mcdonald"], "McDonald's"),
        (["domino"], "Domino's"),
        (["pizza hut"], "Pizza Hut"),
        (["kfc"], "KFC"),
        (["subway"], "Subway"),
        (["dunkin"], "Dunkin'"),
        (["burger king"], "Burger King"),
        (["chipotle"], "Chipotle"),
        (["taco bell"], "Taco Bell"),
        (["chick-fil-a", "chickfila"], "Chick-fil-A"),
        (["panda express"], "Panda Express"),

        // Groceries
        (["bigbasket", "big basket"], "BigBasket"),
        (["blinkit"], "Blinkit"),
        (["zepto"], "Zepto"),
        (["jiomart"], "JioMart"),
        (["dmart", "d-mart"], "DMart"),
        (["whole foods"], "Whole Foods"),
        (["trader joe"], "Trader Joe's"),
        (["kroger"], "Kroger"),
        (["instacart"], "Instacart"),
        (["costco"], "Costco"),
        (["aldi"], "Aldi"),

        // Shopping
        (["amazon"], "Amazon"),
        (["flipkart"], "Flipkart"),
        (["myntra"], "Myntra"),
        (["ajio"], "AJIO"),
        (["meesho"], "Meesho"),
        (["walmart"], "Walmart"),
        (["target"], "Target"),
        (["ebay"], "eBay"),
        (["etsy"], "Etsy"),
        (["ikea"], "IKEA"),
        (["best buy"], "Best Buy"),
        (["apple store", "apple.com"], "Apple"),
        (["nike"], "Nike"),
        (["adidas"], "Adidas"),
        (["zara"], "Zara"),
        (["h&m", "h and m"], "H&M"),
        (["nykaa"], "Nykaa"),
        (["croma"], "Croma"),

        // Transport
        (["uber"], "Uber"),  // Must come after "Uber Eats" check
        (["ola"], "Ola"),
        (["rapido"], "Rapido"),
        (["lyft"], "Lyft"),
        (["bolt"], "Bolt"),
        (["grab"], "Grab"),

        // Subscriptions & Digital
        (["netflix"], "Netflix"),
        (["spotify"], "Spotify"),
        (["disney"], "Disney+"),
        (["hotstar"], "Hotstar"),
        (["youtube", "google youtube"], "YouTube Premium"),
        (["apple music"], "Apple Music"),
        (["amazon prime", "primevideo"], "Amazon Prime"),
        (["hbo"], "HBO Max"),
        (["hulu"], "Hulu"),
        (["audible"], "Audible"),
        (["notion"], "Notion"),
        (["figma"], "Figma"),
        (["adobe"], "Adobe"),
        (["chatgpt", "openai"], "ChatGPT"),
        (["claude", "anthropic"], "Claude"),
        (["microsoft", "msft"], "Microsoft"),
        (["google one", "google storage"], "Google One"),
        (["icloud"], "iCloud"),
        (["dropbox"], "Dropbox"),

        // Bills & Telecom
        (["jio"], "Jio"),
        (["airtel"], "Airtel"),
        (["vodafone", "vi "], "Vi"),
        (["bsnl"], "BSNL"),
        (["act fibernet", "actcorp"], "ACT Fibernet"),
        (["t-mobile", "tmobile"], "T-Mobile"),
        (["verizon"], "Verizon"),
        (["at&t"], "AT&T"),
        (["comcast", "xfinity"], "Xfinity"),

        // Payments & Wallets
        (["paytm"], "Paytm"),
        (["phonepe", "phone pe"], "PhonePe"),
        (["googlepay", "google pay", "gpay"], "Google Pay"),
        (["cred"], "CRED"),
        (["razorpay"], "Razorpay"),
        (["paypal"], "PayPal"),
        (["venmo"], "Venmo"),
        (["cashapp", "cash app"], "Cash App"),

        // Health & Fitness
        (["practo"], "Practo"),
        (["pharmeasy"], "PharmEasy"),
        (["1mg", "onemg"], "1mg"),
        (["cult.fit", "cultfit", "cure.fit"], "Cult.fit"),
        (["apollo"], "Apollo Pharmacy"),

        // Education
        (["udemy"], "Udemy"),
        (["coursera"], "Coursera"),
        (["unacademy"], "Unacademy"),
        (["byju"], "BYJU'S"),

        // Rent & Housing
        (["rentcafe", "rent cafe"], "RentCafe"),
        (["apartments.com"], "Apartments.com"),
        (["zillow"], "Zillow"),
        (["nobroker"], "NoBroker"),

        // Entertainment
        (["bookmyshow"], "BookMyShow"),
        (["pvr", "inox"], "PVR INOX"),
        (["steam"], "Steam"),
    ]
}
