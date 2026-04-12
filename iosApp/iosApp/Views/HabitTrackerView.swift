import SwiftUI

/// Full-screen habit tracker — toggle daily habits, view streaks, add new ones.
struct HabitTrackerView: View {
    @State private var habits: [HabitStore.Habit] = []
    @State private var completedIds: Set<String> = []
    @State private var streaks: [String: Int] = [:]
    @State private var completed = 0
    @State private var total = 0
    @State private var showAddSheet = false
    @State private var bounceId: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    todayHeader
                    habitList
                    if habits.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Habits")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddSheet = true } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(NC.teal)
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddHabitSheet(onAdded: { await reload() })
            }
            .task { await reload() }
        }
    }

    // MARK: - Today Header with Progress Ring

    private var todayHeader: some View {
        VStack(spacing: 12) {
            Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                    .frame(width: 90, height: 90)

                Circle()
                    .trim(from: 0, to: progressFraction)
                    .stroke(NC.teal, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 90, height: 90)
                    .animation(.spring(response: 0.5), value: progressFraction)

                VStack(spacing: 2) {
                    Text("\(completed)/\(total)")
                        .font(.title3.bold().monospacedDigit())
                    Text("done")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if total > 0 && completed == total {
                Text("All done today!")
                    .font(.subheadline.bold())
                    .foregroundStyle(NC.teal)
            }
        }
        .card()
    }

    private var progressFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(completed) / CGFloat(total)
    }

    // MARK: - Habit List

    private var habitList: some View {
        LazyVStack(spacing: 10) {
            ForEach(habits) { habit in
                habitRow(habit)
            }
        }
    }

    private func habitRow(_ habit: HabitStore.Habit) -> some View {
        let isDone = completedIds.contains(habit.id)
        let streak = streaks[habit.id] ?? 0
        let color = colorFor(habit.color)

        return Button {
            Task {
                Haptic.medium()
                await HabitStore.shared.toggleHabit(id: habit.id, date: Date())
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    bounceId = habit.id
                }
                await reload()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    bounceId = nil
                }
            }
        } label: {
            HStack(spacing: 14) {
                // Checkbox
                ZStack {
                    Circle()
                        .stroke(isDone ? color : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 28, height: 28)

                    if isDone {
                        Circle()
                            .fill(color)
                            .frame(width: 28, height: 28)

                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(bounceId == habit.id ? 1.2 : 1.0)

                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: NC.iconSize, height: NC.iconSize)

                    Image(systemName: habit.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }

                // Name + streak
                VStack(alignment: .leading, spacing: 3) {
                    Text(habit.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isDone ? .secondary : .primary)
                        .strikethrough(isDone, color: .secondary)

                    if streak > 0 {
                        Text("\u{1F525} \(streak) day\(streak == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()

                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .card()
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task {
                    await HabitStore.shared.deleteHabit(id: habit.id)
                    await reload()
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        // Wrap in a contextMenu for swipe-to-delete since LazyVStack
        // doesn't support .swipeActions natively — provide long-press fallback.
        .contextMenu {
            Button(role: .destructive) {
                Task {
                    await HabitStore.shared.deleteHabit(id: habit.id)
                    await reload()
                }
            } label: {
                Label("Delete Habit", systemImage: "trash")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.dashed")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No habits yet")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Start building better routines.\nTap + to add your first habit.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Button {
                showAddSheet = true
            } label: {
                Label("Add Habit", systemImage: "plus")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(NC.teal, in: Capsule())
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Reload

    private func reload() async {
        let store = HabitStore.shared
        habits = await store.allHabits()
        let progress = await store.todayProgress()
        completed = progress.completed
        total = progress.total

        var ids: Set<String> = []
        var stks: [String: Int] = [:]
        for h in habits {
            if await store.isCompleted(habitId: h.id, date: Date()) {
                ids.insert(h.id)
            }
            stks[h.id] = await store.streak(for: h.id)
        }
        completedIds = ids
        streaks = stks
    }

    // MARK: - Color Helper

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "teal": return NC.teal
        case "pink": return .pink
        case "orange": return .orange
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        default: return NC.teal
        }
    }
}

// MARK: - Add Habit Sheet

private struct AddHabitSheet: View {
    let onAdded: () async -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selectedIcon = "star.fill"
    @State private var selectedColor = "teal"
    @FocusState private var nameFieldFocused: Bool

    private let iconOptions = [
        "star.fill", "heart.fill", "brain.head.profile", "book.fill",
        "figure.run", "fork.knife", "leaf.fill", "drop.fill",
        "moon.fill", "sun.max.fill", "note.text", "cart.badge.minus",
        "figure.walk", "dumbbell.fill", "cup.and.saucer.fill",
        "paintbrush.fill", "music.note", "globe.americas.fill",
        "phone.down.fill", "alarm.fill",
    ]

    private let colorOptions = ["teal", "pink", "orange", "blue", "purple", "green"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Custom habit
                    customSection

                    dividerLine

                    // Suggestions
                    suggestionsSection
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task {
                            await HabitStore.shared.addHabit(
                                name: name.trimmingCharacters(in: .whitespaces),
                                icon: selectedIcon,
                                color: selectedColor
                            )
                            await onAdded()
                            dismiss()
                        }
                    }
                    .font(.headline)
                    .foregroundStyle(NC.teal)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Custom Habit Section

    private var customSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Your Own")
                .font(.headline)

            // Name field
            TextField("Habit name", text: $name)
                .focused($nameFieldFocused)
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onAppear { nameFieldFocused = true }

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
                    ForEach(iconOptions, id: \.self) { icon in
                        Button {
                            selectedIcon = icon
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selectedIcon == icon ? colorFor(selectedColor).opacity(0.2) : Color.gray.opacity(0.08))
                                    .frame(height: 44)

                                Image(systemName: icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(selectedIcon == icon ? colorFor(selectedColor) : .secondary)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(selectedIcon == icon ? colorFor(selectedColor) : .clear, lineWidth: 2)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(colorOptions, id: \.self) { colorName in
                        Button {
                            selectedColor = colorName
                        } label: {
                            Circle()
                                .fill(colorFor(colorName))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .strokeBorder(.white, lineWidth: selectedColor == colorName ? 3 : 0)
                                )
                                .shadow(color: selectedColor == colorName ? colorFor(colorName).opacity(0.4) : .clear, radius: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .card()
    }

    private var dividerLine: some View {
        HStack {
            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
            Text("or pick a suggestion")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .layoutPriority(1)
            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
        }
    }

    // MARK: - Suggestions Section

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggestions")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(HabitStore.suggestions, id: \.name) { suggestion in
                    Button {
                        Task {
                            await HabitStore.shared.addHabit(
                                name: suggestion.name,
                                icon: suggestion.icon,
                                color: suggestion.color
                            )
                            await onAdded()
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(colorFor(suggestion.color).opacity(0.12))
                                    .frame(width: 32, height: 32)

                                Image(systemName: suggestion.icon)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(colorFor(suggestion.color))
                            }

                            Text(suggestion.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()
                        }
                        .padding(10)
                        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Color Helper

    private func colorFor(_ name: String) -> Color {
        switch name {
        case "teal": return NC.teal
        case "pink": return .pink
        case "orange": return .orange
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        default: return NC.teal
        }
    }
}

#Preview {
    HabitTrackerView()
}
