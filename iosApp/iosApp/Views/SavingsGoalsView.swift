import SwiftUI

// MARK: - ViewModel

@MainActor
class SavingsGoalsViewModel: ObservableObject {
    @Published var progressItems: [SavingsGoalStore.SavingsProgress] = []
    @Published var isLoading = false
    @Published var showAddSheet = false

    // Add goal form fields
    @Published var newName = ""
    @Published var newTarget = ""
    @Published var newDeadline: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @Published var hasDeadline = true
    @Published var newIcon = "star.fill"

    var activeGoals: [SavingsGoalStore.SavingsProgress] {
        progressItems.filter { !$0.goal.isCompleted }
    }

    var completedGoals: [SavingsGoalStore.SavingsProgress] {
        progressItems.filter { $0.goal.isCompleted }
    }

    static let iconOptions = [
        "star.fill", "airplane", "house.fill", "car.fill", "graduationcap.fill",
        "gift.fill", "heart.fill", "laptopcomputer", "iphone", "bicycle",
        "camera.fill", "music.note", "leaf.fill", "cross.case.fill", "banknote.fill",
        "trophy.fill", "flag.fill", "sun.max.fill", "pawprint.fill", "gamecontroller.fill"
    ]

    func load() async {
        isLoading = true
        defer { isLoading = false }
        progressItems = await SavingsGoalStore.shared.progressForAll()
    }

    func addGoal() async {
        guard !newName.isEmpty, let target = Double(newTarget), target > 0 else { return }
        await SavingsGoalStore.shared.addGoal(
            name: newName,
            target: target,
            deadline: hasDeadline ? newDeadline : nil,
            icon: newIcon
        )
        resetForm()
        await load()
    }

    func deleteGoal(id: String) async {
        await SavingsGoalStore.shared.deleteGoal(id: id)
        await load()
    }

    func markComplete(id: String) async {
        await SavingsGoalStore.shared.markComplete(id: id)
        await load()
    }

    private func resetForm() {
        newName = ""
        newTarget = ""
        newDeadline = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        hasDeadline = true
        newIcon = "star.fill"
    }
}

// MARK: - View

