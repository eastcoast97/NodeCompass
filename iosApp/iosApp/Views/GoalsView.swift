import SwiftUI

// MARK: - Goals View — unified entry for recurring goals and named savings targets

struct GoalsView: View {
    @StateObject private var vm = GoalsViewModel()
    @State private var addSheet: AddSheetKind?

    enum AddSheetKind: Identifiable {
        case picker
        case recurring
        case savingsTarget
        var id: Int {
            switch self {
            case .picker: return 0
            case .recurring: return 1
            case .savingsTarget: return 2
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: Savings targets (named, deadline-driven)
                if !vm.activeSavings.isEmpty {
                    Section {
                        ForEach(vm.activeSavings) { progress in
                            SavingsTargetCard(
                                progress: progress,
                                onComplete: { Task { await vm.completeSavings(id: progress.goal.id) } },
                                onDelete:   { Task { await vm.deleteSavings(id: progress.goal.id) } }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: NC.hPad, bottom: 4, trailing: NC.hPad))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await vm.deleteSavings(id: progress.goal.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                                Button {
                                    Task { await vm.completeSavings(id: progress.goal.id) }
                                } label: { Label("Complete", systemImage: "checkmark.circle") }
                                .tint(.green)
                            }
                        }
                    } header: {
                        sectionHeader("Savings Targets", systemImage: "banknote.fill")
                    }
                }

                // MARK: Recurring goals (auto-tracked from data)
                if !vm.recurring.isEmpty {
                    Section {
                        ForEach(vm.recurring) { item in
                            RecurringGoalCard(item: item, onRemove: {
                                Task { await vm.removeRecurring(goalId: item.goal.id) }
                            })
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: NC.hPad, bottom: 4, trailing: NC.hPad))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await vm.removeRecurring(goalId: item.goal.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    } header: {
                        sectionHeader("Recurring Goals", systemImage: "target")
                    }
                }

                // MARK: Completed savings (collapsed footer)
                if !vm.completedSavings.isEmpty {
                    Section {
                        ForEach(vm.completedSavings) { progress in
                            CompletedSavingsRow(progress: progress, onDelete: {
                                Task { await vm.deleteSavings(id: progress.goal.id) }
                            })
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: NC.hPad, bottom: 4, trailing: NC.hPad))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await vm.deleteSavings(id: progress.goal.id) }
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    } header: {
                        sectionHeader("Completed", systemImage: "checkmark.seal.fill")
                    }
                }

                // Empty state
                if vm.isEmpty {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: NC.hPad, bottom: 4, trailing: NC.hPad))
                }

                // Add button
                Button { addSheet = .picker } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add a Goal").fontWeight(.medium)
                    }
                    .font(.subheadline)
                    .foregroundStyle(NC.teal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NC.vPad)
                    .background(NC.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: NC.hPad, bottom: 4, trailing: NC.hPad))
            }
            .listStyle(.plain)
            .background(Color(.systemGroupedBackground))
            .scrollContentBackground(.hidden)
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
            .sheet(item: $addSheet) { kind in
                switch kind {
                case .picker:
                    AddGoalPickerSheet(
                        onPickRecurring: { addSheet = .recurring },
                        onPickSavings:   { addSheet = .savingsTarget }
                    )
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                case .recurring:
                    AddRecurringGoalSheet { type, value in
                        Task {
                            await vm.addRecurring(type: type, target: value)
                            addSheet = nil
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                case .savingsTarget:
                    AddSavingsTargetSheet { name, target, deadline, icon in
                        Task {
                            await vm.addSavings(name: name, target: target, deadline: deadline, icon: icon)
                            addSheet = nil
                        }
                    }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption)
                .foregroundStyle(NC.teal)
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "target")
                .font(.system(size: 40))
                .foregroundStyle(NC.teal.opacity(0.4))
            Text("No goals yet")
                .font(.headline)
            Text("Set savings targets or recurring habits — NodeCompass tracks progress automatically from your data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
        .frame(maxWidth: .infinity)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }
}

// MARK: - Recurring Goal Card

private struct RecurringGoalCard: View {
    let item: GoalProgress
    let onRemove: () -> Void
    @State private var showRemove = false

    var body: some View {
        VStack(spacing: 12) {
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

                HStack(spacing: 4) {
                    Circle()
                        .fill(item.isOnTrack ? .green : .orange)
                        .frame(width: 6, height: 6)
                    Text(item.statusText)
                        .font(.caption.bold())
                        .foregroundStyle(item.isOnTrack ? .green : .orange)
                }

                Button { showRemove = true } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5), in: Circle())
                }
            }

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
        case "food":   return NC.food
        default:       return .blue
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
        case .spending, .savings: return NC.money(item.currentValue)
        case .sleep:    return String(format: "%.1f hrs", item.currentValue)
        case .steps:    return "\(Int(item.currentValue).formatted()) steps"
        case .calories: return "\(Int(item.currentValue)) kcal"
        default:        return "\(Int(item.currentValue))x"
        }
    }
}

