import SwiftUI

// MARK: - Segment

private enum ChallengesSegment: String, CaseIterable, Identifiable {
    case active, catalog, completed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active:    return "Active"
        case .catalog:   return "Catalog"
        case .completed: return "Completed"
        }
    }
}

// MARK: - Root

/// Challenges hub — three tabs:
///   1. **Active** — in-progress challenges with progress rings
///   2. **Catalog** — 25 curated challenges across Wealth/Health/Mind/Cross,
///                    filterable by pillar, one-tap start
///   3. **Completed** — finished challenges with share-as-image button
///
/// Entry points unchanged (modal sheet from Dashboard/Mind/You). Landing tab
/// depends on state: Active if any exist, otherwise Catalog (avoids a
/// cold-start empty list).
struct ChallengesView: View {
    @StateObject private var vm = ChallengesViewModel()
    @State private var segment: ChallengesSegment = .catalog
    @State private var showCustomSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab segmented control
                Picker("", selection: $segment) {
                    ForEach(ChallengesSegment.allCases) { seg in
                        Text(seg.title).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 12)

                // Segment content
                Group {
                    switch segment {
                    case .active:    ActiveTab(vm: vm)
                    case .catalog:   CatalogTab(vm: vm, showCustomSheet: $showCustomSheet)
                    case .completed: CompletedTab(vm: vm)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: segment)
            }
            .background(NC.bgBase)
            .navigationTitle("Challenges")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCustomSheet) {
                NewChallengeSheet(onCreate: { type, target, days in
                    Task {
                        await vm.create(type: type, target: target, days: days)
                        showCustomSheet = false
                        segment = .active
                    }
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task {
                await vm.load()
                // Default landing tab: Active if any active challenges exist,
                // otherwise Catalog so the user sees something to start rather
                // than an empty list.
                segment = vm.active.isEmpty ? .catalog : .active
            }
            .refreshable { await vm.load() }
        }
    }
}

// MARK: - Active Tab

private struct ActiveTab: View {
    @ObservedObject var vm: ChallengesViewModel

