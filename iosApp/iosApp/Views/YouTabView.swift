import SwiftUI
import CoreLocation
import GoogleSignIn
import LinkKit

// MARK: - "You" Tab — Integrations + Settings in one place

struct YouTabView: View {
    @EnvironmentObject var store: TransactionStore
    @StateObject private var categorizer = SmartCategorizer.shared
    @StateObject private var locationState = LocationSettingsState()
    @StateObject private var emailVM = EmailSyncViewModel()
    @StateObject private var bankVM = BankConnectionViewModel()

    @State private var healthEnabled = UserDefaults.standard.bool(forKey: "healthKitAuthorized")
    @State private var showGeminiSetup = false
    @State private var showLocationSetup = false
    @State private var showClearConfirm = false
    @State private var isRecategorizing = false
    @State private var showHeatmap = false
    @State private var showCoach = false
    @State private var showWrapped = false
    @State private var selectedTheme: String = UserDefaults.standard.string(forKey: "preferredColorScheme") ?? "system"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Integrations
                    integrationsSection

                    // MARK: - Explore
                    exploreSection

                    // MARK: - Appearance
                    appearanceSection

                    // MARK: - Privacy
                    privacySection

                    // MARK: - Data & App
                    dataSection
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showGeminiSetup) {
                GeminiSetupView(isPresented: $showGeminiSetup)
            }
            .sheet(isPresented: $showLocationSetup, onDismiss: {
                locationState.refreshStatus()
            }) {
                LocationSetupView(isPresented: $showLocationSetup)
            }
            .alert("Clear All Data?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    store.clearAll()
                    Task {
                        await EventStore.shared.clearAll()
                        await PatternEngine.shared.clearAll()
                        await UserProfileStore.shared.clearAll()
                        await FoodStore.shared.clearAll()
                    }
                }
            } message: {
                Text("This will delete all \(store.transactions.count) transactions. This cannot be undone.")
            }
        }
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "link", title: "Integrations")

            VStack(spacing: 0) {
                // Bank
                IntegrationRow(
                    icon: "building.columns.fill",
                    color: .blue,
                    title: "Bank",
                    status: bankVM.accounts.isEmpty
                        ? "Not connected"
                        : (bankVM.errorMessage != nil
                            ? "Needs re-link"
                            : "\(bankVM.accounts.count) account\(bankVM.accounts.count == 1 ? "" : "s")"),
                    isConnected: !bankVM.accounts.isEmpty && bankVM.errorMessage == nil,
                    detail: bankVM.accounts.isEmpty ? nil : (bankVM.errorMessage ?? bankVM.lastSyncText),
                    isSyncing: bankVM.isSyncing,
                    primaryAction: ("Connect", { bankVM.connectBank() }),
                    secondaryAction: bankVM.accounts.isEmpty
                        ? nil
                        : (bankVM.errorMessage != nil
                            ? ("Re-link", { bankVM.connectBank() })
                            : ("Sync", { bankVM.syncTransactions() })),
                    showAddMore: !bankVM.accounts.isEmpty && bankVM.errorMessage == nil,
                    addMoreAction: { bankVM.connectBank() }
                )

                Divider().padding(.leading, NC.dividerIndent)

                // Email
                if emailVM.hasConnectedAccounts {
                    // Header row
                    IntegrationRow(
                        icon: "envelope.fill",
                        color: .purple,
                        title: "Email",
                        status: "\(emailVM.accounts.count) account\(emailVM.accounts.count == 1 ? "" : "s") • \(emailVM.totalReceipts) receipts",
                        isConnected: true,
                        isSyncing: false,
                        secondaryAction: ("Sync All", {
                            for account in emailVM.accounts where account.isAuthenticated {
                                emailVM.syncNow(email: account.email)
                            }
                        })
                    )

                    // Per-account sub-rows
                    ForEach(emailVM.accounts) { account in
                        Divider().padding(.leading, 76)
                        EmailAccountRow(
                            account: account,
                            onSync: { emailVM.syncNow(email: account.email) },
                            onReAuth: { emailVM.reAuthenticate(email: account.email) },
                            onRemove: { emailVM.removeAccount(email: account.email) }
                        )
                    }

                    // Add another
                    Divider().padding(.leading, NC.dividerIndent)
                    Button { emailVM.addAccount() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption).foregroundStyle(.purple)
                            Text("Add another Gmail")
                                .font(.caption).foregroundStyle(.purple)
                            Spacer()
                        }
                        .padding(.leading, NC.dividerIndent)
                        .padding(.vertical, 10)
                        .padding(.trailing, NC.hPad)
                    }
                } else {
                    IntegrationRow(
                        icon: "envelope.fill",
                        color: .purple,
                        title: "Email",
                        status: "Not connected",
                        isConnected: false,
                        primaryAction: ("Connect Gmail", { emailVM.addAccount() })
                    )
                }

                Divider().padding(.leading, NC.dividerIndent)

                // Health
                IntegrationRow(
                    icon: "heart.fill",
                    color: .pink,
                    title: "Health",
                    status: healthEnabled ? "Connected (steps, workouts, sleep)" : "Not connected",
                    isConnected: healthEnabled,
                    detail: healthEnabled ? "Via Apple Health — includes wearable data" : nil,
                    isSyncing: false,
                    primaryAction: healthEnabled ? nil : ("Connect", { connectHealth() }),
                    secondaryAction: healthEnabled ? ("Disconnect", { disconnectHealth() }) : nil
                )

                Divider().padding(.leading, NC.dividerIndent)

                // Location
                IntegrationRow(
                    icon: "location.fill",
                    color: .blue,
                    title: "Location",
                    status: locationState.isTrackingEnabled ? "Active — learning your places" : (locationState.permissionDenied ? "Permission denied" : "Disabled"),
                    isConnected: locationState.isTrackingEnabled,
                    detail: locationState.isTrackingEnabled ? "Battery-efficient visit detection" : nil,
                    isSyncing: false,
                    primaryAction: locationState.isTrackingEnabled ? nil : ("Enable", {
                        if locationState.permissionDenied {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            showLocationSetup = true
                        }
                    }),
                    secondaryAction: locationState.isTrackingEnabled ? ("Disable", {
                        LocationCollector.shared.stopTracking()
                        locationState.isTrackingEnabled = false
                    }) : nil
                )

                Divider().padding(.leading, NC.dividerIndent)

                // AI Brain
                IntegrationRow(
                    icon: "sparkles",
                    color: NC.teal,
                    title: "AI Brain",
                    status: categorizer.isConfigured ? "Active (Llama 3.3)" : "Not configured",
                    isConnected: categorizer.isConfigured,
                    detail: categorizer.isConfigured ? "Auto-categorizes transactions & receipts" : nil,
                    isSyncing: false,
                    primaryAction: categorizer.isConfigured ? nil : ("Set Up", { showGeminiSetup = true }),
                    secondaryAction: categorizer.isConfigured ? ("Remove Key", { categorizer.removeApiKey() }) : nil
                )
            }
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
    }

    // MARK: - Privacy Section

    // MARK: - Explore Section

    private var exploreSection: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "sparkles", title: "Explore")

            VStack(spacing: 0) {
                Button { showHeatmap = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "map.fill")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                            .frame(width: NC.iconSize, height: NC.iconSize)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: NC.iconRadius))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Location Heatmap").font(.subheadline).foregroundStyle(.primary)
                            Text("See where you spend time and money").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(NC.hPad)
                }

                Divider().padding(.leading, NC.dividerIndent)

                Button { showCoach = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "brain.head.profile")
                            .font(.subheadline)
                            .foregroundStyle(NC.teal)
                            .frame(width: NC.iconSize, height: NC.iconSize)
                            .background(NC.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: NC.iconRadius))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Life Coach").font(.subheadline).foregroundStyle(.primary)
                            Text("Ask about your life patterns").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(NC.hPad)
                }

                Divider().padding(.leading, NC.dividerIndent)

                Button { showWrapped = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sparkles")
                            .font(.subheadline)
                            .foregroundStyle(.indigo)
                            .frame(width: NC.iconSize, height: NC.iconSize)
                            .background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: NC.iconRadius))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Monthly Wrapped").font(.subheadline).foregroundStyle(.primary)
                            Text("Your month in review").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(NC.hPad)
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
        .sheet(isPresented: $showHeatmap) { LocationHeatmapView() }
        .sheet(isPresented: $showCoach) { LifeCoachView() }
        .sheet(isPresented: $showWrapped) { MonthlyWrappedView() }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "paintbrush.fill", title: "Appearance")

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(["system", "light", "dark"], id: \.self) { theme in
                        Button {
                            Haptic.selection()
                            selectedTheme = theme
                            switch theme {
                            case "dark": NC.preferredColorScheme = .dark
                            case "light": NC.preferredColorScheme = .light
                            default: NC.preferredColorScheme = nil
                            }
                            NotificationCenter.default.post(name: NSNotification.Name("themeChanged"), object: nil)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: themeIcon(theme))
                                    .font(.title3)
                                    .foregroundStyle(selectedTheme == theme ? NC.teal : .secondary)
                                Text(theme.capitalized)
                                    .font(.caption.bold())
                                    .foregroundStyle(selectedTheme == theme ? NC.teal : .secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                selectedTheme == theme
                                    ? NC.teal.opacity(0.08)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: NC.iconRadius)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(NC.hPad)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
    }

    private func themeIcon(_ theme: String) -> String {
        switch theme {
        case "dark": return "moon.fill"
        case "light": return "sun.max.fill"
        default: return "circle.lefthalf.filled"
        }
    }

    private var privacySection: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "lock.fill", title: "Privacy")

            VStack(spacing: 0) {
                PrivacyDetailRow(icon: "lock.shield.fill", color: .blue,
                                 title: "On-device storage", detail: "All data stays on your phone")
                Divider().padding(.leading, NC.dividerIndent)
                PrivacyDetailRow(icon: "icloud.slash.fill", color: .orange,
                                 title: "No cloud, no servers", detail: "Zero telemetry or analytics")
                if categorizer.isConfigured {
                    Divider().padding(.leading, NC.dividerIndent)
                    PrivacyDetailRow(icon: "brain.fill", color: NC.teal,
                                     title: "AI: merchant names only", detail: "Amounts & accounts never leave device")
                }
                if locationState.isTrackingEnabled {
                    Divider().padding(.leading, NC.dividerIndent)
                    PrivacyDetailRow(icon: "location.fill", color: .blue,
                                     title: "Location: on-device only", detail: "GPS data never leaves your phone")
                }
                if healthEnabled {
                    Divider().padding(.leading, NC.dividerIndent)
                    PrivacyDetailRow(icon: "heart.fill", color: .pink,
                                     title: "Health: read-only", detail: "Never writes to or modifies your health data")
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
    }

    // MARK: - Data Section

    private var dataSection: some View {
        VStack(spacing: 0) {
            sectionHeader(icon: "externaldrive.fill", title: "Data & App")

            VStack(spacing: 0) {
                DataRow(label: "Total transactions", value: "\(store.transactions.count)")
                Divider().padding(.leading, NC.hPad)
                DataRow(label: "From Bank", value: "\(store.transactions.filter { $0.source == "BANK" }.count)")
                Divider().padding(.leading, NC.hPad)
                DataRow(label: "From Email", value: "\(store.transactions.filter { $0.source == "EMAIL" }.count)")

                if categorizer.isConfigured && !store.transactions.isEmpty {
                    Divider().padding(.leading, NC.hPad)
                    Button {
                        recategorizeAll()
                    } label: {
                        HStack {
                            Label("Re-categorize All", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline)
                            Spacer()
                            if isRecategorizing { ProgressView().scaleEffect(0.8) }
                        }
                        .padding(NC.hPad)
                    }
                    .disabled(isRecategorizing)
                }

                Divider().padding(.leading, NC.hPad)

                Button {
                    showClearConfirm = true
                } label: {
                    HStack {
                        Label("Clear All Data", systemImage: "trash.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(NC.hPad)
                }

                Divider().padding(.leading, NC.hPad)

                // Re-run onboarding
                Button {
                    UserDefaults.standard.set(false, forKey: "onboardingComplete")
                    NotificationCenter.default.post(name: NSNotification.Name("resetOnboarding"), object: nil)
                } label: {
                    HStack {
                        Label("Re-run Onboarding", systemImage: "arrow.counterclockwise")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding(NC.hPad)
                }

                Divider().padding(.leading, NC.hPad)

                HStack {
                    Text("Version").font(.subheadline)
                    Spacer()
                    Text("1.0.0").font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(NC.hPad)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func connectHealth() {
        Task {
            try? await HealthCollector.shared.requestAuthorization()
            await HealthCollector.shared.collectAndStore()
            HealthCollector.shared.enableBackgroundDelivery()
            await MainActor.run { healthEnabled = true }
        }
    }

    private func disconnectHealth() {
        UserDefaults.standard.set(false, forKey: "healthKitAuthorized")
        healthEnabled = false
    }

    private func recategorizeAll() {
        isRecategorizing = true
        Task {
            let uniqueMerchants = Array(Set(store.transactions.map(\.merchant)))
            let results = await SmartCategorizer.shared.categorizeBatch(merchants: uniqueMerchants)
            for (merchant, result) in results {
                for i in store.transactions.indices where store.transactions[i].merchant == merchant {
                    let old = store.transactions[i]
                    if old.category != result.category {
                        let updated = StoredTransaction(
                            id: old.id, amount: old.amount,
                            currencySymbol: old.currencySymbol, currencyCode: old.currencyCode,
                            merchant: result.displayName.isEmpty ? old.merchant : result.displayName,
                            category: result.category,
                            description: result.description.isEmpty ? old.description : result.description,
                            lineItems: old.lineItems, type: old.type, source: old.source,
                            account: old.account, rawText: old.rawText,
                            date: old.date, createdAt: old.createdAt, categorizedByAI: true
                        )
                        store.updateTransaction(at: i, with: updated)
                    }
                }
            }
            isRecategorizing = false
        }
    }
}

// MARK: - Integration Row

private struct IntegrationRow: View {
    let icon: String
    let color: Color
    let title: String
    let status: String
    let isConnected: Bool
    var detail: String?
    var isSyncing: Bool = false
    var primaryAction: (label: String, action: () -> Void)?
    var secondaryAction: (label: String, action: () -> Void)?
    var showAddMore: Bool = false
    var addMoreAction: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                        .fill(isConnected ? color.opacity(0.12) : Color(.systemGray5))
                        .frame(width: NC.iconSize, height: NC.iconSize)
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(isConnected ? color : .secondary)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if isConnected {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(isConnected ? color : .secondary)
                        .lineLimit(1)
                    if let detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Actions
                HStack(spacing: 8) {
                    if isSyncing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        if let secondary = secondaryAction, isConnected {
                            Button(action: secondary.action) {
                                Text(secondary.label)
                                    .font(.caption.bold())
                                    .foregroundStyle(color)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(color.opacity(0.1), in: Capsule())
                            }
                        }

                        if !isConnected, let primary = primaryAction {
                            Button(action: primary.action) {
                                Text(primary.label)
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(color, in: Capsule())
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, NC.hPad)
            .padding(.vertical, NC.vPad)

            // "Add another" row
            if showAddMore, let addMore = addMoreAction {
                Divider().padding(.leading, NC.dividerIndent)
                Button(action: addMore) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(color)
                        Text("Add another")
                            .font(.caption)
                            .foregroundStyle(color)
                        Spacer()
                    }
                    .padding(.leading, NC.dividerIndent)
                    .padding(.vertical, 10)
                    .padding(.trailing, NC.hPad)
                }
            }
        }
    }
}

// MARK: - Support Views

private struct PrivacyDetailRow: View {
    let icon: String; let color: Color; let title: String; let detail: String
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, NC.vPad)
    }
}

private struct DataRow: View {
    let label: String; let value: String
    var body: some View {
        HStack {
            Text(label).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundStyle(.secondary)
        }
        .padding(NC.hPad)
    }
}

// MARK: - Email Account Row (per-account with re-auth)

private struct EmailAccountRow: View {
    let account: GmailAccountState
    let onSync: () -> Void
    let onReAuth: () -> Void
    let onRemove: () -> Void

    @State private var showRemoveConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Indent + status dot
            Spacer().frame(width: NC.iconSize)

            Circle()
                .fill(account.isAuthenticated ? .green : .orange)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.email)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if !account.isAuthenticated {
                        Text("Session expired")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("\(account.receiptsFound) receipts")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if !account.lastSyncText.isEmpty {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(account.lastSyncText)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                if let error = account.errorMessage {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }

            Spacer()

            // Actions
            if account.isSyncing {
                ProgressView().scaleEffect(0.7)
            } else if !account.isAuthenticated {
                Button(action: onReAuth) {
                    Text("Re-auth")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.orange, in: Capsule())
                }
            } else {
                HStack(spacing: 6) {
                    Button(action: onSync) {
                        Text("Sync")
                            .font(.caption2.bold())
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.purple.opacity(0.1), in: Capsule())
                    }

                    Button { showRemoveConfirm = true } label: {
                        Image(systemName: "trash")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 26, height: 26)
                            .background(Color(.systemGray5), in: Circle())
                    }
                }
            }
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, 8)
        .alert("Remove Account?", isPresented: $showRemoveConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: onRemove)
        } message: {
            Text("Remove \(account.email)? This won't delete synced transactions.")
        }
    }
}
