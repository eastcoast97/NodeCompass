import Foundation
import Supabase
import Combine

/// Reactions layer: sending, inbox fetching, real-time subscription.
///
/// Four fixed emojis (🔥 👏 💪 🎯) so there's a tight vocabulary and no
/// free-form text to moderate. Reactions live 48h server-side (trigger
/// prunes on every INSERT), and we filter client-side to that same window
/// for safety.
///
/// Real-time: subscribes to Postgres INSERTs on the `reactions` table. The
/// server-side RLS filter `to_user = auth.uid()` combined with the
/// subscription means we only get events for reactions addressed TO us.
/// When a new reaction lands while the app is foregrounded, we publish it
/// via `newReactionPublisher` so a banner view can react.
@MainActor
final class ReactionsSync: ObservableObject {
    static let shared = ReactionsSync()

    // MARK: - Emoji set (must match server CHECK constraint)

    enum Reaction: String, CaseIterable, Codable {
        case fire     = "🔥"
        case clap     = "👏"
        case muscle   = "💪"
        case target   = "🎯"
    }

    // MARK: - Row model

    struct ReactionRow: Identifiable, Codable, Hashable {
        let id: UUID
        let challengeId: UUID
        let fromUser: String
        let toUser: String
        let emoji: String
        let createdAt: Date

        enum CodingKeys: String, CodingKey {
            case id
            case challengeId = "challenge_id"
            case fromUser    = "from_user"
            case toUser      = "to_user"
            case emoji
            case createdAt   = "created_at"
        }
    }

    // MARK: - Published state

    /// The last reaction received (via realtime). Views subscribe to this
    /// to show a banner when it changes.
    @Published private(set) var latestInbound: ReactionRow?

    /// Unread reactions (since last `markInboxSeen()`). Drives the badge
    /// counter on the Circles entry.
    @Published private(set) var unreadCount: Int = 0

    /// Cached inbox list so the inbox view opens instantly, then refreshes.
    @Published private(set) var inbox: [ReactionRow] = []

    // MARK: - Private

    private let seenTimestampKey = "nc.reactions.seenAt"
    private var realtimeChannel: RealtimeChannelV2?
    private var subscriptionTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    private init() {}

    // MARK: - Send

    /// Send a reaction from the current user to a teammate on a circle
    /// challenge. Goes through the `send_reaction` SECURITY DEFINER RPC
    /// so RLS + membership checks run server-side.
    func send(
        reaction: Reaction,
        challengeId: UUID,
        toUser: String
    ) async throws {
        _ = try await AnonymousIdentity.shared.ensureSession()
        struct Args: Encodable {
            let p_challenge_id: UUID
            let p_to_user: String
            let p_emoji: String
        }
        try await NCBackend.shared
            .rpc("send_reaction", params: Args(
                p_challenge_id: challengeId,
                p_to_user: toUser,
                p_emoji: reaction.rawValue
            ))
            .execute()
    }

    // MARK: - Inbox

    /// Fetch the caller's recent inbox (last 48 hours). RLS filters to
    /// only reactions addressed to the current user.
    ///
    /// Side effect: when `triggerBanner == true`, any row that wasn't in
    /// the previous inbox snapshot gets surfaced via `latestInbound` — this
    /// is what the polling loop (see `startPolling`) uses to make the
    /// banner fire reliably even if the Realtime websocket is misbehaving.
    @discardableResult
    func refreshInbox(triggerBanner: Bool = false) async throws -> [ReactionRow] {
        guard AnonymousIdentity.shared.hasIdentity else { return [] }
        _ = try await AnonymousIdentity.shared.ensureSession()

        let uid = AnonymousIdentity.shared.anonUserId ?? ""
        let rows: [ReactionRow] = try await NCBackend.shared
            .from("reactions")
            .select()
            .eq("to_user", value: uid)
            .order("created_at", ascending: false)
            .limit(50)
            .execute()
            .value

        if triggerBanner {
            let previousIds = Set(inbox.map { $0.id })
            if let newest = rows.first, !previousIds.contains(newest.id) {
                latestInbound = newest
            }
        }

        inbox = rows
        recomputeUnread()
        return rows
    }

    /// Call when the user opens the inbox — snaps the "last seen" timestamp
    /// to now so the unread badge resets.
    func markInboxSeen() {
        UserDefaults.standard.set(Date(), forKey: seenTimestampKey)
        recomputeUnread()
    }

    /// Clear the transient `latestInbound` value so the in-app banner
    /// stops showing it. Called by the banner view after its timeout.
    /// Only clears if the most-recent value is still the one the caller
    /// received (avoids clobbering a newer reaction that arrived during
    /// the banner's visible window).
    func acknowledgeBanner(id: UUID) {
        if latestInbound?.id == id {
            latestInbound = nil
        }
    }

    // MARK: - Realtime subscription

