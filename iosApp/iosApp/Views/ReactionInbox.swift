import SwiftUI

/// List of reactions the current user has received in the last 48 hours.
/// Grouped by day ("Today", "Yesterday", or the date).
struct ReactionInbox: View {
    @StateObject private var vm = ReactionInboxViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.rows.isEmpty {
                    ProgressView().tint(NC.teal)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.rows.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(vm.groupedKeys, id: \.self) { day in
                                groupSection(day: day, items: vm.grouped[day] ?? [])
                            }
                        }
                        .padding(.horizontal, NC.hPad)
                        .padding(.top, 8)
                        .padding(.bottom, 30)
                    }
                }
            }
            .background(NC.bgBase)
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.load()
                // Snap the last-seen timestamp so the badge zeroes out.
                ReactionsSync.shared.markInboxSeen()
            }
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Subviews

    private func groupSection(day: String, items: [ReactionInboxViewModel.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day)
                .font(.caption.bold())
                .foregroundStyle(NC.textTertiary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 8) {
                ForEach(items) { row in
                    inboxCard(row)
                }
            }
        }
    }

    private func inboxCard(_ row: ReactionInboxViewModel.Row) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Text(row.senderAvatar).font(.system(size: 30))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                    .background(NC.bgElevated,
                                in: RoundedRectangle(cornerRadius: NC.iconRadius))
                Text(row.emoji)
                    .font(.system(size: 18))
                    .offset(x: 6, y: 6)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(row.senderName)
                    .font(.subheadline.bold())
                    .foregroundStyle(NC.textPrimary)
                Text("\(row.emoji) on your \(row.challengeTitle)")
                    .font(.caption)
                    .foregroundStyle(NC.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(row.timeLabel)
                .font(.caption2)
                .foregroundStyle(NC.textTertiary)
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(NC.insight.opacity(0.4))
            Text("No reactions yet")
                .font(.headline)
                .foregroundStyle(NC.textPrimary)
            Text("When teammates hit a milestone, tap their row to send 🔥 👏 💪 🎯. Theirs will show up here.")
                .font(.caption)
                .foregroundStyle(NC.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - View Model

@MainActor
final class ReactionInboxViewModel: ObservableObject {
    struct Row: Identifiable, Hashable {
        let id: UUID
        let senderName: String
        let senderAvatar: String
        let emoji: String
        let challengeTitle: String
        let createdAt: Date
        let timeLabel: String
    }

    @Published var rows: [Row] = []
    @Published var isLoading = false
    @Published var grouped: [String: [Row]] = [:]
    @Published var groupedKeys: [String] = []

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let reactions = (try? await ReactionsSync.shared.refreshInbox()) ?? []
        guard !reactions.isEmpty else {
            rows = []; grouped = [:]; groupedKeys = []; return
        }

        // Fetch sender profiles + challenge titles in two batched queries.
        let senderIds = Array(Set(reactions.map { $0.fromUser }))
        let challengeIds = Array(Set(reactions.map { $0.challengeId }))

        async let profilesFetch = fetchProfiles(ids: senderIds)
        async let challengesFetch = fetchChallengeTitles(ids: challengeIds)

        let profiles = await profilesFetch
        let challenges = await challengesFetch

        rows = reactions.map { r in
            Row(
                id: r.id,
                senderName: profiles[r.fromUser]?.display_name ?? "Someone",
                senderAvatar: profiles[r.fromUser]?.avatar_emoji ?? "👤",
                emoji: r.emoji,
                challengeTitle: challenges[r.challengeId] ?? "challenge",
                createdAt: r.createdAt,
                timeLabel: Self.timeLabel(r.createdAt)
            )
        }
        regroup()
    }

    private func regroup() {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        let cal = Calendar.current

        var buckets: [String: [Row]] = [:]
        var orderedKeys: [String] = []
        for row in rows {
            let day: String
            if cal.isDateInToday(row.createdAt) { day = "Today" }
            else if cal.isDateInYesterday(row.createdAt) { day = "Yesterday" }
            else { day = formatter.string(from: row.createdAt) }
            if buckets[day] == nil { orderedKeys.append(day) }
            buckets[day, default: []].append(row)
        }
        grouped = buckets
        groupedKeys = orderedKeys
    }

    // MARK: - Helpers

    private struct ProfileLite: Decodable {
        let anon_user_id: String
        let display_name: String
        let avatar_emoji: String
    }

    private struct ChallengeLite: Decodable {
        let id: UUID
        let title: String
    }

    private func fetchProfiles(ids: [String]) async -> [String: ProfileLite] {
        guard !ids.isEmpty else { return [:] }
        let profiles: [ProfileLite] = (try? await NCBackend.shared
            .from("profiles")
            .select("anon_user_id, display_name, avatar_emoji")
            .in("anon_user_id", values: ids)
            .execute()
            .value) ?? []
        return Dictionary(uniqueKeysWithValues: profiles.map { ($0.anon_user_id, $0) })
    }

    private func fetchChallengeTitles(ids: [UUID]) async -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let idStrings = ids.map { $0.uuidString.lowercased() }
        let rows: [ChallengeLite] = (try? await NCBackend.shared
            .from("circle_challenges")
            .select("id, title")
            .in("id", values: idStrings)
            .execute()
            .value) ?? []
        return Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.title) })
    }

    private static func timeLabel(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60          { return "just now" }
        if seconds < 3600        { return "\(seconds / 60)m ago" }
        if seconds < 86400       { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}
