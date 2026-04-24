import SwiftUI

/// Main entry point for the Circles feature.
///
/// - No circles yet → large empty state + two CTAs (Create / Enter code)
/// - Has circles → list of them with member count + invite code preview
/// - Identity not yet set up → auto-presents `IdentityPromptSheet`
///
/// Aurora-themed: solid `NC.bgSurface` cards, teal accent, no borders.
struct CirclesView: View {
    @StateObject private var vm = CirclesViewModel()
    @ObservedObject private var reactions = ReactionsSync.shared
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showIdentity = false
    @State private var showInbox = false
    @State private var pendingAction: PendingAction?

    /// What the user wanted to do before we interrupted for identity setup.
    enum PendingAction: Identifiable {
        case create, join
        var id: String {
            switch self {
            case .create: return "create"
            case .join:   return "join"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                NC.bgBase.ignoresSafeArea()

                if vm.isLoading {
                    ProgressView().tint(NC.teal)
                } else if vm.circles.isEmpty {
                    emptyState
                } else {
                    circlesList
                }
            }
            .navigationTitle("Circles")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showInbox = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell")
                                .foregroundStyle(NC.teal)
                            if reactions.unreadCount > 0 {
                                Text("\(min(reactions.unreadCount, 99))")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red, in: Capsule())
                                    .offset(x: 8, y: -6)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            startAction(.create)
                        } label: {
                            Label("Create a Circle", systemImage: "plus.circle")
                        }
                        Button {
                            startAction(.join)
                        } label: {
                            Label("Enter Invite Code", systemImage: "envelope.open")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(NC.teal)
                    }
                }
            }
            .task {
                await vm.load()
                // Two paths feed the reactions banner:
                //   1. Realtime websocket (fast, ~200ms) — when it works
                //   2. 15s polling fallback — always reliable
                // Both write into `ReactionsSync.latestInbound`; the banner
                // doesn't care which path delivered the row.
                await ReactionsSync.shared.startListening()
                ReactionsSync.shared.startPolling()
                _ = try? await ReactionsSync.shared.refreshInbox()
            }
            .refreshable { await vm.load() }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await vm.load() } }) {
                CreateCircleSheet()
            }
            .sheet(isPresented: $showJoin, onDismiss: { Task { await vm.load() } }) {
                EnterInviteCodeSheet()
            }
            .sheet(isPresented: $showIdentity) {
                IdentityPromptSheet(onComplete: {
                    // After identity is set up, resume whatever the user was
                    // trying to do.
                    if let action = pendingAction {
                        pendingAction = nil
                        switch action {
                        case .create: showCreate = true
                        case .join:   showJoin = true
                        }
                    }
                })
            }
            .sheet(isPresented: $showInbox) {
                ReactionInbox()
            }
            // Lightweight in-app banner when a new reaction arrives via
            // realtime while the user is in the Circles view. Slides in
            // from the top for ~3 seconds then auto-dismisses.
            .overlay(alignment: .top) {
                if let latest = reactions.latestInbound {
                    ReactionBanner(row: latest)
                        .padding(.horizontal, NC.hPad)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(10)
                }
            }
            .animation(.spring(), value: reactions.latestInbound?.id)
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 52))
                .foregroundStyle(NC.teal.opacity(0.4))
            Text("No circles yet")
                .font(.title3.bold())
                .foregroundStyle(NC.textPrimary)
            Text("Create a circle to challenge up to 8 friends. Only people you invite ever see your activity.")
                .font(.subheadline)
                .foregroundStyle(NC.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(spacing: 10) {
                Button {
                    startAction(.create)
                } label: {
                    Label("Create a Circle", systemImage: "plus.circle.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(NC.teal, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    startAction(.join)
                } label: {
                    Label("Enter Invite Code", systemImage: "envelope.open")
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                        .foregroundStyle(NC.teal)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NC.hPad)
            .padding(.top, 12)
        }
        .padding()
    }

    private var circlesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(vm.circles) { circle in
                    NavigationLink(value: circle) {
                        CircleRow(circle: circle)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NC.hPad)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationDestination(for: CirclesRemoteSync.Circle.self) { circle in
            CircleDetailView(circle: circle)
        }
    }

    // MARK: - Actions

    /// Dispatch an action, interrupting with the identity prompt if the user
    /// hasn't signed in yet.
    private func startAction(_ action: PendingAction) {
        if !AnonymousIdentity.shared.hasIdentity
            || !UserIdentityProfile.shared.isConfigured {
            pendingAction = action
            showIdentity = true
        } else {
            switch action {
            case .create: showCreate = true
            case .join:   showJoin = true
            }
        }
    }
}

// MARK: - Circle Row

private struct CircleRow: View {
    let circle: CirclesRemoteSync.Circle

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.3.sequence.fill")
                .font(.title3)
                .foregroundStyle(NC.teal)
                .frame(width: NC.iconSize, height: NC.iconSize)
                .background(NC.teal.opacity(0.15),
                            in: RoundedRectangle(cornerRadius: NC.iconRadius))

            VStack(alignment: .leading, spacing: 4) {
                Text(circle.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(NC.textPrimary)
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                    Text("\(circle.memberCount) member\(circle.memberCount == 1 ? "" : "s")")
                        .font(.caption)
                }
                .foregroundStyle(NC.textSecondary)
            }

            Spacer()

            Text(circle.inviteCode)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(NC.bgElevated, in: Capsule())
                .foregroundStyle(NC.textSecondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(NC.textTertiary)
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }
}

// MARK: - Reaction Banner

/// Ephemeral in-app banner shown when a reaction arrives via realtime.
/// Auto-dismisses after ~3s by nilling the published `latestInbound` that
/// drives its visibility.
private struct ReactionBanner: View {
    let row: ReactionsSync.ReactionRow

    @State private var senderName: String = "Someone"
    @State private var senderAvatar: String = "👤"

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Text(senderAvatar).font(.system(size: 24))
                    .frame(width: 32, height: 32)
                    .background(NC.bgElevated, in: Circle())
                Text(row.emoji)
                    .font(.system(size: 16))
                    .offset(x: 4, y: 4)
            }
            Text("\(senderName) sent you \(row.emoji)")
                .font(.subheadline.bold())
                .foregroundStyle(NC.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NC.bgSurface, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
        .task(id: row.id) {
            // Resolve the sender's display info + ping haptic.
            await loadSender()
            Haptic.light()
            // Auto-dismiss after ~3s.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            ReactionsSync.shared.acknowledgeBanner(id: row.id)
        }
    }

    private func loadSender() async {
        struct ProfileLite: Decodable {
            let display_name: String
            let avatar_emoji: String
        }
        do {
            let rows: [ProfileLite] = try await NCBackend.shared
                .from("profiles")
                .select("display_name, avatar_emoji")
                .eq("anon_user_id", value: row.fromUser)
                .limit(1)
                .execute()
                .value
            if let r = rows.first {
                senderName = r.display_name
                senderAvatar = r.avatar_emoji
            }
        } catch { /* fall back to defaults */ }
    }
}

// MARK: - View Model

@MainActor
final class CirclesViewModel: ObservableObject {
    @Published var circles: [CirclesRemoteSync.Circle] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        defer { isLoading = false }

        errorMessage = nil
        do {
            circles = try await CirclesRemoteSync.shared.myCircles()
        } catch {
            circles = []
            errorMessage = error.localizedDescription
        }
    }
}
