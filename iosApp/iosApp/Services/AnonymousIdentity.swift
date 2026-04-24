import Foundation
import AuthenticationServices
import Supabase

/// Derives and persists a stable anonymous user ID from Sign in with Apple.
///
/// **Privacy contract:**
/// - We never persist Apple's email, full name, or raw opaque identifier.
/// - We SHA-256 hash Apple's opaque `user` string once, the first time the
///   user signs in. The hash is what Supabase sees as the user's identity
///   (via `auth.uid()`).
/// - Apple's opaque identifier is already privacy-preserving (it's unique to
///   our app's App ID, not the user's Apple account globally), but hashing
///   adds one more layer of defence-in-depth.
///
/// **Auth flow:**
/// 1. User triggers "Sign in with Apple" (from `IdentityPromptSheet`).
/// 2. `ASAuthorizationAppleIDProvider` returns an identity token (JWT) +
///    opaque `user` string.
/// 3. We forward the identity token to Supabase via
///    `client.auth.signInWithIdToken(credentials:)` — Supabase validates the
///    token against Apple's public keys, creates/fetches an `auth.users` row,
///    and returns a Supabase session.
/// 4. We compute our anon_user_id = SHA-256(Apple's user) and persist it in
///    Keychain. This becomes the primary key we use across our own tables.
@MainActor
final class AnonymousIdentity: NSObject, ObservableObject {
    static let shared = AnonymousIdentity()

    private let keychainKey = "nc.anon_user_id"

    /// True if the user has completed Sign in with Apple at least once and
    /// we have a persisted anon ID available.
    @Published private(set) var hasIdentity: Bool = false

    /// Cached anon ID. Loaded from Keychain on init, populated after sign-in.
    @Published private(set) var anonUserId: String?

    /// Completion handler used to bridge ASAuthorization's delegate callback
    /// into an async/await call site.
    private var pendingContinuation: CheckedContinuation<String, Error>?

    private override init() {
        super.init()
        // Load the anon ID from Keychain if it exists from a previous session.
        //
        // Validate shape: current format is Supabase's auth.users.id UUID
        // (36 chars, 4 hyphens). Older builds saved SHA-256 hex hashes of
        // Apple's opaque identifier (64 chars, no hyphens) — those no longer
        // match Supabase RLS policies, so wipe them to force a fresh
        // sign-in sequence on next attempt.
        if let cached = KeychainService.shared.get(key: keychainKey) {
            if UUID(uuidString: cached) != nil {
                self.anonUserId = cached
                self.hasIdentity = true
            } else {
                KeychainService.shared.delete(key: keychainKey)
            }
        }
    }

    // MARK: - Public API

    /// Kick off the Sign in with Apple flow. Resolves with the stable anon ID
    /// once the user completes authentication and Supabase accepts the token.
    ///
    /// Always runs the full Apple + Supabase handshake — we intentionally do
    /// NOT short-circuit on cached `anonUserId` because the cache can outlive
    /// a Supabase session (e.g. session expired, app reinstalled with the
    /// Keychain entry surviving, early broken attempts persisted a stale ID).
    /// Apple's own system sheet is instant when you're already signed in so
    /// there's near-zero UX cost to re-running this.
    ///
    /// Throws `AnonymousIdentityError.cancelled` if the user dismisses the
    /// system auth sheet, or `.supabaseRejected(reason:)` if token exchange
    /// fails.
    func signIn() async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuation = continuation

            let provider = ASAuthorizationAppleIDProvider()
            let request = provider.createRequest()
            request.requestedScopes = []  // we don't want email or name

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    /// Clear the cached identity (used when the user signs out / clears data).
    func reset() {
        KeychainService.shared.delete(key: keychainKey)
        anonUserId = nil
        hasIdentity = false
    }

    // MARK: - Internal

    /// Handle a successful Apple credential — exchange the identity token
    /// with Supabase, persist the Supabase-issued user UUID as our anon ID.
    ///
    /// Why use Supabase's user.id instead of hashing Apple's opaque user
    /// string: Supabase's RLS policies check `auth.uid()` against our table's
    /// `anon_user_id` column. Supabase's `auth.uid()` is a UUID it generates
    /// per auth.users row — NOT Apple's raw sub claim. If we store a hash of
    /// Apple's ID, the RLS policy `auth.uid()::text = anon_user_id` always
    /// fails and every INSERT gets silently rejected. Using Supabase's
    /// UUID aligns our tables with how Postgres enforces access.
    ///
    /// The UUID is still privacy-preserving — Supabase generates it randomly
    /// per user, doesn't leak Apple's identity, and only circle members ever
    /// see your (per-circle) display name + emoji avatar, never the UUID.
    private func completeSignIn(credential: ASAuthorizationAppleIDCredential) async {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            fail(with: .missingToken)
            return
        }

        let anonId: String
        do {
            // Sign in to Supabase using Apple's identity token.
            // Supabase validates the JWT against Apple's JWKS, then issues
            // us a Supabase session (access token + refresh token).
            let session = try await NCBackend.shared.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: identityToken)
            )
            anonId = session.user.id.uuidString.lowercased()
        } catch {
            fail(with: .supabaseRejected(reason: error.localizedDescription))
            return
        }

        // Persist and publish.
        _ = KeychainService.shared.save(key: keychainKey, value: anonId)
        self.anonUserId = anonId
        self.hasIdentity = true

        pendingContinuation?.resume(returning: anonId)
        pendingContinuation = nil
    }

    private func fail(with error: AnonymousIdentityError) {
        pendingContinuation?.resume(throwing: error)
        pendingContinuation = nil
    }
}

// MARK: - Error

enum AnonymousIdentityError: LocalizedError {
    case cancelled
    case missingToken
    case supabaseRejected(reason: String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sign-in was cancelled."
        case .missingToken:
            return "Apple didn't return an identity token."
        case .supabaseRejected(let reason):
            return "Server rejected sign-in: \(reason)"
        }
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AnonymousIdentity: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            fail(with: .missingToken)
            return
        }
        Task { await completeSignIn(credential: credential) }
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let nsError = error as NSError
        if nsError.code == ASAuthorizationError.canceled.rawValue {
            fail(with: .cancelled)
        } else {
            fail(with: .supabaseRejected(reason: error.localizedDescription))
        }
    }
}

// MARK: - Presentation context

extension AnonymousIdentity: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Grab the key window from the active scene (iOS 15+).
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            ?? ASPresentationAnchor()
    }
}
