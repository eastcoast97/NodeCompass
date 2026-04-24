import SwiftUI

/// Bottom sheet for picking one of the four reaction emojis to send to a
/// teammate. Taps on a button send + dismiss.
///
/// Intentionally minimal — no free-form text, no history, just tap → go.
struct ReactionPicker: View {
    let challengeId: UUID
    let recipientUserId: String
    let recipientDisplayName: String
    let recipientEmoji: String

    @Environment(\.dismiss) private var dismiss
    @State private var isSending = false
    @State private var error: String?
    @State private var confirmed: ReactionsSync.Reaction?

    var body: some View {
        VStack(spacing: 20) {
            header

            if let picked = confirmed {
                successView(picked)
            } else {
                emojiGrid
            }

            if let err = error {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                    Text(err).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .padding(.horizontal, NC.hPad)
        .padding(.bottom, 30)
        .background(NC.bgBase)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(recipientEmoji).font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text("React to").font(.caption).foregroundStyle(NC.textTertiary)
                    Text(recipientDisplayName)
                        .font(.title3.bold())
                        .foregroundStyle(NC.textPrimary)
                }
                Spacer()
            }
        }
    }

    private var emojiGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            ForEach(ReactionsSync.Reaction.allCases, id: \.self) { reaction in
                Button {
                    Task { await send(reaction) }
                } label: {
                    Text(reaction.rawValue)
                        .font(.system(size: 44))
                        .frame(height: 80)
                        .frame(maxWidth: .infinity)
                        .background(NC.bgSurface,
                                    in: RoundedRectangle(cornerRadius: NC.cardRadius))
                }
                .buttonStyle(.plain)
                .disabled(isSending)
                .opacity(isSending ? 0.5 : 1.0)
            }
        }
    }

    private func successView(_ picked: ReactionsSync.Reaction) -> some View {
        VStack(spacing: 14) {
            Text(picked.rawValue).font(.system(size: 72))
            Text("Sent to \(recipientDisplayName)")
                .font(.subheadline)
                .foregroundStyle(NC.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(NC.bgSurface,
                    in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .task {
            // Auto-dismiss after a short celebratory beat.
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        }
    }

    // MARK: - Actions

    private func send(_ reaction: ReactionsSync.Reaction) async {
        error = nil
        isSending = true
        defer { isSending = false }

        do {
            try await ReactionsSync.shared.send(
                reaction: reaction,
                challengeId: challengeId,
                toUser: recipientUserId
            )
            Haptic.light()
            confirmed = reaction
        } catch {
            self.error = error.localizedDescription
        }
    }
}