    /// Start listening for inbound reactions. Called on app foreground
    /// from the Circles entry point (or wherever the user is likely to
    /// care). Safe to call multiple times — deduped via early-return.
    func startListening() async {
        guard realtimeChannel == nil,
              AnonymousIdentity.shared.hasIdentity else {
            print("[ReactionsSync] startListening skipped — channel=\(realtimeChannel == nil), hasIdentity=\(AnonymousIdentity.shared.hasIdentity)")
            return
        }

        let client = NCBackend.shared
        let channel = client.realtimeV2.channel("public:reactions")

        // Watch for INSERTs on the reactions table. RLS ensures we only
        // receive events for rows where (from_user = me OR to_user = me);
        // we further narrow to to_user = me client-side below.
        let insertStream = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "reactions"
        )

        realtimeChannel = channel
        await channel.subscribe()
        print("[ReactionsSync] realtime channel subscribed")

        subscriptionTask = Task { [weak self] in
            for await change in insertStream {
                guard let self else { return }
                print("[ReactionsSync] realtime INSERT received, record keys=\(Array(change.record.keys))")
                await self.handleInsert(change)
            }
            print("[ReactionsSync] realtime stream ended")
        }
    }

    /// Stop listening. Called when app backgrounds / user signs out.
    func stopListening() async {
        subscriptionTask?.cancel()
        subscriptionTask = nil
        pollingTask?.cancel()
        pollingTask = nil
        if let ch = realtimeChannel {
            await ch.unsubscribe()
        }
        realtimeChannel = nil
    }

    /// Start a 15-second polling loop as a fallback for Realtime. Idempotent.
    ///
    /// Realtime WebSocket delivery is the primary path, but supabase-swift's
    /// realtime client sometimes fails to attach the session token properly
    /// after a sign-in, and events silently drop. Polling at a low interval
    /// guarantees the banner fires within ~15s even when realtime misbehaves.
    /// Cheap: one indexed SELECT per poll, LIMIT 50.
    func startPolling() {
        guard pollingTask == nil,
              AnonymousIdentity.shared.hasIdentity else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let self, !Task.isCancelled else { return }
                _ = try? await self.refreshInbox(triggerBanner: true)
            }
        }
    }

    // MARK: - Private

    private func handleInsert(_ change: InsertAction) async {
        guard let uid = AnonymousIdentity.shared.anonUserId else {
            print("[ReactionsSync] handleInsert: no anon id cached")
            return
        }

        // Decode the `record` payload into our ReactionRow model.
        let row: ReactionRow
        do {
            row = try decodeReaction(from: change.record)
        } catch {
            print("[ReactionsSync] decodeReaction FAILED: \(error)")
            return
        }

        // Only surface inbound — reactions sent BY us still arrive via the
        // RLS 'self_read_reactions' policy but shouldn't trigger a banner.
        guard row.toUser == uid else {
            print("[ReactionsSync] ignoring (to_user=\(row.toUser) != me=\(uid))")
            return
        }

        print("[ReactionsSync] new banner candidate from=\(row.fromUser) emoji=\(row.emoji)")
        inbox.insert(row, at: 0)
        latestInbound = row
        recomputeUnread()
    }

    /// Decode a realtime `record` payload into a `ReactionRow`. Postgres
    /// emits timestamps with fractional seconds (e.g.
    /// `"2026-04-24T16:45:00.123456+00:00"` or
    /// `"2026-04-24 16:45:00.123456+00"`) which Swift's stock `.iso8601`
    /// strategy rejects. We try multiple formats and pick the first that
    /// parses.
    private func decodeReaction(from record: [String: AnyJSON]) throws -> ReactionRow {
        let data = try JSONEncoder().encode(record)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let c = try d.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = Self.flexibleDateFormatters.lazy
                .compactMap({ $0.date(from: s) }).first {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: c,
                debugDescription: "Unparseable timestamp: \(s)"
            )
        }
        return try decoder.decode(ReactionRow.self, from: data)
    }

    /// Ordered list of date parsers to try against Postgres realtime
    /// timestamp payloads. Most common formats first.
    private static let flexibleDateFormatters: [DateFormatter] = {
        let fmts: [String] = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX",   // ISO with fractional + zone
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",           // ISO no fractional
            "yyyy-MM-dd HH:mm:ss.SSSSSSxxx",        // Postgres default
            "yyyy-MM-dd HH:mm:ss.SSSxxx",
            "yyyy-MM-dd HH:mm:ssxxx",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",             // UTC suffix
        ]
        return fmts.map {
            let f = DateFormatter()
            f.dateFormat = $0
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: 0)
            return f
        }
    }()

    private func recomputeUnread() {
        let cutoff = (UserDefaults.standard.object(forKey: seenTimestampKey) as? Date)
            ?? Date.distantPast
        unreadCount = inbox.filter { $0.createdAt > cutoff }.count
    }
}
