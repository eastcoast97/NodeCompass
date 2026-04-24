import SwiftUI

/// Modal for creating a new circle. Single text field + Create button.
struct CreateCircleSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var createdCircle: CirclesRemoteSync.Circle?

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        name.count <= 50 &&
        !isCreating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let created = createdCircle {
                        successCard(created)
                    } else {
                        nameInputCard
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(NC.bgBase)
            .navigationTitle("New Circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(createdCircle == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(createdCircle == nil
                 ? "Name your circle"
                 : "Share the invite code")
                .font(.title3.bold())
                .foregroundStyle(NC.textPrimary)
            Text(createdCircle == nil
                 ? "Anyone you give the invite code can join — up to 8 people total."
                 : "Anyone with this code can join. You can always leave the circle later.")
                .font(.subheadline)
                .foregroundStyle(NC.textSecondary)
        }
    }

    private var nameInputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Circle name")
                .font(.caption)
                .foregroundStyle(NC.textTertiary)

            TextField("e.g. Gym Buddies", text: $name)
                .textFieldStyle(.plain)
                .padding(12)
                .background(NC.bgElevated, in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(NC.textPrimary)
                .autocorrectionDisabled()

            Button {
                Task { await create() }
            } label: {
                HStack(spacing: 8) {
                    if isCreating { ProgressView().tint(.white) }
                    Text(isCreating ? "Creating…" : "Create Circle")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canCreate ? NC.teal : NC.teal.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)

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

    private func successCard(_ circle: CirclesRemoteSync.Circle) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundStyle(NC.teal)

            Text(circle.name)
                .font(.title3.bold())
                .foregroundStyle(NC.textPrimary)

            VStack(spacing: 4) {
                Text("Invite code")
                    .font(.caption)
                    .foregroundStyle(NC.textTertiary)
                Text(circle.inviteCode)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(NC.teal)
                    .kerning(4)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(NC.bgElevated, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(.top, 8)

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
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Actions

    private func create() async {
        errorMessage = nil
        isCreating = true
        defer { isCreating = false }

        do {
            let circle = try await CirclesRemoteSync.shared.createCircle(name: name)
            createdCircle = circle
            Haptic.medium()
        } catch {
            // On failure, augment the error message with server-side auth
            // state so we can diagnose immediately whether the issue is
            // auth-context (JWT not attached) or something else.
            var msg = error.localizedDescription
            if let who = try? await CirclesRemoteSync.shared.whoami() {
                msg += "\n\n[server sees uid=\(who.uid), role=\(who.role)]"
            }
            errorMessage = msg
        }
    }
}
