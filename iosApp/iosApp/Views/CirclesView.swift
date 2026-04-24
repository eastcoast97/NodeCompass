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
    @State private var showCreate = false
    @State private var showJoin = false
    @State private var showIdentity = false
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
            .task { await vm.load() }
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
