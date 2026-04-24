import Foundation
import Supabase

/// Remote sync for circles: create, join-via-code, leave, list, members.
///
/// All reads go through Supabase's RLS — we rely on the server-side policies
/// created in M2.1 to enforce "only members of a circle can see it." That
/// means clients can issue plain SELECT queries; unauthorized rows are
/// silently filtered out by Postgres.
@MainActor
final class CirclesRemoteSync: ObservableObject {
    static let shared = CirclesRemoteSync()

    // MARK: - Models (match Postgres schema)

    struct Circle: Identifiable, Codable, Hashable {
        let id: UUID
        let name: String
        let inviteCode: String
        let createdBy: String
        let createdAt: Date
        let memberCount: Int

        enum CodingKeys: String, CodingKey {
            case id, name
            case inviteCode  = "invite_code"
            case createdBy   = "created_by"
            case createdAt   = "created_at"
            case memberCount = "member_count"
        }
    }

    /// Row from the `circle_members` table joined with the member's profile
    /// fields. Renders the members-list UI.
    struct CircleMember: Identifiable, Codable, Hashable {
        var id: String { anonUserId }
        let anonUserId: String
        let joinedAt: Date
        let displayName: String
        let avatarEmoji: String

        enum CodingKeys: String, CodingKey {
            case anonUserId   = "anon_user_id"
            case joinedAt     = "joined_at"
            case displayName  = "display_name"
            case avatarEmoji  = "avatar_emoji"
        }
    }