// MARK: - Savings Target Card (named, deadline-driven)

private struct SavingsTargetCard: View {
    let progress: SavingsGoalStore.SavingsProgress
    let onComplete: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
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
                    Text("\(NC.money(progress.currentSaved)) of \(NC.money(progress.goal.targetAmount))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                progressRing(percentage: progress.percentage)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: progress.isOnTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(progress.isOnTrack ? "On Track" : "Behind")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(progress.isOnTrack ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                .foregroundStyle(progress.isOnTrack ? .green : .orange)
                .clipShape(Capsule())

                if progress.monthlyRequired > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle")
                            .font(.caption)
                        Text("\(NC.money(progress.monthlyRequired))/mo")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(NC.teal.opacity(0.1))
                    .foregroundStyle(NC.teal)
                    .clipShape(Capsule())
                }

                Spacer()

                if let deadline = progress.goal.deadline {
                    let months = Calendar.current.dateComponents([.month], from: Date(), to: deadline).month ?? 0
                    Text(months > 0 ? "\(months) mo left" : "Due now")
                        .font(.caption)
                        .foregroundStyle(months > 0 ? Color.secondary : Color.red)
                }
            }

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

            if progress.dailySuggested > 0 && !progress.goal.isCompleted {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                    Text("Save \(NC.money(progress.dailySuggested))/day to stay on track")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .contextMenu {
            Button { onComplete() } label: {
                Label("Mark Complete", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete Goal", systemImage: "trash")
            }
        }
    }

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
}

// MARK: - Completed Savings Row

private struct CompletedSavingsRow: View {
    let progress: SavingsGoalStore.SavingsProgress
    let onDelete: () -> Void

    var body: some View {
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
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        .opacity(0.85)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Goal Picker

private struct AddGoalPickerSheet: View {
    let onPickRecurring: () -> Void
    let onPickSavings: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                pickerCard(
                    icon: "banknote.fill",
                    title: "Savings Target",
                    subtitle: "Save toward a named goal with a deadline",
                    color: NC.teal,
                    action: onPickSavings
                )
                pickerCard(
                    icon: "target",
                    title: "Recurring Goal",
                    subtitle: "Auto-tracked from spending, health, or food data",
                    color: .blue,
                    action: onPickRecurring
                )
                Spacer()
            }
            .padding(NC.hPad)
            .navigationTitle("Add a Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func pickerCard(icon: String, title: String, subtitle: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(NC.hPad)
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Recurring Goal

private struct AddRecurringGoalSheet: View {
    let onAdd: (GoalType, Double) -> Void
    @State private var selectedType: GoalType?
    @State private var targetValue: Double = 0
    @State private var customValueText: String = ""
    @State private var useCustom: Bool = false
    @FocusState private var customFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let type = selectedType {
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(pillarColor(type).opacity(0.1))
                                    .frame(width: 80, height: 80)
                                Image(systemName: type.icon)
                                    .font(.title)
                                    .foregroundStyle(pillarColor(type))
                            }

                            Text(type.title).font(.title3.bold())

                            VStack(spacing: 10) {
                                Text("Quick select")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                    ForEach(type.presets, id: \.self) { preset in
                                        Button {
                                            useCustom = false
                                            customValueText = ""
                                            targetValue = preset
                                        } label: {
                                            Text(formatPreset(preset, type: type))
                                                .font(.subheadline.bold())
                                                .foregroundStyle(!useCustom && targetValue == preset ? .white : .primary)
                                                .frame(maxWidth: .infinity)
                                                .padding(.vertical, 12)
                                                .background(
                                                    !useCustom && targetValue == preset
                                                        ? AnyShapeStyle(pillarColor(type))
                                                        : AnyShapeStyle(Color(.systemGray5)),
                                                    in: RoundedRectangle(cornerRadius: NC.iconRadius)
                                                )
                                        }
                                    }
                                }
                            }

                            VStack(spacing: 8) {
                                Text("Or set your own")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 8) {
                                    if type == .spending || type == .savings {
                                        Text(NC.currencySymbol)
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                    }
                                    TextField(formatPreset(type.defaultValue, type: type), text: $customValueText)
                                        .font(.title3.bold())
                                        .keyboardType(type == .sleep ? .decimalPad : .numberPad)
                                        .focused($customFieldFocused)
                                        .onChange(of: customValueText) {
                                            if let val = Double(customValueText), val > 0 {
                                                useCustom = true
                                                targetValue = val
                                            }
                                        }
                                    Text(type.unit)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: NC.iconRadius)
                                        .stroke(useCustom ? pillarColor(type) : Color(.systemGray4),
                                                lineWidth: useCustom ? 2 : 1)
                                )
                            }

