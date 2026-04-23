import Foundation

/// Registry of known subscription merchants and the best way to cancel them.
///
/// For each merchant we provide (in priority order):
///   1. `appURLScheme` — deep-link into the merchant's iOS app (when installed)
///   2. `cancelURL` — direct URL to the merchant's cancel-subscription page,
///      bypassing a Google search
///   3. `supportEmail` — address for a mailto: fallback when no web cancel
///      flow exists
///
/// Match is keyword-based (case-insensitive substring) so we handle merchant
/// name variations like "NETFLIX.COM", "Netflix Premium", "Netflix India" all
/// routing to the same entry.
///
/// Fully "automatic" cancellation isn't possible on iOS — no app can invoke
/// cancellation on behalf of the user for a third-party service. The best we
/// can do is open the *exact* page / app / pre-composed email, so the user
/// completes cancellation in one or two taps.
enum SubscriptionCancelRegistry {

    struct Entry {
        /// Lower-cased keywords that identify this merchant (any-of match).
        let keywords: [String]
        /// Display name for user-facing messaging.
        let displayName: String
        /// Deep link into the merchant app (opens "app settings / subscription").
        let appURLScheme: URL?
        /// Direct web URL to the cancel / manage-subscription page.
        let cancelURL: URL?
        /// Billing / support email for mailto fallback.
        let supportEmail: String?
        /// If true, this merchant is billed through Apple's App Store and the
        /// user should be sent to iOS's Manage Subscriptions screen instead.
        let isAppStoreBilled: Bool

        init(
            keywords: [String],
            displayName: String,
            appURLScheme: String? = nil,
            cancelURL: String? = nil,
            supportEmail: String? = nil,
            isAppStoreBilled: Bool = false
        ) {
            self.keywords = keywords.map { $0.lowercased() }
            self.displayName = displayName
            self.appURLScheme = appURLScheme.flatMap { URL(string: $0) }
            self.cancelURL = cancelURL.flatMap { URL(string: $0) }
            self.supportEmail = supportEmail
            self.isAppStoreBilled = isAppStoreBilled
        }
    }

    /// Universal iOS deep link to the Manage Subscriptions screen — covers
    /// anything billed through the App Store.
    static let appStoreSubscriptionsURL = URL(string: "itms-apps://apps.apple.com/account/subscriptions")!

