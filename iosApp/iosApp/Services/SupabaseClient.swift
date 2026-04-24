import Foundation
import Supabase

/// Singleton wrapper around the Supabase client.
///
/// Owns the one shared `SupabaseClient` used by all remote sync services
/// (`CirclesRemoteSync`, `CoopChallengeSync`, `PushNotificationService`, etc.).
///
/// Project URL + anon key are hard-coded here for now. Long-term these should
/// move into an xcconfig or Info.plist-driven config to support dev/staging/
/// prod separation, but the anon key is safe to embed in client builds because
/// Row-Level Security policies enforce access control server-side.
enum NCBackend {

    /// Project URL for the NodeCompass Supabase project.
    /// Project ref: `zduiktztdlgsahpteicc`.
    static let projectURL = URL(string: "https://zduiktztdlgsahpteicc.supabase.co")!

    /// Anon (public) key. Safe to embed in the client — RLS policies on every
    /// table enforce row-level access rules. The service_role key is NEVER
    /// included here; it belongs on server infrastructure only.
    static let anonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" +
        ".eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpkdWlrdHp0ZGxnc2FocHRlaWNjIiwi" +
        "cm9sZSI6ImFub24iLCJpYXQiOjE3NzY5ODc3MDYsImV4cCI6MjA5MjU2MzcwNn0" +
        ".8QxyHhyI3gLefKmc0eaHsz8LDnWrTuO6eOMR8onu4vs"

    /// Lazy-initialised shared client. The first access happens when
    /// `NodeCompassApp.bootstrapSupabase()` runs on app launch, so subsequent
    /// reads never block on client setup.
    static let shared: SupabaseClient = {
        SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: anonKey
        )
    }()

    /// Kick off any one-time initialization at app launch. Currently a no-op
    /// beyond referencing `.shared` to force lazy-init, but exists as a hook
    /// for future work (e.g. restoring cached session, refreshing JWT).
    static func bootstrap() {
        _ = shared
    }
}