                            Button {
                                let finalValue = targetValue > 0 ? targetValue : type.defaultValue
                                onAdd(type, finalValue)
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
            .navigationTitle(selectedType == nil ? "Recurring Goal" : "Set Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedType == nil ? "Cancel" : "Back") {
                        if selectedType == nil { dismiss() } else { selectedType = nil }
                    }
                }
            }
        }
    }

    private func pillarColor(_ type: GoalType) -> Color {
        switch type.pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "food":   return NC.food
        default:       return .blue
        }
    }

    private func formatPreset(_ value: Double, type: GoalType) -> String {
        switch type {
        case .spending, .savings: return NC.money(value)
        case .sleep: return String(format: "%.1f", value)
        case .steps: return "\(Int(value).formatted())"
        default:     return "\(Int(value))"
        }
    }
}

// MARK: - Add Savings Target

private struct AddSavingsTargetSheet: View {
    let onAdd: (_ name: String, _ target: Double, _ deadline: Date?, _ icon: String) -> Void
    @State private var name = ""
    @State private var targetText = ""
    @State private var deadline: Date = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
    @State private var hasDeadline = true
    @State private var icon = "star.fill"
    @Environment(\.dismiss) private var dismiss

    static let iconOptions = [
        "star.fill", "airplane", "house.fill", "car.fill", "graduationcap.fill",
        "gift.fill", "heart.fill", "laptopcomputer", "iphone", "bicycle",
        "camera.fill", "music.note", "leaf.fill", "cross.case.fill", "banknote.fill",
        "trophy.fill", "flag.fill", "sun.max.fill", "pawprint.fill", "gamecontroller.fill"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal name (e.g., Vacation to Bali)", text: $name)

                    HStack {
                        Text(NC.currencySymbol).foregroundStyle(.secondary)
                        TextField("Target amount", text: $targetText)
                            .keyboardType(.decimalPad)
                    }

                    Toggle("Set deadline", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                    }
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(Self.iconOptions, id: \.self) { option in
                            Button { icon = option } label: {
                                ZStack {
                                    Circle()
                                        .fill(icon == option ? NC.teal.opacity(0.2) : Color(.systemGray6))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: option)
                                        .font(.system(size: 18))
                                        .foregroundStyle(icon == option ? NC.teal : .secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("New Savings Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let target = Double(targetText), !name.isEmpty, target > 0 else { return }
                        onAdd(name, target, hasDeadline ? deadline : nil, icon)
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(NC.teal)
                    .disabled(name.isEmpty || Double(targetText) == nil)
                }
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class GoalsViewModel: ObservableObject {
    @Published var recurring: [GoalProgress] = []
    @Published var savingsAll: [SavingsGoalStore.SavingsProgress] = []

    var activeSavings:    [SavingsGoalStore.SavingsProgress] { savingsAll.filter { !$0.goal.isCompleted } }
    var completedSavings: [SavingsGoalStore.SavingsProgress] { savingsAll.filter {  $0.goal.isCompleted } }

    var isEmpty: Bool { recurring.isEmpty && savingsAll.isEmpty }

    func load() async {
        async let r = GoalStore.shared.progressForAll()
        async let s = SavingsGoalStore.shared.progressForAll()
        let (rec, sav) = await (r, s)
        recurring = rec
        savingsAll = sav
    }

    // Recurring goals
    func addRecurring(type: GoalType, target: Double) async {
        await GoalStore.shared.addGoal(type: type, target: target)
        await load()
    }

    func removeRecurring(goalId: String) async {
        await GoalStore.shared.removeGoal(goalId: goalId)
        await load()
    }

    // Savings targets
    func addSavings(name: String, target: Double, deadline: Date?, icon: String) async {
        await SavingsGoalStore.shared.addGoal(name: name, target: target, deadline: deadline, icon: icon)
        await load()
    }

    func deleteSavings(id: String) async {
        await SavingsGoalStore.shared.deleteGoal(id: id)
        await load()
    }

    func completeSavings(id: String) async {
        await SavingsGoalStore.shared.markComplete(id: id)
        await load()
    }
}