    var body: some View {
        if vm.active.isEmpty {
            emptyState
        } else {
            // List (rather than ScrollView + LazyVStack) so that native
            // swipe-to-delete via `.swipeActions` works. `.plain` style +
            // hidden scroll background + clear row background lets the
            // Aurora dark canvas show through.
            List {
                ForEach(vm.active) { item in
                    ActiveChallengeCard(item: item)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: NC.hPad, bottom: 6, trailing: NC.hPad))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await vm.delete(id: item.challenge.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await vm.delete(id: item.challenge.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(NC.bgBase)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "flame")
                .font(.system(size: 40))
                .foregroundStyle(NC.teal.opacity(0.4))
            Text("No active challenges")
                .font(.headline)
                .foregroundStyle(NC.textPrimary)
            Text("Pick one from the Catalog tab and go.")
                .font(.caption)
                .foregroundStyle(NC.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Catalog Tab

private struct CatalogTab: View {
    @ObservedObject var vm: ChallengesViewModel
    @Binding var showCustomSheet: Bool
    @State private var selectedPillar: ChallengeStore.Pillar? = nil

    private var filteredEntries: [ChallengeCatalog.Entry] {
        if let p = selectedPillar {
            return ChallengeCatalog.forPillar(p)
        }
        return ChallengeCatalog.entries
    }

    var body: some View {
        VStack(spacing: 0) {
            // Pillar filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    FilterChip(
                        label: "All",
                        icon: "square.grid.2x2",
                        isSelected: selectedPillar == nil,
                        tint: NC.teal
                    ) { selectedPillar = nil }

                    ForEach(ChallengeStore.Pillar.allCases, id: \.self) { p in
                        FilterChip(
                            label: p.displayName,
                            icon: p.icon,
                            isSelected: selectedPillar == p,
                            tint: pillarColor(p)
                        ) {
                            selectedPillar = (selectedPillar == p) ? nil : p
                        }
                    }
                }
                .padding(.horizontal, NC.hPad)
            }
            .padding(.bottom, 12)

            // Entries
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredEntries) { entry in
                        CatalogEntryCard(
                            entry: entry,
                            isActive: vm.hasActive(catalogId: entry.id),
                            onStart: {
                                Task {
                                    await vm.start(from: entry)
                                }
                            }
                        )
                    }

                    // Custom challenge footer
                    Button {
                        showCustomSheet = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "slider.horizontal.3")
                            Text("Don't see what you want? Create custom →")
                                .font(.caption)
                        }
                        .foregroundStyle(NC.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - Completed Tab

private struct CompletedTab: View {
    @ObservedObject var vm: ChallengesViewModel
    @State private var sharingChallenge: ChallengeStore.Challenge?
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        Group {
            if vm.completed.isEmpty {
                emptyState
            } else {
                // List-based layout so swipe-to-delete works natively.
                List {
                    ForEach(vm.completed) { item in
                        CompletedChallengeCard(
                            item: item,
                            onShare: { prepareShare(for: item.challenge) }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 6, leading: NC.hPad, bottom: 6, trailing: NC.hPad))
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await vm.delete(id: item.challenge.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await vm.delete(id: item.challenge.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(NC.bgBase)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @MainActor
    private func prepareShare(for challenge: ChallengeStore.Challenge) {
        Task { @MainActor in
            // Look up the linked achievement (if any) so the share card can
            // render its name/icon alongside the challenge title.
            var achievement: AchievementEngine.Achievement? = nil
            if let type = challenge.unlockAchievement {
                let all = await AchievementEngine.shared.allAchievements()
                achievement = all.first { $0.type == type }
            }
            if let img = ChallengeShareCardRenderer.render(challenge: challenge, achievement: achievement) {
                shareImage = img
                showShareSheet = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "trophy")
                .font(.system(size: 40))
                .foregroundStyle(NC.insight.opacity(0.4))
            Text("No completions yet")
                .font(.headline)
                .foregroundStyle(NC.textPrimary)
            Text("Finish a challenge to unlock a badge and share your win.")
                .font(.caption)
                .foregroundStyle(NC.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Cards

private struct ActiveChallengeCard: View {
    let item: ChallengeProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                // Pillar-tinted icon
                Image(systemName: item.challenge.type.icon)
                    .font(.title3)
                    .foregroundStyle(pillarColor(item.challenge.pillar))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                    .background(
                        pillarColor(item.challenge.pillar).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: NC.iconRadius)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.challenge.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(NC.textPrimary)
                    if !item.challenge.subtitle.isEmpty {
                        Text(item.challenge.subtitle)
                            .font(.caption)
                            .foregroundStyle(NC.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("\(item.daysRemaining) day\(item.daysRemaining == 1 ? "" : "s") remaining")
                            .font(.caption)
                            .foregroundStyle(NC.textSecondary)
                    }
                }

                Spacer()

                // Progress ring
                ZStack {
                    Circle()
                        .stroke(NC.bgElevated, lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Circle()
                        .trim(from: 0, to: item.progress)
                        .stroke(pillarColor(item.challenge.pillar),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(item.progress * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(NC.textPrimary)
                }
            }

            HStack {
                Text(progressLabel)
                    .font(.caption2)
                    .foregroundStyle(NC.textSecondary)
                Spacer()
                Text("\(item.daysRemaining) day\(item.daysRemaining == 1 ? "" : "s") left")
                    .font(.caption2.bold())
                    .foregroundStyle(pillarColor(item.challenge.pillar))
            }
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var progressLabel: String {
        let c = item.challenge
        let current = Int(c.currentValue)
        let target = Int(c.targetValue)
        return "\(current) / \(target) \(c.type.unit)"
    }
}

private struct CatalogEntryCard: View {
    let entry: ChallengeCatalog.Entry
    let isActive: Bool
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: pillar icon + difficulty chip
            HStack(spacing: 8) {
                Image(systemName: entry.pillar.icon)
                    .font(.caption.bold())
                    .foregroundStyle(pillarColor(entry.pillar))
                Text(entry.pillar.displayName.uppercased())
                    .font(.caption2.bold())
                    .kerning(1)
                    .foregroundStyle(pillarColor(entry.pillar))
                Spacer()
                DifficultyChip(difficulty: entry.difficulty)
            }

            Text(entry.title)
                .font(.subheadline.bold())
                .foregroundStyle(NC.textPrimary)
                .multilineTextAlignment(.leading)

            Text(entry.subtitle)
                .font(.caption)
                .foregroundStyle(NC.textSecondary)
                .lineLimit(2)

            HStack {
                Label("\(entry.durationDays) days", systemImage: "calendar")
                    .font(.caption2)
                    .foregroundStyle(NC.textTertiary)
                Spacer()

                if isActive {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(pillarColor(entry.pillar))
                } else {
                    Button(action: onStart) {
                        Text("Start")
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(pillarColor(entry.pillar), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }
}

private struct CompletedChallengeCard: View {
    let item: ChallengeProgress
    var onShare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: achievementIcon)
                .font(.title2)
                .foregroundStyle(NC.insight)
                .frame(width: NC.iconSize, height: NC.iconSize)
                .background(NC.insight.opacity(0.12), in: RoundedRectangle(cornerRadius: NC.iconRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.challenge.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(NC.textPrimary)
                if let completed = item.challenge.completedAt {
                    Text("Completed \(completed, style: .date)")
                        .font(.caption)
                        .foregroundStyle(NC.textSecondary)
                }
            }

            Spacer()

            Button(action: onShare) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title3)
                    .foregroundStyle(NC.teal)
                    .frame(width: 36, height: 36)
                    .background(NC.teal.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(NC.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    private var achievementIcon: String {
        item.challenge.unlockAchievement?.icon ?? "checkmark.seal.fill"
    }
}

// MARK: - Small Helpers

private struct FilterChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2.bold())
                Text(label)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? tint : NC.bgElevated,
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : NC.textSecondary)
        }
        .buttonStyle(.plain)
    }
}

private struct DifficultyChip: View {
    let difficulty: ChallengeStore.Difficulty

    var body: some View {
        Text(difficulty.displayName)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch difficulty {
        case .easy:   return NC.wealth
        case .medium: return NC.insight
        case .hard:   return NC.health
        }
    }
}

/// Pillar → display colour. Lives at file scope so every sub-view can use it.
private func pillarColor(_ pillar: ChallengeStore.Pillar) -> Color {
    switch pillar {
    case .wealth: return NC.wealth
    case .health: return NC.health
    case .mind:   return NC.mind
    case .cross:  return NC.insight
    }
}

// MARK: - New Challenge Sheet (kept for custom path from Catalog footer)

private struct NewChallengeSheet: View {
    var onCreate: (ChallengeStore.ChallengeType, Double, Int) -> Void

    @State private var selectedType: ChallengeStore.ChallengeType = .noEatingOut
    @State private var targetValue: String = ""
    @State private var durationDays: Int = 7
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
                                Text(type.title).foregroundStyle(.primary)
                                Spacer()
                                if selectedType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NC.teal)
                                }
                            }
                        }
                    }
                }

                Section("Target") {
                    HStack {
                        TextField("Target", text: $targetValue)
                            .keyboardType(.numberPad)
                        Text(selectedType.unit).foregroundStyle(.secondary)
                    }
                }

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
            .navigationTitle("Custom Challenge")
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
    @Published var activeCatalogIds: Set<String> = []

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

        activeCatalogIds = Set(activeList.compactMap { $0.catalogId })
    }

    func hasActive(catalogId: String) -> Bool {
        activeCatalogIds.contains(catalogId)
    }

    func start(from entry: ChallengeCatalog.Entry) async {
        _ = await ChallengeStore.shared.startFromCatalog(entry)
        await load()
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
