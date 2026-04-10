import SwiftUI

struct EmailSyncView: View {
    @StateObject private var viewModel = EmailSyncViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if viewModel.hasConnectedAccounts {
                        connectedState
                    } else {
                        disconnectedState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Orders")
        }
    }

    // MARK: - Disconnected State (no accounts)

    private var disconnectedState: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.purple.opacity(0.15), .blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .blue], startPoint: .top, endPoint: .bottom)
                    )
            }
            .padding(.top, 20)

            VStack(spacing: 8) {
                Text("Track Your Orders")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Connect your Gmail accounts to automatically\nfind receipts from Amazon, Uber Eats, and more.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            addAccountButton

            if let error = viewModel.addAccountError {
                errorBanner(error)
            }

            // Privacy bullets
            VStack(alignment: .leading, spacing: 10) {
                PrivacyBullet(icon: "eye.slash.fill", text: "Read-only access to receipts")
                PrivacyBullet(icon: "iphone", text: "All parsing on your device")
                PrivacyBullet(icon: "xmark.icloud.fill", text: "No email content stored or sent")
                PrivacyBullet(icon: "person.2.fill", text: "Add multiple accounts")
                PrivacyBullet(icon: "key.fill", text: "Disconnect anytime")
            }
            .card()
        }
    }

    // MARK: - Connected State (one or more accounts)

    private var connectedState: some View {
        VStack(spacing: 16) {
            // Account cards
            ForEach(viewModel.accounts) { account in
                AccountCard(account: account, viewModel: viewModel)
            }

            // Re-scan all emails (re-parse for food items etc.)
            Button {
                viewModel.rescanAll()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .font(.subheadline)
                    Text("Re-scan All Emails")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.purple.opacity(0.1))
                .foregroundStyle(.purple)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Add another account
            addAccountButton

            if let error = viewModel.addAccountError {
                errorBanner(error)
            }

            // Aggregate stats
            if viewModel.accounts.count > 1 {
                VStack(spacing: 0) {
                    StatRow(label: "Total accounts", value: "\(viewModel.accounts.count)", icon: "person.2.fill")
                    Divider().padding(.horizontal)
                    StatRow(label: "Total receipts", value: "\(viewModel.totalReceipts)", icon: "doc.text.fill")
                }
                .card(padding: 0)
            }
        }
    }

    // MARK: - Shared Components

    private var addAccountButton: some View {
        Button {
            viewModel.addAccount()
        } label: {
            HStack(spacing: 10) {
                if viewModel.isAddingAccount {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: viewModel.hasConnectedAccounts ? "plus.circle.fill" : "envelope.fill")
                        .font(.body)
                }
                Text(viewModel.hasConnectedAccounts ? "Add Another Gmail" : "Connect Gmail")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [.blue, .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
            .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
        }
        .disabled(viewModel.isAddingAccount)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NC.warning)
            Text(message)
                .font(.caption)
        }
        .padding(12)
        .background(NC.warning.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Account Card

private struct AccountCard: View {
    let account: GmailAccountState
    let viewModel: EmailSyncViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Header: status + email
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(account.isAuthenticated ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: account.isAuthenticated ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(account.isAuthenticated ? .green : .orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.email)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Text(account.isAuthenticated ? "Connected" : "Needs re-authentication")
                        .font(.caption)
                        .foregroundColor(account.isAuthenticated ? .secondary : .orange)
                }
                Spacer()
            }

            // Stats
            if account.isAuthenticated {
                VStack(spacing: 0) {
                    StatRow(label: "Receipts", value: "\(account.receiptsFound)", icon: "doc.text.fill")
                    Divider().padding(.horizontal)
                    StatRow(label: "Last sync", value: account.lastSyncText, icon: "clock.fill")
                }
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            // New receipts indicator
            if account.newReceiptsThisSync > 0 {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(NC.teal)
                    Text("\(account.newReceiptsThisSync) new orders found!")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(NC.teal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(NC.teal.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Error
            if let error = account.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NC.warning)
                    Text(error)
                        .font(.caption)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NC.warning.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Actions
            HStack(spacing: 12) {
                if account.isAuthenticated {
                    Button {
                        viewModel.syncNow(email: account.email)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                            Text(account.isSyncing ? "Syncing..." : "Sync")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(NC.teal.opacity(0.12))
                        .foregroundStyle(NC.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(account.isSyncing)
                } else {
                    Button {
                        viewModel.reAuthenticate(email: account.email)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                            Text("Re-authenticate")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.orange.opacity(0.12))
                        .foregroundStyle(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                Button(role: .destructive) {
                    viewModel.removeAccount(email: account.email)
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.red.opacity(0.08))
                        .foregroundStyle(.red.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .card()
    }
}

// MARK: - Subviews

private struct PrivacyBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(NC.teal)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
        }
    }
}

private struct StatRow: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    EmailSyncView()
}
