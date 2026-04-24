import SwiftUI

/// Modal for joining an existing circle via a 6-character invite code.
struct EnterInviteCodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var joinedCircle: CirclesRemoteSync.Circle?

    /// Auto-uppercase as they type; only keep alphanumerics.
    private var normalizedCode: String {
        code.uppercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private var canJoin: Bool {
        normalizedCode.count == 6 && !isJoining
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let joined = joinedCircle {
                        joinedCard(joined)
                    } else {
                        inputCard
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NC.bgBase)
            .navigationTitle("Enter Invite Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(joinedCircle == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Have a code?")
                .font(.title3.bold())
                .foregroundStyle(NC.textPrimary)
            Text("Enter the 6-character invite code shared by the circle's creator. It looks something like ABC234.")
                .font(.subheadline)
                .foregroundStyle(NC.textSecondary)
        }
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Invite code")
                .font(.caption)
                .foregroundStyle(NC.textTertiary)

            TextField("ABC234", text: $code)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .kerning(6)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(NC.bgElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(NC.textPrimary)
                .onChange(of: code) { _, newValue in
                    // Keep only alphanumeric, uppercase, max 6 chars
                    let cleaned = String(
                        newValue.uppercased()
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(6)
                    )
                    if cleaned != newValue { code = cleaned }
                }

            Button {
                Task { await join() }
            } label: {
                HStack(spacing: 8) {
                    if isJoining { ProgressView().tint(.white) }
                    Text(isJoining ? "Joining…" : "Join Circle")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canJoin ? NC.teal : NC.teal.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canJoin)

            if let err = errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red).font(.caption)
                    Text(err).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private func joinedCard(_ circle: CirclesRemoteSync.Circle) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(NC.teal)
            Text("You're in!")
                .font(.title3.bold())
                .foregroundStyle(NC.textPrimary)
            Text(circle.name)
                .font(.headline)
                .foregroundStyle(NC.textSecondary)
            Text("\(circle.memberCount) member\(circle.memberCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(NC.textTertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Actions

    private func join() async {
        errorMessage = nil
        isJoining = true
        defer { isJoining = false }

        do {
            let circle = try await CirclesRemoteSync.shared.joinWithCode(normalizedCode)
            joinedCircle = circle
            Haptic.medium()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
