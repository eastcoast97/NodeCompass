import Foundation
import Supabase

/// Remote sync for circle-scoped challenges.
///
/// Mutations use SECURITY DEFINER RPCs (`share_challenge`, `upload_my_score`,
/// `join_circle_challenge`) to cleanly bypass RLS while still deriving
/// identity from `auth.uid()` server-side. Reads go through the RLS-
/// protected tables — only members of the circle can SELECT.
///
/// Callers:
/// - `ChallengesView` (Catalog tab) calls `shareToCircle(...)` when user
///   picks a circle instead of Solo when starting a catalog challenge.
/// - `ChallengeStore.updateProgress()` calls `uploadMyScore(...)` after
///   computing local progress for circle-scoped challenges.
/// - `CircleChallengeDetailView` calls `scoresFor(challengeId:)` to render
///   the leaderboard.
@MainActor
final class CoopChallengeSync {
    static let shared = CoopChallengeSync()

    // MARK: - Models (match server schema)

    /// One row in `circle_challenges`. Mirrors the server's column names.
    struct CircleChallenge: Identifiable, Codable, Hashable {
        let id: UUID
        let circleId: UUID
        let catalogId: String?
        let title: String
        let subtitle: String?
        let pillar: String
        let challengeType: String
        let targetValue: Double
        let unit: String
        let startsAt: Date
        let endsAt: Date
        let createdBy: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case circleId       = "circle_id"
            case catalogId      = "catalog_id"
            case title
            case subtitle
            case pillar
            case challengeType  = "challenge_type"
            case targetValue    = "target_value"
            case unit
            case startsAt       = "starts_at"
            case endsAt         = "ends_at"
            case createdBy      = "created_by"
            case createdAt      = "created_at"
        }
    }

    /// One participant's score on a circle challenge.
    struct ParticipantScore: Identifiable, Codable, Hashable {
        var id: String { anonUserId }
        let challengeId: UUID
        let anonUserId: String
        let currentValue: Double
        let lastUpdated: Date
        let isCompleted: Bool
        let completedAt: Date?

        enum CodingKeys: String, CodingKey {
            case challengeId  = "challenge_id"
            case anonUserId   = "anon_user_id"
            case currentValue = "current_value"
            case lastUpdated  = "last_updated"
            case isCompleted  = "is_completed"
            case completedAt  = "completed_at"
        }
    }

    // MARK: - Errors

    enum CoopError: LocalizedError {
        case notSignedIn
        case notMember
        case supabase(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in first."
            case .notMember:   return "You're not a member of that circle."
            case .supabase(let m): return m
            }
        }
    }

    // MARK: - Share a challenge to a circle

    /// Share a challenge from the catalog to one of the user's circles.
    /// Creates the `circle_challenges` row and auto-joins the caller as the
    /// first participant.
    func shareToCircle(
        _ entry: ChallengeCatalog.Entry,
        circleId: UUID
    ) async throws -> CircleChallenge {
        _ = try await ensureSession()

        struct Args: Encodable {
            let p_circle_id: UUID
            let p_catalog_id: String
            let p_title: String
            let p_subtitle: String
            let p_pillar: String
            let p_challenge_type: String
            let p_target_value: Double
            let p_unit: String
            let p_duration_days: Int
        }
        let args = Args(
            p_circle_id: circleId,
            p_catalog_id: entry.id,
            p_title: entry.title,
            p_subtitle: entry.subtitle,
            p_pillar: entry.pillar.rawValue,
            p_challenge_type: entry.type.rawValue,
            p_target_value: entry.targetValue,
            p_unit: entry.type.unit,
            p_duration_days: entry.durationDays
        )

        do {
            let rows: [CircleChallenge] = try await NCBackend.shared
                .rpc("share_challenge", params: args)
                .execute()
                .value
            guard let challenge = rows.first else {
                throw CoopError.supabase("Server returned no challenge.")
            }
            return challenge
        } catch {
            throw mapError(error)
        }
    }

    /// Join an existing challenge in a circle you joined after it started.
    func joinChallenge(challengeId: UUID) async throws {
        _ = try await ensureSession()
        struct Args: Encodable { let p_challenge_id: UUID }
        do {
            try await NCBackend.shared
                .rpc("join_circle_challenge", params: Args(p_challenge_id: challengeId))
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Score upload

    /// Push the caller's current value for a challenge.
    /// Called periodically by `ChallengeStore.updateProgress()` for every
    /// active circle-scoped challenge. Fire-and-forget friendly — callers
    /// that don't want to surface errors can `try?` this.
    func uploadMyScore(challengeId: UUID, value: Double) async throws {
        _ = try await ensureSession()
        struct Args: Encodable {
            let p_challenge_id: UUID
            let p_value: Double
        }
        do {
            try await NCBackend.shared
                .rpc("upload_my_score",
                     params: Args(p_challenge_id: challengeId, p_value: value))
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Queries

    /// All circle challenges across all circles the user is in.
    /// Used by the Active tab to group by circle.
    func myActiveCircleChallenges() async throws -> [CircleChallenge] {
        guard AnonymousIdentity.shared.hasIdentity else { return [] }
        do { _ = try await AnonymousIdentity.shared.ensureSession() }
        catch { return [] }

        do {
            let challenges: [CircleChallenge] = try await NCBackend.shared
                .from("circle_challenges")
                .select()
                .gte("ends_at", value: Date().ISO8601Format())
                .order("created_at", ascending: false)
                .execute()
                .value
            return challenges
        } catch {
            throw mapError(error)
        }
    }

    /// All circle challenges for a specific circle. Used by `CircleDetailView`
    /// and `CircleChallengeDetailView`.
    func challenges(for circleId: UUID) async throws -> [CircleChallenge] {
        do { _ = try await AnonymousIdentity.shared.ensureSession() }
        catch { return [] }
        do {
            let challenges: [CircleChallenge] = try await NCBackend.shared
                .from("circle_challenges")
                .select()
                .eq("circle_id", value: circleId.uuidString.lowercased())
                .order("created_at", ascending: false)
                .execute()
                .value
            return challenges
        } catch {
            throw mapError(error)
        }
    }

    /// All participant scores for a single circle challenge. Feeds the
    /// leaderboard in `CircleChallengeDetailView`.
    func scores(for challengeId: UUID) async throws -> [ParticipantScore] {
        do { _ = try await AnonymousIdentity.shared.ensureSession() }
        catch { return [] }
        do {
            let scores: [ParticipantScore] = try await NCBackend.shared
                .from("participant_scores")
                .select()
                .eq("challenge_id", value: challengeId.uuidString.lowercased())
                .execute()
                .value
            return scores
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Helpers

    private func ensureSession() async throws -> String {
        do {
            return try await AnonymousIdentity.shared.ensureSession()
        } catch {
            throw CoopError.notSignedIn
        }
    }

    private func mapError(_ error: Error) -> CoopError {
        let msg = error.localizedDescription.lowercased()
        if msg.contains("not_member") || msg.contains("not a member") {
            return .notMember
        }
        return .supabase(error.localizedDescription)
    }
}
