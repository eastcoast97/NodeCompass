import SwiftUI

/// Challenges view — time-bound goals with progress tracking.
struct ChallengesView: View {
    @StateObject private var vm = ChallengesViewModel()
    @State private var showNewChallenge = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active Challenges
                    if vm.active.isEmpty && vm.completed.isEmpty {
                        emptyState
                    } else if !vm.active.isEmpty {
                        activeChallengesSection
                    }

                    // Start a Challenge button
                    Button { showNewChallenge = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Start a Challenge")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(NC.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NC.vPad)
                        .background(NC.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    }

                    // Completed Challenges
                    if !vm.completed.isEmpty {
                        completedSection
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Challenges")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showNewChallenge) {
                NewChallengeSheet(onCreate: { type, target, days in
                    Task {
                        await vm.create(type: type, target: target, days: days)
                        showNewChallenge = false
                    }
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task { await vm.load() }
            .refreshable { await vm.load() }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trophy")
                .font(.system(size: 40))
                .foregroundStyle(NC.teal.opacity(0.4))
            Text("No challenges yet")
                .font(.headline)
            Text("Challenge yourself with time-bound goals across spending, fitness, and habits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - Active Challenges

    private var activeChallengesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Active Challenges")
                    .font(.subheadline.bold())
            }

            ForEach(vm.active) { item in
                ActiveChallengeCard(item: item, onDelete: {
                    Task { await vm.delete(id: item.challenge.id) }
                })
            }
        }
    }

    // MARK: - Completed Section

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Completed")
                    .font(.subheadline.bold())
            }

            ForEach(vm.completed) { item in
                CompletedChallengeCard(item: item)
            }
        }
    }
}

// MARK: - Active Challenge Card

private struct ActiveChallengeCard: View {
    let item: ChallengeProgress
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: item.challenge.type.icon)
                    .font(.title3)
                    .foregroundStyle(NC.teal)
                    .frame(width: NC.iconSize, height: NC.iconSize)
                    .background(NC.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: NC.iconRadius))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.challenge.title)
                        .font(.subheadline.bold())
                    Text("\(item.daysRemaining) day\(item.daysRemaining == 1 ? "" : "s") remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(role: .destructive) { onDelete() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            // Progress bar
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: max(0, geo.size.width * item.progress), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(progressLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(item.progress * 100))%")
                        .font(.caption2.bold())
                        .foregroundStyle(progressColor)
                }
            }
        }
        .card()
    }

    private var progressColor: Color {
        if item.progress >= 1.0 { return .green }
        if item.progress >= 0.5 { return NC.teal }
        return .orange
    }

    private var progressLabel: String {
        let c = item.challenge
        let current = Int(c.currentValue)
        let target = Int(c.targetValue)
        return "\(current) / \(target) \(c.type.unit)"
    }
}

// MARK: - Completed Challenge Card

private struct CompletedChallengeCard: View {
    let item: ChallengeProgress

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.challenge.type.icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: NC.iconSize, height: NC.iconSize)
                .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: NC.iconRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.challenge.title)
                    .font(.subheadline.bold())
                if let completed = item.challenge.completedAt {
                    Text("Completed \(completed, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(.green)
        }
        .card()
    }
}

// MARK: - New Challenge Sheet

private struct NewChallengeSheet: View {
    var onCreate: (ChallengeStore.ChallengeType, Double, Int) -> Void

    @State private var selectedType: ChallengeStore.ChallengeType = .noEatingOut
    @State private var targetValue: String = ""
    @State private var durationDays: Int = 7
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                // Challenge type picker
                Section("Challenge Type") {
                    ForEach(ChallengeStore.ChallengeType.allCases, id: \.rawValue) { type in
                        Button {
                            selectedType = type
                            targetValue = "\(Int(type.defaultTarget))"
                            durationDays = type.defaultDuration
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: type.icon)
                                    .font(.title3)
                                    .foregroundStyle(NC.teal)
                                    .frame(width: 32, height: 32)

                                Text(type.title)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if selectedType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NC.teal)
                                }
                            }
                        }
                    }
                }

                // Target value
                Section("Target") {
                    HStack {
                        TextField("Target", text: $targetValue)
                            .keyboardType(.numberPad)
                        Text(selectedType.unit)
                            .foregroundStyle(.secondary)
                    }
                }

                // Duration
                Section("Duration") {
                    Picker("Days", selection: $durationDays) {
                        Text("3 days").tag(3)
                        Text("5 days").tag(5)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("21 days").tag(21)
                        Text("30 days").tag(30)
                    }
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let target = Double(targetValue) ?? selectedType.defaultTarget
                        onCreate(selectedType, target, durationDays)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(NC.teal)
                }
            }
            .onAppear {
                targetValue = "\(Int(selectedType.defaultTarget))"
                durationDays = selectedType.defaultDuration
            }
        }
    }
}

// MARK: - View Model

struct ChallengeProgress: Identifiable {
    var id: String { challenge.id }
    let challenge: ChallengeStore.Challenge
    let progress: Double
    let daysRemaining: Int
}

@MainActor
class ChallengesViewModel: ObservableObject {
    @Published var active: [ChallengeProgress] = []
    @Published var completed: [ChallengeProgress] = []

    func load() async {
        let store = ChallengeStore.shared
        await store.updateProgress()

        let activeList = await store.activeChallenges()
        let completedList = await store.completedChallenges()

        active = await activeList.asyncMap { challenge in
            let prog = await store.progress(for: challenge)
            let days = await store.daysRemaining(for: challenge)
            return ChallengeProgress(challenge: challenge, progress: prog, daysRemaining: days)
        }

        completed = completedList.map { challenge in
            ChallengeProgress(challenge: challenge, progress: 1.0, daysRemaining: 0)
        }
    }

    func create(type: ChallengeStore.ChallengeType, target: Double, days: Int) async {
        await ChallengeStore.shared.createChallenge(type: type, target: target, days: days)
        await load()
    }

    func delete(id: String) async {
        await ChallengeStore.shared.deleteChallenge(id: id)
        await load()
    }
}

// MARK: - Async Map Helper

private extension Array {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}