    /// Known merchants. Ordered by popularity so first-match wins if two
    /// entries share a keyword (shouldn't happen, but defensive).
    static let entries: [Entry] = [
        // --- Streaming video ---
        Entry(
            keywords: ["netflix"],
            displayName: "Netflix",
            appURLScheme: "nflx://",
            cancelURL: "https://www.netflix.com/cancelplan"
        ),
        Entry(
            keywords: ["spotify"],
            displayName: "Spotify",
            appURLScheme: "spotify://",
            cancelURL: "https://www.spotify.com/account/subscription/"
        ),
        Entry(
            keywords: ["disney+", "disneyplus", "disney plus", "hotstar"],
            displayName: "Disney+ / Hotstar",
            appURLScheme: "disneyplus://",
            cancelURL: "https://www.disneyplus.com/account/subscription"
        ),
        Entry(
            keywords: ["youtube premium", "youtube music", "ytmusic", "youtube"],
            displayName: "YouTube Premium",
            appURLScheme: "youtube://",
            cancelURL: "https://www.youtube.com/paid_memberships"
        ),
        Entry(
            keywords: ["hbo", "max "],  // trailing space to avoid matching "Maxima"
            displayName: "HBO Max",
            cancelURL: "https://www.max.com/account/subscription"
        ),
        Entry(
            keywords: ["hulu"],
            displayName: "Hulu",
            cancelURL: "https://www.hulu.com/account"
        ),
        Entry(
            keywords: ["prime video", "amazon prime", "amazonprime"],
            displayName: "Amazon Prime",
            cancelURL: "https://www.amazon.com/gp/primecentral"
        ),
        Entry(
            keywords: ["paramount+", "paramountplus"],
            displayName: "Paramount+",
            cancelURL: "https://www.paramountplus.com/account/"
        ),
        Entry(
            keywords: ["peacock"],
            displayName: "Peacock",
            cancelURL: "https://www.peacocktv.com/account/plans-and-payment"
        ),

        // --- Apple services (App-Store billed → iOS Subscriptions screen) ---
        Entry(
            keywords: ["apple music", "apple.com/bill", "apple one", "icloud", "itunes", "apple tv+", "appletv"],
            displayName: "Apple Services",
            isAppStoreBilled: true
        ),

        // --- Google services ---
        Entry(
            keywords: ["google one", "google storage"],
            displayName: "Google One",
            cancelURL: "https://one.google.com/storage"
        ),
        Entry(
            keywords: ["google workspace", "gsuite", "g suite"],
            displayName: "Google Workspace",
            cancelURL: "https://admin.google.com/ac/billing"
        ),

        // --- AI / Productivity ---
        Entry(
            keywords: ["claude", "anthropic"],
            displayName: "Claude (Anthropic)",
            cancelURL: "https://claude.ai/settings/billing",
            supportEmail: "support@anthropic.com"
        ),
        Entry(
            keywords: ["openai", "chatgpt", "chat.openai"],
            displayName: "ChatGPT (OpenAI)",
            cancelURL: "https://chat.openai.com/#settings/Subscription",
            supportEmail: "help@openai.com"
        ),
        Entry(
            keywords: ["notion"],
            displayName: "Notion",
            cancelURL: "https://www.notion.so/my-integrations"
        ),
        Entry(
            keywords: ["figma"],
            displayName: "Figma",
            cancelURL: "https://www.figma.com/settings/billing"
        ),
        Entry(
            keywords: ["adobe", "creative cloud"],
            displayName: "Adobe Creative Cloud",
            cancelURL: "https://account.adobe.com/plans"
        ),
        Entry(
            keywords: ["microsoft 365", "microsoft365", "office 365"],
            displayName: "Microsoft 365",
            cancelURL: "https://account.microsoft.com/services"
        ),
        Entry(
            keywords: ["dropbox"],
            displayName: "Dropbox",
            cancelURL: "https://www.dropbox.com/account/plan"
        ),
        Entry(
            keywords: ["zoom.us", "zoom "],
            displayName: "Zoom",
            cancelURL: "https://zoom.us/billing"
        ),
        Entry(
            keywords: ["linkedin premium", "linkedinpremium"],
            displayName: "LinkedIn Premium",
            cancelURL: "https://www.linkedin.com/premium/manage/"
        ),
        Entry(
            keywords: ["slack"],
            displayName: "Slack",
            cancelURL: "https://app.slack.com/billing"
        ),
        Entry(
            keywords: ["github"],
            displayName: "GitHub",
            cancelURL: "https://github.com/settings/billing"
        ),

        // --- Audio / Reading ---
        Entry(
            keywords: ["audible"],
            displayName: "Audible",
            cancelURL: "https://www.audible.com/account/membership-details"
        ),
        Entry(
            keywords: ["kindle unlimited"],
            displayName: "Kindle Unlimited",
            cancelURL: "https://www.amazon.com/cpe/yourpayments/ku"
        ),
        Entry(
            keywords: ["new york times", "nyt ", "nytimes"],
            displayName: "NYTimes",
            cancelURL: "https://myaccount.nytimes.com/seg/subscription"
        ),

        // --- Fitness / Health ---
        Entry(
            keywords: ["peloton"],
            displayName: "Peloton",
            cancelURL: "https://members.onepeloton.com/preferences/membership"
        ),
        Entry(
            keywords: ["calm "],
            displayName: "Calm",
            isAppStoreBilled: true
        ),
        Entry(
            keywords: ["headspace"],
            displayName: "Headspace",
            isAppStoreBilled: true
        ),

        // --- Indian telcos / services (user profile suggests India) ---
        Entry(
            keywords: ["jio", "reliance jio"],
            displayName: "Jio",
            cancelURL: "https://www.jio.com/selfcare/"
        ),
        Entry(
            keywords: ["airtel"],
            displayName: "Airtel",
            cancelURL: "https://www.airtel.in/myaccount/"
        ),
        Entry(
            keywords: ["vi ", "vodafone", "vodafone idea"],
            displayName: "Vi (Vodafone Idea)",
            cancelURL: "https://www.myvi.in/"
        ),
        Entry(
            keywords: ["swiggy one"],
            displayName: "Swiggy One",
            appURLScheme: "swiggy://",
            cancelURL: "https://www.swiggy.com/one"
        ),
        Entry(
            keywords: ["zomato gold", "zomato pro"],
            displayName: "Zomato Gold",
            appURLScheme: "zomato://",
            cancelURL: "https://www.zomato.com/gold"
        ),
    ]

    // MARK: - Lookup

    /// Find the first registry entry whose keywords match the merchant name.
    static func entry(for merchant: String) -> Entry? {
        let m = merchant.lowercased()
        return entries.first { entry in
            entry.keywords.contains(where: { m.contains($0) })
        }
    }
}