    /// Error cases that map to clear UI messages.
    enum CirclesError: LocalizedError {
        case notSignedIn
        case codeNotFound
        case circleFull
        case userAtCap
        case supabase(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn:  return "Sign in before creating or joining a circle."
            case .codeNotFound: return "No circle matches that invite code."
            case .circleFull:   return "That circle is full (8 members max)."
            case .userAtCap:    return "You're already in 5 circles (the max)."
            case .supabase(let msg): return msg
            }
        }
    }

    // MARK: - Create

    /// Create a new circle via the `create_circle` RPC (SECURITY DEFINER).
    ///
    /// Why an RPC and not a direct INSERT: a direct `FROM circles INSERT`
    /// goes through RLS, and the trigger chain on `circles` (creator-member
    /// insert + member_count maintenance) ends up doing UPDATEs and INSERTs
    /// that hit RLS policies and fail opaquely ("new row violates RLS for
    /// table circles"). The SECURITY DEFINER RPC bypasses RLS entirely —
    /// it still reads `auth.uid()` internally, so only an authenticated
    /// caller can create a circle, and the created_by is set from the JWT,
    /// never from client input.
    func createCircle(name: String) async throws -> Circle {
        do {
            _ = try await AnonymousIdentity.shared.ensureSession()
        } catch {
            throw CirclesError.notSignedIn
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 50 else {
            throw CirclesError.supabase("Circle name must be 1-50 characters.")
        }

        struct CreateArgs: Encodable { let p_name: String }
        do {
            let rows: [Circle] = try await NCBackend.shared
                .rpc("create_circle", params: CreateArgs(p_name: trimmed))
                .execute()
                .value
            guard let circle = rows.first else {
                throw CirclesError.supabase("Server returned no circle.")
            }
            return circle
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Join

    /// Join an existing circle by its 6-character invite code via the
    /// `join_circle` RPC (SECURITY DEFINER). Same rationale as
    /// `createCircle` — avoids the RLS / trigger cascade issues.
    @discardableResult
    func joinWithCode(_ code: String) async throws -> Circle {
        do {
            _ = try await AnonymousIdentity.shared.ensureSession()
        } catch {
            throw CirclesError.notSignedIn
        }
        let normalized = code
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard normalized.count == 6 else {
            throw CirclesError.supabase("Invite codes are 6 characters.")
        }

        struct JoinArgs: Encodable { let p_code: String }
        do {
            let rows: [Circle] = try await NCBackend.shared
                .rpc("join_circle", params: JoinArgs(p_code: normalized))
                .execute()
                .value
            guard let circle = rows.first else {
                throw CirclesError.codeNotFound
            }
            return circle
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Leave

    /// Leave a circle via the `leave_circle` RPC (SECURITY DEFINER).
    func leaveCircle(circleId: UUID) async throws {
        do {
            _ = try await AnonymousIdentity.shared.ensureSession()
        } catch {
            throw CirclesError.notSignedIn
        }
        struct LeaveArgs: Encodable { let p_circle_id: UUID }
        do {
            try await NCBackend.shared
                .rpc("leave_circle", params: LeaveArgs(p_circle_id: circleId))
                .execute()
        } catch {
            throw mapError(error)
        }
    }

    // MARK: - Queries

    /// All circles the current user is a member of.
    func myCircles() async throws -> [Circle] {
        // Only attempt if identity is set up. SELECTs still need a live
        // session for RLS to match `auth.uid()`.
        guard AnonymousIdentity.shared.hasIdentity else { return [] }
        do { _ = try await AnonymousIdentity.shared.ensureSession() }
        catch { return [] }

        do {
            let circles: [Circle] = try await NCBackend.shared
                .from("circles")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            return circles
        } catch {
            throw mapError(error)
        }
    }

    /// Members of a circle, joined with profile data. Two queries issued in
    /// parallel: one for `circle_members`, one for matching `profiles`.
    func membersOf(circleId: UUID) async throws -> [CircleMember] {
        guard AnonymousIdentity.shared.hasIdentity else { return [] }
        do { _ = try await AnonymousIdentity.shared.ensureSession() }
        catch { return [] }

        // circle_members rows
        struct MemberRow: Decodable {
            let anon_user_id: String
            let joined_at: Date
        }
        let memberRows: [MemberRow]
        do {
            memberRows = try await NCBackend.shared
                .from("circle_members")
                .select("anon_user_id, joined_at")
                .eq("circle_id", value: circleId.uuidString.lowercased())
                .execute()
                .value
        } catch {
            throw mapError(error)
        }

        guard !memberRows.isEmpty else { return [] }

        // profiles rows for those user IDs
        struct ProfileRow: Decodable {
            let anon_user_id: String
            let display_name: String
            let avatar_emoji: String
        }
        let ids = memberRows.map { $0.anon_user_id }
        let profileRows: [ProfileRow]
        do {
            profileRows = try await NCBackend.shared
                .from("profiles")
                .select("anon_user_id, display_name, avatar_emoji")
                .in("anon_user_id", values: ids)
                .execute()
                .value
        } catch {
            throw mapError(error)
        }

        let profileByUserId = Dictionary(uniqueKeysWithValues:
            profileRows.map { ($0.anon_user_id, $0) })

        return memberRows.compactMap { m in
            guard let p = profileByUserId[m.anon_user_id] else { return nil }
            return CircleMember(
                anonUserId: m.anon_user_id,
                joinedAt: m.joined_at,
                displayName: p.display_name,
                avatarEmoji: p.avatar_emoji
            )
        }
    }

    // MARK: - Diagnostics

    struct WhoAmI: Decodable, Hashable {
        let uid: String
        let role: String
    }

    /// Call the server-side `whoami()` function to inspect what the server
    /// currently believes about the caller (auth.uid + auth.role). If
    /// `uid` comes back as `"<null>"`, the JWT isn't being attached and
    /// all RLS policies will reject as if the caller were anonymous.
    func whoami() async throws -> WhoAmI {
        let rows: [WhoAmI] = try await NCBackend.shared
            .rpc("whoami")
            .execute()
            .value
        return rows.first ?? WhoAmI(uid: "<no-row>", role: "<no-row>")
    }

    // MARK: - Error mapping

    /// Translate raw Supabase / Postgres errors into our typed `CirclesError`
    /// so views can show friendly messages.
    private func mapError(_ error: Error) -> CirclesError {
        let msg = error.localizedDescription
        let lower = msg.lowercased()
        if lower.contains("circle is full") || lower.contains("circle_full") {
            return .circleFull
        }
        if lower.contains("already in 5 circles") || lower.contains("user_cap") {
            return .userAtCap
        }
        return .supabase(msg)
    }
}