struct SavingsGoalsView: View {
    @StateObject private var vm = SavingsGoalsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.progressItems.isEmpty {
                    ProgressView("Loading goals...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.progressItems.isEmpty {
                    emptyState
                } else {
                    goalsList
                }
            }
            .navigationTitle("Savings Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm.showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(NC.teal)
                    }
                }
            }
            .sheet(isPresented: $vm.showAddSheet) {
                addGoalSheet
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Goals List

    private var goalsList: some View {
        List {
            // Active goals
            if !vm.activeGoals.isEmpty {
                ForEach(vm.activeGoals) { progress in
                    goalCard(progress: progress)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: NC.hPad, bottom: 4, trailing: NC.hPad))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task { await vm.deleteGoal(id: progress.goal.id) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                Task { await vm.markComplete(id: progress.goal.id) }
                            } label: {
                                Label("Complete", systemImage: "checkmark.circle")
                            }
                            .tint(.green)
                        }
                }
            }

            // Completed goals
            if !vm.completedGoals.isEmpty {
                Section {
                    ForEach(vm.completedGoals) { progress in
                        completedGoalCard(progress: progress)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: NC.hPad, bottom: 4, trailing: NC.hPad))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await vm.deleteGoal(id: progress.goal.id) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("Completed")
                            .font(.headline)
                    }
                    .padding(.top, 8)
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Goal Card

    private func goalCard(progress: SavingsGoalStore.SavingsProgress) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    Circle()
                        .fill(NC.teal.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: progress.goal.icon)
                        .font(.system(size: 18))
                        .foregroundStyle(NC.teal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.goal.name)
                        .font(.headline)
                    Text("\(NC.money(progress.currentSaved)) saved of \(NC.money(progress.goal.targetAmount))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Progress ring
                progressRing(percentage: progress.percentage)
            }

            // Status badges
            HStack(spacing: 8) {
                // On track / behind badge
                HStack(spacing: 4) {
                    Image(systemName: progress.isOnTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(progress.isOnTrack ? "On Track" : "Behind")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(progress.isOnTrack ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                .foregroundStyle(progress.isOnTrack ? .green : .orange)
                .clipShape(Capsule())

                // Monthly required hint
                if progress.monthlyRequired > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle")
                            .font(.caption)
                        Text("Save \(NC.money(progress.monthlyRequired))/mo")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(NC.teal.opacity(0.1))
                    .foregroundStyle(NC.teal)
                    .clipShape(Capsule())
                }

                Spacer()

                // Deadline info
                if let deadline = progress.goal.deadline {
                    let months = Calendar.current.dateComponents([.month], from: Date(), to: deadline).month ?? 0
                    if months > 0 {
                        Text("\(months) mo left")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Due now")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(NC.teal.gradient)
                        .frame(width: max(0, geo.size.width * min(1.0, progress.percentage)), height: 6)
                }
            }
            .frame(height: 6)

            // Daily suggestion
            if progress.dailySuggested > 0 && !progress.goal.isCompleted {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Daily budget tip: save \(NC.money(progress.dailySuggested))/day to stay on track")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .card()
        .contextMenu {
            Button {
                Task { await vm.markComplete(id: progress.goal.id) }
            } label: {
                Label("Mark Complete", systemImage: "checkmark.circle")
            }

            Button(role: .destructive) {
                Task { await vm.deleteGoal(id: progress.goal.id) }
            } label: {
                Label("Delete Goal", systemImage: "trash")
            }
        }
    }

    // MARK: - Completed Goal Card

    private func completedGoalCard(progress: SavingsGoalStore.SavingsProgress) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: progress.goal.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.goal.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(color: .secondary.opacity(0.5))
                Text(NC.money(progress.goal.targetAmount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.title3)
                .foregroundStyle(.green)
        }
        .card(padding: 12)
        .opacity(0.8)
        .contextMenu {
            Button(role: .destructive) {
                Task { await vm.deleteGoal(id: progress.goal.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Progress Ring

    private func progressRing(percentage: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color(.systemGray5), lineWidth: 4)
                .frame(width: 48, height: 48)

            Circle()
                .trim(from: 0, to: min(1.0, percentage))
                .stroke(NC.teal, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: 48, height: 48)
                .rotationEffect(.degrees(-90))

            Text("\(Int(percentage * 100))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(NC.teal)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "target")
                .font(.system(size: 50))
                .foregroundStyle(NC.teal.opacity(0.5))
            Text("No Savings Goals Yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Set a target and track your progress automatically from your spending data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                vm.showAddSheet = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Add Your First Goal")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(NC.teal, in: Capsule())
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    // MARK: - Add Goal Sheet

    private var addGoalSheet: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal name (e.g., Vacation to Bali)", text: $vm.newName)

                    HStack {
                        Text(NC.currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("Target amount", text: $vm.newTarget)
                            .keyboardType(.decimalPad)
                    }

                    Toggle("Set deadline", isOn: $vm.hasDeadline)

                    if vm.hasDeadline {
                        DatePicker("Deadline", selection: $vm.newDeadline, in: Date()..., displayedComponents: .date)
                    }
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(SavingsGoalsViewModel.iconOptions, id: \.self) { icon in
                            Button {
                                vm.newIcon = icon
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(vm.newIcon == icon ? NC.teal.opacity(0.2) : Color(.systemGray6))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: icon)
                                        .font(.system(size: 18))
                                        .foregroundStyle(vm.newIcon == icon ? NC.teal : .secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Savings Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        vm.showAddSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await vm.addGoal()
                            vm.showAddSheet = false
                        }
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(NC.teal)
                    .disabled(vm.newName.isEmpty || Double(vm.newTarget) == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    SavingsGoalsView()
}
