import SwiftUI

// MARK: - Goals Tab / Sheet

struct GoalsView: View {
    @StateObject private var vm = GoalsViewModel()
    @State private var showAddGoal = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Active goals with progress
                    if vm.progress.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.progress) { item in
                            GoalCard(item: item, onRemove: {
                                Task { await vm.remove(goalId: item.goal.id) }
                            })
                        }
                    }

                    // Add goal button
                    Button { showAddGoal = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add a Goal")
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                        .foregroundStyle(NC.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, NC.vPad)
                        .background(NC.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showAddGoal) {
                AddGoalSheet(onAdd: { type, value in
                    Task {
                        await vm.add(type: type, target: value)
                        showAddGoal = false
                    }
                })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task { await vm.load() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 40))
                .foregroundStyle(NC.teal.opacity(0.4))
            Text("No goals yet")
                .font(.headline)
            Text("Set goals and NodeCompass will track them automatically using your spending, health, and food data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }
}

// MARK: - Goal Card

private struct GoalCard: View {
    let item: GoalProgress
    let onRemove: () -> Void
    @State private var showRemove = false

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                        .fill(pillarColor.opacity(0.12))
                        .frame(width: NC.iconSize, height: NC.iconSize)
                    Image(systemName: item.goal.type.icon)
                        .font(.subheadline)
                        .foregroundStyle(pillarColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.goal.type.title)
                        .font(.subheadline.bold())
                    Text("Target: \(item.goal.formattedTarget) \(item.goal.type.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(item.isOnTrack ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(item.statusText)
                        .font(.caption.bold())
                        .foregroundStyle(item.isOnTrack ? .green : .orange)
                }
            }

            // Progress bar
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 8)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(progressColor)
                            .frame(width: min(geo.size.width, geo.size.width * item.progress), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text(formattedCurrent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(min(item.progress, 1.0) * 100))%")
                        .font(.caption2.bold())
                        .foregroundStyle(progressColor)
                }
            }

            // Streak (if applicable)
            if item.streakDays > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(item.streakDays)-day streak")
                        .font(.caption2.bold())
                        .foregroundStyle(.orange)
                    Spacer()
                }
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .contextMenu {
            Button(role: .destructive) { showRemove = true } label: {
                Label("Remove Goal", systemImage: "trash")
            }
        }
        .alert("Remove Goal?", isPresented: $showRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    private var pillarColor: Color {
        switch item.goal.type.pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "food": return NC.food
        default: return .blue
        }
    }

    private var progressColor: Color {
        if item.goal.type.lowerIsBetter {
            return item.progress <= 1.0 ? .green : NC.spend
        }
        return item.progress >= 1.0 ? .green : (item.isOnTrack ? NC.teal : .orange)
    }

    private var formattedCurrent: String {
        switch item.goal.type {
        case .spending, .savings:
            return "₹\(Int(item.currentValue).formatted())"
        case .sleep:
            return String(format: "%.1f hrs", item.currentValue)
        case .steps:
            return "\(Int(item.currentValue).formatted()) steps"
        case .calories:
            return "\(Int(item.currentValue)) kcal"
        default:
            return "\(Int(item.currentValue))x"
        }
    }
}

// MARK: - Add Goal Sheet

private struct AddGoalSheet: View {
    let onAdd: (GoalType, Double) -> Void
    @State private var selectedType: GoalType?
    @State private var targetValue: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let type = selectedType {
                        // Step 2: Set target
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(pillarColor(type).opacity(0.1))
                                    .frame(width: 80, height: 80)
                                Image(systemName: type.icon)
                                    .font(.title)
                                    .foregroundStyle(pillarColor(type))
                            }

                            Text(type.title)
                                .font(.title3.bold())

                            // Presets
                            VStack(spacing: 10) {
                                Text("Choose a target")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(type.presets, id: \.self) { preset in
                                        Button {
                                            targetValue = preset
                                        } label: {
                                            Text(formatPreset(preset, type: type))
                                                .font(.subheadline.bold())
                                                .foregroundStyle(targetValue == preset ? .white : .primary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(
                                                    targetValue == preset
                                                        ? AnyShapeStyle(pillarColor(type))
                                                        : AnyShapeStyle(Color(.systemGray5)),
                                                    in: RoundedRectangle(cornerRadius: NC.iconRadius)
                                                )
                                        }
                                    }
                                }
                            }

                            // Unit label
                            Text(type.unit)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            // Confirm
                            Button {
                                onAdd(type, targetValue > 0 ? targetValue : type.defaultValue)
                            } label: {
                                Text("Set Goal")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(pillarColor(type), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                            }
                            .disabled(targetValue == 0)
                        }
                        .padding(.top, 20)
                    } else {
                        // Step 1: Choose type
                        ForEach(GoalType.allCases, id: \.self) { type in
                            Button {
                                selectedType = type
                                targetValue = type.defaultValue
                            } label: {
                                HStack(spacing: 14) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                                            .fill(pillarColor(type).opacity(0.12))
                                            .frame(width: NC.iconSize, height: NC.iconSize)
                                        Image(systemName: type.icon)
                                            .font(.subheadline)
                                            .foregroundStyle(pillarColor(type))
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(type.title)
                                            .font(.subheadline.bold())
                                            .foregroundStyle(.primary)
                                        Text("Default: \(formatPreset(type.defaultValue, type: type)) \(type.unit)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, NC.hPad)
                                .padding(.vertical, NC.vPad)
                            }

                            if type != GoalType.allCases.last {
                                Divider().padding(.leading, NC.dividerIndent)
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    }
                }
                .padding(.horizontal, NC.hPad)
            }
            .navigationTitle(selectedType == nil ? "Add Goal" : "Set Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if selectedType != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Back") { selectedType = nil }
                    }
                }
            }
        }
    }

    private func pillarColor(_ type: GoalType) -> Color {
        switch type.pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "food": return NC.food
        default: return .blue
        }
    }

    private func formatPreset(_ value: Double, type: GoalType) -> String {
        switch type {
        case .spending, .savings: return "₹\(Int(value).formatted())"
        case .sleep: return String(format: "%.1f", value)
        case .steps: return "\(Int(value).formatted())"
        default: return "\(Int(value))"
        }
    }
}

// MARK: - ViewModel

@MainActor
class GoalsViewModel: ObservableObject {
    @Published var progress: [GoalProgress] = []

    func load() async {
        progress = await GoalStore.shared.progressForAll()
    }

    func add(type: GoalType, target: Double) async {
        await GoalStore.shared.addGoal(type: type, target: target)
        await load()
    }

    func remove(goalId: String) async {
        await GoalStore.shared.removeGoal(goalId: goalId)
        await load()
    }
}
