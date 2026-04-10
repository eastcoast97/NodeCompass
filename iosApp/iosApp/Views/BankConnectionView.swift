import SwiftUI
import LinkKit

struct BankConnectionView: View {
    @EnvironmentObject var store: TransactionStore
    @StateObject private var viewModel = BankConnectionViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.accounts.isEmpty {
                        disconnectedHero
                    }

                    // Server status (only show if offline — don't clutter when working)
                    if !viewModel.isServerOnline {
                        serverStatusCard
                    }

                    // Connected accounts
                    if !viewModel.accounts.isEmpty {
                        accountsCard
                        syncCard
                    }

                    // Connect bank button — always visible
                    connectButton

                    // How it works (when no accounts)
                    if viewModel.accounts.isEmpty {
                        howItWorksCard
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Banks")
            .onAppear { viewModel.checkServer() }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    // MARK: - Hero (disconnected)

    private var disconnectedHero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.15), NC.teal.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(colors: [.blue, NC.teal], startPoint: .top, endPoint: .bottom)
                    )
            }

            VStack(spacing: 6) {
                Text("Connect Your Bank")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("Automatically sync transactions\nfrom all your accounts.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Server Status

    private var serverStatusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(viewModel.isServerOnline ? .green.opacity(0.12) : .red.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(viewModel.isServerOnline ? .green : .red)
                        .frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.isServerOnline ? "Server Online" : "Server Offline")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(viewModel.serverURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !viewModel.isServerOnline {
                VStack(spacing: 8) {
                    TextField("http://localhost:8080", text: $viewModel.serverURLInput)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .padding(10)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Button {
                        viewModel.updateServerURL()
                    } label: {
                        Text("Connect")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(NC.teal)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .disabled(viewModel.serverURLInput.isEmpty)

                    Text("Run: cd server && npm start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    // MARK: - Connected Accounts

    private var accountsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.accounts.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NC.teal.opacity(0.12))
                    .foregroundStyle(NC.teal)
                    .clipShape(Capsule())
            }

            ForEach(viewModel.accounts, id: \.accountId) { account in
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.blue.opacity(0.1))
                            .frame(width: 40, height: 40)
                        Image(systemName: accountIcon(for: account.type))
                            .foregroundStyle(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.institutionName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 4) {
                            Text(account.name)
                            if let mask = account.mask {
                                Text("••\(mask)")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(account.subtype?.capitalized ?? account.type.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }
        }
        .card()
    }

    // MARK: - Sync

    private var syncCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Bank transactions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.transactions.filter { $0.source == "BANK" }.count)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            HStack {
                Text("Last sync")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.lastSyncText)
                    .font(.subheadline)
            }

            if viewModel.newThisSync > 0 {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(NC.teal)
                    Text("\(viewModel.newThisSync) new transactions!")
                        .fontWeight(.medium)
                        .foregroundStyle(NC.teal)
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(NC.teal.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                viewModel.syncTransactions()
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text(viewModel.isSyncing ? "Syncing..." : "Sync Now")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(NC.teal.opacity(0.12))
                .foregroundStyle(NC.teal)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isSyncing)
        }
        .card()
    }

    // MARK: - Connect Button

    private var connectButton: some View {
        Button {
            if viewModel.isServerOnline {
                viewModel.connectBank()
            } else {
                // Try to connect server first, then connect bank
                viewModel.checkServerThenConnect()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                Text(viewModel.accounts.isEmpty ? "Connect a Bank" : "Add Another Bank")
                    .fontWeight(.semibold)
                if viewModel.isConnecting {
                    Spacer()
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(colors: [.blue, NC.teal], startPoint: .leading, endPoint: .trailing)
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
            .shadow(color: .blue.opacity(0.25), radius: 10, y: 5)
        }
        .disabled(viewModel.isConnecting)
    }

    // MARK: - How It Works

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How It Works")
                .font(.headline)

            HowItWorksRow(icon: "hand.tap.fill", color: .blue,
                          title: "Tap to connect",
                          detail: "Pick your bank, log in with your existing credentials")
            HowItWorksRow(icon: "arrow.triangle.2.circlepath", color: .green,
                          title: "Auto-sync",
                          detail: "Transactions sync every 10 minutes automatically")
            HowItWorksRow(icon: "brain.fill", color: .purple,
                          title: "AI-powered",
                          detail: "Smart categorization for every transaction")
            HowItWorksRow(icon: "lock.shield.fill", color: .orange,
                          title: "Secure & private",
                          detail: "Bank login through Plaid — data stored on-device")
        }
        .card()
    }

    private func accountIcon(for type: String) -> String {
        switch type {
        case "depository": return "banknote.fill"
        case "credit": return "creditcard.fill"
        case "investment": return "chart.line.uptrend.xyaxis"
        default: return "building.columns.fill"
        }
    }
}

private struct HowItWorksRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class BankConnectionViewModel: ObservableObject {
    @Published var isServerOnline: Bool = false
    @Published var isConnecting: Bool = false
    @Published var isSyncing: Bool = false
    @Published var accounts: [PlaidAccount] = []
    @Published var lastSyncText: String = "Never"
    @Published var newThisSync: Int = 0
    @Published var errorMessage: String? = nil
    @Published var serverURLInput: String = ""

    private let plaid = PlaidService.shared
    private let store = TransactionStore.shared
    private var autoCheckTimer: Timer?
    private var linkHandler: Handler?
    private var lastUpdateCounter: Int = 0
    private var foregroundObserver: Any?

    var serverURL: String { plaid.currentServerURL }

    init() {
        // Fix stale localhost URLs cached from previous builds
        let currentURL = plaid.currentServerURL
        if currentURL.contains("localhost") {
            plaid.setServerURL("http://10.0.0.177:8080")
            serverURLInput = "http://10.0.0.177:8080"
        } else {
            serverURLInput = currentURL
        }

        // Auto-check when app comes to foreground
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates() }
        }
    }

    deinit {
        autoCheckTimer?.invalidate()
        if let obs = foregroundObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    func checkServer() {
        Task {
            isServerOnline = await plaid.isServerReachable()
            if isServerOnline {
                await loadAccounts()
                if !accounts.isEmpty { startAutoCheck() }
            }
        }
    }

    func updateServerURL() {
        var url = serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url.removeLast() }
        plaid.setServerURL(url)
        serverURLInput = url
        checkServer()
    }

    func checkServerThenConnect() {
        isConnecting = true
        errorMessage = nil

        Task {
            isServerOnline = await plaid.isServerReachable()
            if isServerOnline {
                await loadAccounts()
                connectBank()
            } else {
                errorMessage = "Server is offline. Enter your Mac's IP address above (e.g. http://10.0.0.177:8080) and tap Connect first."
                isConnecting = false
            }
        }
    }

    func connectBank() {
        isConnecting = true
        errorMessage = nil

        Task {
            do {
                let linkToken = try await plaid.createLinkToken()
                await openPlaidLink(token: linkToken)
            } catch {
                errorMessage = "Failed to connect: \(error.localizedDescription)"
                isConnecting = false
            }
        }
    }

    private func openPlaidLink(token: String) async {
        var config = LinkTokenConfiguration(token: token) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                let publicToken = success.publicToken
                let institutionName = success.metadata.institution.name

                do {
                    try await self.plaid.exchangePublicToken(publicToken, institutionName: institutionName)
                    await self.loadAccounts()
                    self.syncTransactions()
                    self.startAutoCheck()
                    self.isConnecting = false
                } catch {
                    self.errorMessage = "Bank connection failed: \(error.localizedDescription)"
                    self.isConnecting = false
                }
            }
        }

        config.onExit = { [weak self] exit in
            Task { @MainActor in
                if let error = exit.error {
                    self?.errorMessage = "Plaid Link: \(error.errorMessage)"
                }
                self?.isConnecting = false
            }
        }

        let result = Plaid.create(config)
        switch result {
        case .success(let handler):
            self.linkHandler = handler
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = windowScene.windows.first?.rootViewController else {
                errorMessage = "Cannot present bank connection screen"
                isConnecting = false
                return
            }
            handler.open(presentUsing: .viewController(rootVC))
        case .failure(let error):
            errorMessage = "Failed to open bank connection: \(error.localizedDescription)"
            isConnecting = false
        }
    }

    func syncTransactions() {
        isSyncing = true
        newThisSync = 0

        Task {
            do {
                let transactions = try await plaid.syncTransactions()
                var newCount = 0
                for txn in transactions where !txn.pending {
                    let countBefore = store.transactions.count
                    store.addFromBank(txn)
                    if store.transactions.count > countBefore { newCount += 1 }
                }
                newThisSync = newCount
                lastSyncText = formatNow()
                isSyncing = false
                if newCount > 0 {
                    Task { await PatternEngine.shared.runAnalysis() }
                }
            } catch {
                errorMessage = "Sync failed: \(error.localizedDescription)"
                isSyncing = false
            }
        }
    }

    private func loadAccounts() async {
        do { accounts = try await plaid.getConnectedAccounts() }
        catch { accounts = [] }
    }

    /// Lightweight check — asks server "anything new?" (tiny JSON response, no Plaid API call).
    /// Only triggers a full sync if the server says there's new data from webhooks.
    private func checkForUpdates() {
        guard isServerOnline, !isSyncing else { return }

        Task {
            let hasNew = await plaid.checkForUpdates(since: lastUpdateCounter)
            if let result = hasNew {
                lastUpdateCounter = result.counter
                if result.hasUpdates {
                    syncTransactions() // Only sync when server says there's new data
                }
            }
        }
    }

    /// Periodic lightweight check — runs every 30 seconds but costs nothing
    /// unless the server says there are new transactions from Plaid webhooks.
    private func startAutoCheck() {
        autoCheckTimer?.invalidate()
        autoCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdates() }
        }
    }

    private func formatNow() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}
