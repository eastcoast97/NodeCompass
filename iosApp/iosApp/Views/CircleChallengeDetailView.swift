import SwiftUI

/// Leaderboard view for a single circle challenge. Shows:
///   - challenge title + subtitle + pillar / difficulty hint
///   - every participant's current progress ring
///   - days remaining
///
/// Pushed onto the Circles navigation stack via
/// `CircleDetailView.navigationDestination(for: CircleChallenge)`.
struct CircleChallengeDetailView: View {
    let challenge: CoopChallengeSync.CircleChallenge

    @State private var scores: [CoopChallengeSync.ParticipantScore] = []
    @State private var members: [CirclesRemoteSync.CircleMember] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// When non-nil, the ReactionPicker sheet is presented targeting this
    /// member. Distinguishes tapping yourself (no-op) from tapping a
    /// teammate (opens picker).
    @State private var reactionTarget: CirclesRemoteSync.CircleMember?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                leaderboardSection

                if let err = errorMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red).font(.caption)
                        Text(err).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, NC.hPad)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(NC.bgBase)
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Subviews

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(challenge.pillar.uppercased())
                    .font(.caption2.bold())
                    .kerning(1)
                    .foregroundStyle(accentColor)
                Spacer()
                Text(daysRemainingLabel)
                    .font(.caption)
                    .foregroundStyle(NC.textSecondary)
            }

            Text(challenge.title)
                .font(.title3.bold())
                .foregroundStyle(NC.textPrimary)

            if let sub = challenge.subtitle, !sub.isEmpty {
                Text(sub)
                    .font(.subheadline)
                    .foregroundStyle(NC.textSecondary)
            }

            Text("Target: \(Int(challenge.targetValue)) \(challenge.unit)")
                .font(.caption)
                .foregroundStyle(NC.textTertiary)
                .padding(.top, 2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Standings")
                .font(.subheadline.bold())
                .foregroundStyle(NC.textPrimary)

            if isLoading && scores.isEmpty {
                ProgressView().tint(NC.teal).padding(.vertical, 8)
            } else if scores.isEmpty {
                Text("No scores yet — be the first.")
                    .font(.caption)
                    .foregroundStyle(NC.textTertiary)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(sortedScores, id: \.anonUserId) { score in
                        let isMe = score.anonUserId == AnonymousIdentity.shared.anonUserId
                        let member = memberForScore(score)

                        if isMe {
                            // Yourself — no reaction picker, just the row.
                            LeaderboardRow(
                                score: score,
                                member: member,
                                target: challenge.targetValue,
                                accentColor: accentColor
                            )
                        } else {
                            // Teammate — tap to send a reaction.
                            Button {
                                if let m = member {
                                    Haptic.light()
                                    reactionTarget = m
                                }
                            } label: {
                                LeaderboardRow(
                                    score: score,
                                    member: member,
                                    target: challenge.targetValue,
                                    accentColor: accentColor
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .sheet(item: $reactionTarget) { target in
            ReactionPicker(
                challengeId: challenge.id,
                recipientUserId: target.anonUserId,
                recipientDisplayName: target.displayName,
                recipientEmoji: target.avatarEmoji
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helpers

    private var accentColor: Color {
        switch challenge.pillar {
        case "wealth": return NC.wealth
        case "health": return NC.health
        case "mind":   return NC.mind
        case "cross":  return NC.insight
        default:       return NC.teal
        }
    }

    private var daysRemainingLabel: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: Date(), to: challenge.endsAt).day ?? 0
        if days <= 0 { return "Ended" }
        return "\(days) day\(days == 1 ? "" : "s") left"
    }

    private var sortedScores: [CoopChallengeSync.ParticipantScore] {
        scores.sorted { $0.currentValue > $1.currentValue }
    }

    private func memberForScore(_ score: CoopChallengeSync.ParticipantScore) -> CirclesRemoteSync.CircleMember? {
        members.first { $0.anonUserId == score.anonUserId }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            async let scoresFetch = CoopChallengeSync.shared.scores(for: challenge.id)
            async let membersFetch = CirclesRemoteSync.shared.membersOf(circleId: challenge.circleId)
            scores = try await scoresFetch
            members = try await membersFetch
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Leaderboard Row

private struct LeaderboardRow: View {
    let score: CoopChallengeSync.ParticipantScore
    let member: CirclesRemoteSync.CircleMember?
    let target: Double
    let accentColor: Color

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(1.0, score.currentValue / target)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(member?.avatarEmoji ?? "👤")
                .font(.system(size: 28))
                .frame(width: NC.iconSize, height: NC.iconSize)
                .background(NC.bgElevated,
                            in: RoundedRectangle(cornerRadius: NC.iconRadius))

            VStack(alignment: .leading, spacing: 4) {
                Text(member?.displayName ?? "Unknown")
                    .font(.subheadline.bold())
                    .foregroundStyle(NC.textPrimary)

                // Progress bar + numeric score
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(NC.bgElevated)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(accentColor)
                                .frame(width: max(0, geo.size.width * progress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(score.currentValue)) / \(Int(target))")
                        .font(.caption2.monospaced())
                        .foregroundStyle(NC.textSecondary)
                        .frame(minWidth: 60, alignment: .trailing)
                }
            }

            if score.isCompleted {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(accentColor)
            }
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }
}
