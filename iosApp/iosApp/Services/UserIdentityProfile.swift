import Foundation
import Supabase

/// Local cache + Supabase sync for the user's display name + avatar emoji.
///
/// These are the only two user-visible pieces of identity in NodeCompass —
/// no real name, no email, no photo. They're what circle members see next to
/// your progress rings.
///
/// **Storage layout:**
/// - Local: `UserDefaults` (so writes don't block on network)
/// - Remote: `profiles` table in Supabase, keyed by `anon_user_id`
///
/// Local is the source of truth for reads. Remote is written to on every
/// change + on first-time upsert right after the user sets their initial
/// values from the `IdentityPromptSheet`.
@MainActor
final class UserIdentityProfile: ObservableObject {
    static let shared = UserIdentityProfile()

    private let displayNameKey = "nc.profile.displayName"
    private let avatarEmojiKey = "nc.profile.avatarEmoji"

    /// User-chosen display name. Empty string before first setup.
    @Published private(set) var displayName: String
    /// Single-emoji avatar. Default is a random animal from the seed set.
    @Published private(set) var avatarEmoji: String

    /// Curated seed list for the emoji picker UI. Keeping it small so the
    /// picker fits on one row of a sheet.
    static let avatarChoices: [String] = [
        "🦊", "🐼", "🐯", "🦁", "🐻", "🐨",
        "🐸", "🐙", "🦉", "🦦", "🐢", "🦄",
        "🌱", "🔥", "⚡️", "🌊", "🌙", "⭐️",
    ]

    private init() {
        let defaults = UserDefaults.standard
        self.displayName = defaults.string(forKey: displayNameKey) ?? ""
        self.avatarEmoji = defaults.string(forKey: avatarEmojiKey)
            ?? Self.avatarChoices.randomElement() ?? "🦊"
    }

    /// True once the user has picked both a display name and an avatar.
    /// `IdentityPromptSheet` uses this to decide whether to show the prompt.
    var isConfigured: Bool { !displayName.isEmpty }

    // MARK: - Updates

    /// Set the user's profile values locally + push them to Supabase.
    /// Returns `nil` on success, or a user-facing error string on failure —
    /// the local cache is always written even when the remote write fails,
    /// so the retry in `syncIfNeeded()` has a chance to pick it up later.
    @discardableResult
    func set(displayName: String, avatarEmoji: String) async -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else {
            return "Display name must be 1-40 characters."
        }
        guard avatarEmoji.count <= 8 else {
            return "Avatar emoji invalid."
        }

        self.displayName = trimmed
        self.avatarEmoji = avatarEmoji

        let defaults = UserDefaults.standard
        defaults.set(trimmed, forKey: displayNameKey)
        defaults.set(avatarEmoji, forKey: avatarEmojiKey)

        do {
            try await pushToSupabase()
            return nil
        } catch {
            return "Couldn't save to server: \(error.localizedDescription)"
        }
    }

    /// If we have an anon identity but the remote profile row is missing
    /// (e.g. first launch after Supabase project reset), re-push. Called on
    /// app launch from `NodeCompassApp.bootstrapSupabase()`.
    func syncIfNeeded() async {
        guard AnonymousIdentity.shared.hasIdentity, isConfigured else { return }
        try? await pushToSupabase()
    }

    // MARK: - Remote

    private struct ProfileRow: Encodable {
        let anon_user_id: String
        let display_name: String
        let avatar_emoji: String
    }

    enum ProfileSyncError: LocalizedError {
        case noAnonymousIdentity
        var errorDescription: String? {
            switch self {
            case .noAnonymousIdentity:
                return "Not signed in."
            }
        }
    }

    /// Upsert the local profile row to Supabase. Throws on failure so the
    /// caller can surface a user-visible error (network issue, RLS reject,
    /// etc).
    private func pushToSupabase() async throws {
        guard let anonId = AnonymousIdentity.shared.anonUserId else {
            throw ProfileSyncError.noAnonymousIdentity
        }

        let row = ProfileRow(
            anon_user_id: anonId,
            display_name: displayName,
            avatar_emoji: avatarEmoji
        )

        // UPSERT on the profiles table. `onConflict: "anon_user_id"` ensures
        // repeat writes update the existing row instead of failing the PK
        // constraint.
        try await NCBackend.shared
            .from("profiles")
            .upsert(row, onConflict: "anon_user_id")
            .execute()
    }
}
