import SwiftUI

/// Shows a single circle's members + invite code + Leave option.
///
/// Pushed onto `CirclesView`'s navigation stack via `NavigationLink`. In
/// M2.2 this will also render circle-scoped challenges.
struct CircleDetailView: View {
    let circle: CirclesRemoteSync.Circle

    @Environment(\.dismiss) private var dismiss
    @State private var members: [CirclesRemoteSync.CircleMember] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showLeaveConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                inviteCodeCard

                membersSection

                Button(role: .destructive) {
                    showLeaveConfirm = true
                } label: {
                    Label("Leave this circle", systemImage: "arrow.right.square")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.red.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: NC.cardRadius))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

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
        .navigationTitle(circle.name)
        .navigationBarTitleDisplayMode(.large)
        .task { await loadMembers() }
        .refreshable { await loadMembers() }
        .confirmationDialog(
            "Leave \"\(circle.name)\"?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave Circle", role: .destructive) {
                Task { await leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop seeing shared challenges from this circle. You can rejoin later if someone shares the code with you.")
        }
    }

    // MARK: - Subviews

    private var inviteCodeCard: some View {
        VStack(spacing: 10) {
            Text("Invite friends with this code")
                .font(.caption)
                .foregroundStyle(NC.textTertiary)

            Text(circle.inviteCode)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(NC.teal)
                .kerning(4)

            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = circle.inviteCode
                    Haptic.light()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NC.bgElevated,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(NC.textPrimary)
                }
                .buttonStyle(.plain)

                ShareLink(item: "Join my NodeCompass circle \"\(circle.name)\" with code: \(circle.inviteCode)") {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(NC.teal.opacity(0.15),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(NC.teal)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Members")
                    .font(.subheadline.bold())
                    .foregroundStyle(NC.textPrimary)
                Spacer()
                Text("\(members.count)/8")
                    .font(.caption)
                    .foregroundStyle(NC.textTertiary)
            }

            if isLoading && members.isEmpty {
                ProgressView().tint(NC.teal).padding(.vertical, 8)
            } else if members.isEmpty {
                Text("No members loaded yet")
                    .font(.caption)
                    .foregroundStyle(NC.textTertiary)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(members) { m in
                        MemberRow(member: m, isCreator: m.anonUserId == circle.createdBy)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func loadMembers() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        do {
            members = try await CirclesRemoteSync.shared.membersOf(circleId: circle.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leave() async {
        errorMessage = nil
        do {
            try await CirclesRemoteSync.shared.leaveCircle(circleId: circle.id)
            Haptic.medium()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Member Row

private struct MemberRow: View {
    let member: CirclesRemoteSync.CircleMember
    let isCreator: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(member.avatarEmoji)
                .font(.system(size: 28))
                .frame(width: NC.iconSize, height: NC.iconSize)
                .background(NC.bgElevated,
                            in: RoundedRectangle(cornerRadius: NC.iconRadius))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.displayName)
                        .font(.subheadline.bold())
                        .foregroundStyle(NC.textPrimary)
                    if isCreator {
                        Text("creator")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(NC.teal.opacity(0.15), in: Capsule())
                            .foregroundStyle(NC.teal)
                    }
                }
                Text("Joined \(member.joinedAt, style: .date)")
                    .font(.caption)
                    .foregroundStyle(NC.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }
}
