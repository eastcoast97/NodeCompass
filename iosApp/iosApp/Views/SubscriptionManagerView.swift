import SwiftUI

/// Subscription manager view — shows detected recurring charges with totals.
struct SubscriptionManagerView: View {
    @StateObject private var vm = SubscriptionManagerViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Monthly Total Hero Card
                    monthlyTotalCard

                    // Active Subscriptions
                    if vm.isLoading {
                        loadingState
                    } else if vm.active.isEmpty {
                        emptyState
                    } else {
                        activeSubscriptionsSection
                    }

                    // Inactive Subscriptions
                    if !vm.inactive.isEmpty {
                        inactiveSection
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Subscriptions")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Monthly Total Card

    private var monthlyTotalCard: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Monthly Subscriptions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(NC.money(vm.monthlyTotal))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(NC.teal)
            }

            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Yearly")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(NC.money(vm.yearlyTotal))
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(vm.active.count)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text("Inactive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(vm.inactive.count)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .card()
    }

    // MARK: - Active Subscriptions

    private var activeSubscriptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "repeat")
                    .foregroundStyle(NC.teal)
                Text("Active Subscriptions")
                    .font(.subheadline.bold())
            }

            ForEach(vm.active) { sub in
                SubscriptionRow(sub: sub)
                    .contextMenu {
                        Button {
                            Task { await vm.markInactive(id: sub.id) }
                        } label: {
                            Label("Mark Inactive", systemImage: "xmark.circle")
                        }
                        Button {
                            vm.showCancelReminder(for: sub)
                        } label: {
                            Label("Set Cancel Reminder", systemImage: "bell.badge")
                        }
                    }
            }
        }
        .sheet(item: $vm.reminderSub) { sub in
            CancelReminderSheet(subscription: sub) { date in
                Task { await vm.setCancelReminder(id: sub.id, date: date) }
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Inactive Section

    private var inactiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                Text("Inactive")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            ForEach(vm.inactive) { sub in
                SubscriptionRow(sub: sub, dimmed: true)
                    .contextMenu {
                        Button {
                            Task { await vm.markActive(id: sub.id) }
                        } label: {
                            Label("Reactivate", systemImage: "checkmark.circle")
                        }
                    }
            }
        }
    }

    // MARK: - Loading & Empty

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Analyzing transactions...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .card()
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "repeat.circle")
                .font(.system(size: 40))
                .foregroundStyle(NC.teal.opacity(0.4))
            Text("No subscriptions detected")
                .font(.headline)
            Text("NodeCompass will automatically detect recurring charges from your transaction history.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .card()
    }
}

// MARK: - Subscription Row

private struct SubscriptionRow: View {
    let sub: SubscriptionManager.Subscription
    var dimmed: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: NC.icon(for: sub.category))
                .font(.title3)
                .foregroundStyle(dimmed ? .secondary : NC.color(for: sub.category))
                .frame(width: NC.iconSize, height: NC.iconSize)
                .background(
                    (dimmed ? Color(.systemGray4) : NC.color(for: sub.category).opacity(0.12)),
                    in: RoundedRectangle(cornerRadius: NC.iconRadius)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(sub.merchant)
                    .font(.subheadline.bold())
                    .foregroundStyle(dimmed ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(sub.frequency.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let next = sub.nextChargeDate, sub.isActive {
                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text("Next: \(next, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let reminder = sub.cancelReminder {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 9))
                        Text("Cancel by \(reminder, style: .date)")
                            .font(.caption2)
                    }
                    .foregroundStyle(.orange)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(NC.money(sub.amount))
                    .font(.subheadline.bold())
                    .foregroundStyle(dimmed ? .secondary : .primary)
                Text("/\(sub.frequency.label.lowercased())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .opacity(dimmed ? 0.7 : 1.0)
    }
}

// MARK: - Cancel Reminder Sheet

private struct CancelReminderSheet: View {
    let subscription: SubscriptionManager.Subscription
    var onSet: (Date) -> Void

    @State private var reminderDate = Date()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "bell.badge")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("Cancel Reminder")
                        .font(.headline)
                    Text("Set a reminder to cancel \(subscription.merchant)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                DatePicker("Remind on", selection: $reminderDate, in: Date()..., displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.horizontal, NC.hPad)

                Button {
                    onSet(reminderDate)
                    dismiss()
                } label: {
                    Text("Set Reminder")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(NC.teal, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, NC.hPad)
            }
            .padding(.top, 20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
class SubscriptionManagerViewModel: ObservableObject {
    @Published var active: [SubscriptionManager.Subscription] = []
    @Published var inactive: [SubscriptionManager.Subscription] = []
    @Published var monthlyTotal: Double = 0
    @Published var yearlyTotal: Double = 0
    @Published var isLoading = false
    @Published var reminderSub: SubscriptionManager.Subscription?

    func load() async {
        isLoading = true
        let manager = SubscriptionManager.shared

        let all = await manager.allSubscriptions()
        active = all.filter(\.isActive).sorted { ($0.nextChargeDate ?? .distantPast) < ($1.nextChargeDate ?? .distantPast) }
        inactive = all.filter { !$0.isActive }
        monthlyTotal = await manager.monthlyTotal()
        yearlyTotal = await manager.yearlyTotal()
        isLoading = false
    }

    func markInactive(id: String) async {
        await SubscriptionManager.shared.markInactive(id: id)
        await load()
    }

    func markActive(id: String) async {
        await SubscriptionManager.shared.markActive(id: id)
        await load()
    }

    func setCancelReminder(id: String, date: Date) async {
        await SubscriptionManager.shared.setCancelReminder(id: id, date: date)
        await load()
    }

    func showCancelReminder(for sub: SubscriptionManager.Subscription) {
        reminderSub = sub
    }
}

// MARK: - Make Subscription Identifiable for sheet binding

extension SubscriptionManager.Subscription: @retroactive Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension SubscriptionManager.Subscription: @retroactive Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
