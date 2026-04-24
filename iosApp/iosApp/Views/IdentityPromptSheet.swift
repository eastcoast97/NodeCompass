import SwiftUI
import AuthenticationServices

/// First-time modal that asks the user to:
///   1. Sign in with Apple (derives their anonymous user ID).
///   2. Pick a display name + emoji avatar that circle members will see.
///
/// Shown when the user tries to create or join a circle and doesn't yet have
/// an `AnonymousIdentity` + `UserIdentityProfile` configured.
///
/// Aurora-themed — solid `NC.bgSurface` card, no borders, accent teal on the
/// primary action.
struct IdentityPromptSheet: View {
    @ObservedObject private var identity = AnonymousIdentity.shared
    @ObservedObject private var profile = UserIdentityProfile.shared

    @Environment(\.dismiss) private var dismiss

    @State private var draftName: String = ""
    @State private var draftEmoji: String = UserIdentityProfile.avatarChoices.randomElement() ?? "🦊"
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    /// Called after a successful sign-in + profile save. Lets the caller
    /// (e.g. `CreateCircleSheet`) continue its flow.
    var onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header

                    if !identity.hasIdentity {
                        signInCard
                    } else {
                        profileCard
                    }

                    privacyFootnote
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NC.bgBase)
            .navigationTitle("Join Circles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                draftName = profile.displayName
                draftEmoji = profile.avatarEmoji
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before you join a circle")
                .font(.title2.bold())
                .foregroundStyle(NC.textPrimary)
            Text("We need a way to identify you to the 1-to-8 people you invite, without sharing any of your real data.")
                .font(.subheadline)
                .foregroundStyle(NC.textSecondary)
        }
    }

    private var signInCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 1 — Sign in with Apple")
                .font(.subheadline.bold())
                .foregroundStyle(NC.textPrimary)
            Text("We derive a stable anonymous ID from Apple's opaque identifier. No email, no name, no photo crosses the wire.")
                .font(.caption)
                .foregroundStyle(NC.textSecondary)

            // Plain Button styled to resemble Apple's sign-in button.
            // We deliberately avoid `SignInWithAppleButton` here because it
            // insists on owning its own tap handler — mixing our own
            // AnonymousIdentity flow with SIWA button's onCompletion is
            // prone to silent failures (`Color.clear` overlays don't hit-
            // test, etc). For App Store submission we can swap back to the
            // official button and route its onCompletion into
            // AnonymousIdentity; until then, this is the reliable path.
            Button {
                Task { await performSignIn() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 18, weight: .medium))
                    Text("Sign in with Apple")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(.white, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(isSigningIn)
            .opacity(isSigningIn ? 0.6 : 1.0)

            if isSigningIn {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Signing you in…")
                        .font(.caption)
                        .foregroundStyle(NC.textSecondary)
                }
            }

            if let err = errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Step 2 — How should friends see you?")
                .font(.subheadline.bold())
                .foregroundStyle(NC.textPrimary)
            Text("Pick a display name + avatar. Both are visible only to people you invite into a circle.")
                .font(.caption)
                .foregroundStyle(NC.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Display name").font(.caption).foregroundStyle(NC.textTertiary)
                TextField("e.g. Ram", text: $draftName)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(NC.bgElevated, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(NC.textPrimary)
                    .autocorrectionDisabled()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Avatar").font(.caption).foregroundStyle(NC.textTertiary)
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6),
                    spacing: 8
                ) {
                    ForEach(UserIdentityProfile.avatarChoices, id: \.self) { emoji in
                        Button {
                            draftEmoji = emoji
                        } label: {
                            Text(emoji)
                                .font(.title2)
                                .frame(width: 42, height: 42)
                                .background(
                                    draftEmoji == emoji ? NC.teal.opacity(0.2) : NC.bgElevated,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(draftEmoji == emoji ? NC.teal : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button {
                Task { await saveProfile() }
            } label: {
                Text("Save and continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSave ? NC.teal : NC.teal.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    .foregroundStyle(.white)
            }
            .disabled(!canSave)
            .buttonStyle(.plain)

            // Show profile-save errors (RLS reject, network) inline.
            if let err = errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var privacyFootnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(NC.teal)
                Text("What actually leaves your device")
                    .font(.caption.bold())
                    .foregroundStyle(NC.textPrimary)
            }
            Text("• An anonymous ID (hash of Apple's opaque identifier)\n• Your display name + emoji avatar\n• The challenge metrics you share (just numbers)\n\nNever shared: transactions, merchants, amounts, location, health data.")
                .font(.caption)
                .foregroundStyle(NC.textSecondary)
        }
        .padding()
        .background(NC.bgSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Actions

    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func performSignIn() async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }

        do {
            _ = try await identity.signIn()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveProfile() async {
        errorMessage = nil
        if let err = await profile.set(displayName: draftName, avatarEmoji: draftEmoji) {
            // Surface real errors (RLS reject, network, etc.) instead of
            // silently dismissing. Keep the sheet open so the user can retry.
            errorMessage = err
            return
        }
        onComplete()
        dismiss()
    }
}
