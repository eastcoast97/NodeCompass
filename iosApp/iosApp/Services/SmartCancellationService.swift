import Foundation
import UIKit

/// Chooses the best way to help the user cancel a subscription, and opens it.
///
/// Resolution order (best → fallback):
///   1. **Native app** — if the merchant has a known iOS URL scheme and the
///      app is installed on the device, open it (deep-link into settings).
///   2. **Direct cancel page** — open the merchant's actual cancel URL in
///      Safari (no Google search, no clicking through nav menus).
///   3. **Mailto unsubscribe** — if we have the merchant's support email and
///      the user has a Gmail account connected, open Mail.app with a
///      pre-filled cancellation request addressed to the merchant, sent from
///      the user's connected email.
///   4. **Apple App Store Subscriptions** — for merchants billed through the
///      App Store, open iOS's universal Manage Subscriptions screen.
///   5. **Google search** — last resort: "how to cancel <merchant> subscription".
///
/// Returns the method that was invoked so the calling view can show a matching
/// confirmation toast / haptic.
@MainActor
enum SmartCancellationService {

    /// Which route the service ended up invoking.
    enum Route {
        case nativeApp(name: String)
        case webCancelPage(URL)
        case mailto(URL)
        case appStoreSubscriptions
        case googleSearch(URL)
    }

    /// Resolve and open the best cancellation route for a merchant.
    ///
    /// - Parameter merchant: raw merchant name from a transaction / subscription.
    /// - Returns: the route invoked (for logging / UI confirmation).
    @discardableResult
    static func cancel(merchant: String) -> Route {
        let registryEntry = SubscriptionCancelRegistry.entry(for: merchant)

        // 1. Native app (if known + installed)
        if let entry = registryEntry,
           let scheme = entry.appURLScheme,
           UIApplication.shared.canOpenURL(scheme) {
            UIApplication.shared.open(scheme)
            return .nativeApp(name: entry.displayName)
        }

        // 2. Direct web cancel URL
        if let entry = registryEntry, let url = entry.cancelURL {
            UIApplication.shared.open(url)
            return .webCancelPage(url)
        }

        // 3. App-Store-billed → iOS subscriptions screen
        if registryEntry?.isAppStoreBilled == true {
            UIApplication.shared.open(SubscriptionCancelRegistry.appStoreSubscriptionsURL)
            return .appStoreSubscriptions
        }

        // 4. Mailto fallback — compose an unsubscribe email
        if let entry = registryEntry,
           let to = entry.supportEmail,
           let mailtoURL = composeMailto(
               to: to,
               merchant: entry.displayName,
               userEmail: primaryUserEmail()
           ) {
            UIApplication.shared.open(mailtoURL)
            return .mailto(mailtoURL)
        }

        // 5. Google search — last resort (explains WHAT we're searching for)
        let searchURL = googleSearchFallback(merchant: merchant)
        UIApplication.shared.open(searchURL)
        return .googleSearch(searchURL)
    }

    /// A short human-readable label describing what the cancel button will do
    /// for a given merchant. Used to avoid surprising the user — e.g. "Open
    /// Netflix app" vs "Open cancel page" vs "Search how to cancel".
    static func actionLabel(for merchant: String) -> String {
        guard let entry = SubscriptionCancelRegistry.entry(for: merchant) else {
            return "Search how to cancel"
        }
        if let scheme = entry.appURLScheme, UIApplication.shared.canOpenURL(scheme) {
            return "Open \(entry.displayName) app"
        }
        if entry.cancelURL != nil {
            return "Open \(entry.displayName) cancel page"
        }
        if entry.isAppStoreBilled {
            return "Open App Store Subscriptions"
        }
        if entry.supportEmail != nil {
            return "Email \(entry.displayName) to cancel"
        }
        return "Search how to cancel"
    }

    // MARK: - Private helpers

    /// Build a mailto: URL with a pre-filled cancellation request body.
    private static func composeMailto(to address: String, merchant: String, userEmail: String?) -> URL? {
        let subject = "Please cancel my \(merchant) subscription"

        var body = "Hello \(merchant) team,\n\n"
        body += "Please cancel my subscription to \(merchant). "
        if let email = userEmail {
            body += "The account email is \(email). "
        }
        body += "Please also confirm the cancellation by replying to this message.\n\nThank you."

        guard let subjectEnc = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let bodyEnc = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }

        let urlString = "mailto:\(address)?subject=\(subjectEnc)&body=\(bodyEnc)"
        return URL(string: urlString)
    }

    /// Google search fallback URL for merchants not in the registry.
    private static func googleSearchFallback(merchant: String) -> URL {
        let query = "how to cancel \(merchant) subscription"
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: "https://www.google.com/search?q=\(encoded)")!
    }

    /// Best-effort primary email for the user — the first connected Gmail
    /// account, if any. Used to personalise the mailto body.
    private static func primaryUserEmail() -> String? {
        GmailService.shared.connectedEmails.first
    }
}
