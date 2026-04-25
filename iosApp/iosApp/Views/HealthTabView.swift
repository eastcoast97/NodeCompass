import SwiftUI

// MARK: - Health Tab View

/// The "Health" pillar hub — consolidates mood, food, habits, steps, sleep, and activity
/// into one warm, encouraging dashboard.
struct HealthTabView: View {
    // MARK: - State

    @State private var steps: Int = 0
    @State private var activeCalories: Int = 0
    @State private var sleepHours: Double = 0
    @State private var restingHR: Int = 0

    @State private var todayMood: MoodStore.MoodEntry?
    @State private var foodEntries: [FoodStore.FoodLogEntry] = []
    @State private var foodCalories: Int = 0

    @State private var habits: [HabitStore.Habit] = []
    @State private var completedHabitIds: Set<String> = []
    @State private var habitStreaks: [String: Int] = [:]

    @State private var weeklySteps: [Int] = Array(repeating: 0, count: 7)

    @State private var showFoodLog = false
    @State private var showHabitTracker = false
    @State private var showMoodHistory = false

    // Goals (sensible defaults)
    private let stepGoal = 10_000
    private let calorieGoal = 500
    private let sleepGoal: Double = 8.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DiscoveryTip(
                        id: "health",
                        icon: "heart.fill",
                        title: "Health Intelligence",
                        message: "Steps, workouts, sleep, and food — synced from Apple Health. Your habits get auto-tracked when data confirms them.",
                        accentColor: .pink
                    )

                    healthRingsCard
                        .sectionAppear(delay: 0.05)
                    moodCheckInCard
                        .sectionAppear(delay: 0.1)
                    foodLogCard
                        .sectionAppear(delay: 0.15)
                    quickActionsRow
                        .sectionAppear(delay: 0.2)
                    habitsProgressCard
                        .sectionAppear(delay: 0.25)
                    weeklyActivityCard
                        .sectionAppear(delay: 0.35)
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(NC.bgBase)
            .navigationTitle("Health")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadAllData() }
            .refreshable { await loadAllData() }
            .sheet(isPresented: $showFoodLog) {
                FoodLogView()
            }
            .sheet(isPresented: $showHabitTracker) {
                HabitTrackerView()
            }
        }
    }

    // MARK: - 1. Health Rings (Hero Card)

    private var healthRingsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                Text("Today's Health")
                    .font(.headline)
                Spacer()
            }

            HStack(spacing: 24) {
                ringView(
                    value: Double(steps),
                    goal: Double(stepGoal),
                    color: .pink,
                    icon: "figure.walk",
                    label: "\(steps.formatted())",
                    subtitle: "Steps"
                )

                ringView(
                    value: Double(activeCalories),
                    goal: Double(calorieGoal),
                    color: .orange,
                    icon: "flame.fill",
                    label: "\(activeCalories)",
                    subtitle: "Cal"
                )

                ringView(
                    value: sleepHours,
                    goal: sleepGoal,
                    color: .indigo,
                    icon: "bed.double.fill",
                    label: String(format: "%.1fh", sleepHours),
                    subtitle: "Sleep"
                )
            }

            if restingHR > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.pink.opacity(0.7))
                    Text("Resting HR: \(restingHR) bpm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .card()
    }

    private func ringView(value: Double, goal: Double, color: Color, icon: String, label: String, subtitle: String) -> some View {
        let progress = min(value / max(goal, 1), 1.0)

        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 8)
                    .frame(width: 70, height: 70)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)

                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }

            Text(label)
                .font(.subheadline)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 2. Mood Check-In

    private var moodCheckInCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundStyle(.pink)
                Text(todayMood == nil ? "How are you feeling?" : "Today's Mood")
                    .font(.headline)
                Spacer()
            }

            if let mood = todayMood {
                // Already logged — show today's mood
                HStack(spacing: 12) {
                    Text(mood.mood.emoji)
                        .font(.system(size: 36))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Feeling \(mood.mood.label)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if let note = mood.note, !note.isEmpty {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                // Mood picker row
                HStack(spacing: 0) {
                    ForEach(MoodStore.MoodLevel.allCases, id: \.rawValue) { level in
                        Button {
                            Haptic.light()
                            Task { await logMood(level) }
                        } label: {
                            VStack(spacing: 4) {
                                Text(level.emoji)
                                    .font(.system(size: 30))
                                Text(level.label)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Tap to log how you feel right now")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    // MARK: - 3. Food Log Today

    private var foodLogCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "fork.knife")
                    .foregroundStyle(NC.food)
                Text("Food Today")
                    .font(.headline)
                Spacer()

                Button {
                    Haptic.light()
                    showFoodLog = true
                } label: {
                    Label("Log Meal", systemImage: "plus.circle.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(NC.food)
                }
            }

            if foodEntries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "fork.knife.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text("No meals logged yet today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else {
                // Total calories banner
                HStack {
                    Text("\(foodCalories) cal")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(NC.food)
                    Text("consumed today")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Meal type badges
                HStack(spacing: 8) {
                    ForEach(mealTypeSummary, id: \.type) { meal in
                        mealBadge(type: meal.type, count: meal.count)
                    }
                    Spacer()
                }

                // Entry list (compact)
                ForEach(foodEntries.prefix(3)) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: mealIcon(for: entry.mealType))
                            .font(.caption)
                            .foregroundStyle(NC.food)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.mealType.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                            if !entry.items.isEmpty {
                                Text(entry.items.prefix(2).map(\.name).joined(separator: ", "))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if let cal = entry.totalCaloriesEstimate {
                            Text("\(cal) cal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if foodEntries.count > 3 {
                    Text("+\(foodEntries.count - 3) more")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .card()
    }

    private struct MealSummary {
        let type: String
        let count: Int
    }

    private var mealTypeSummary: [MealSummary] {
        let grouped = Dictionary(grouping: foodEntries, by: \.mealType)
        return grouped.map { MealSummary(type: $0.key, count: $0.value.count) }
            .sorted { $0.type < $1.type }
    }

    private func mealBadge(type: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: mealIcon(for: type))
                .font(.system(size: 9))
            Text(type.capitalized)
                .font(.system(size: 10))
                .fontWeight(.medium)
            if count > 1 {
                Text("x\(count)")
                    .font(.system(size: 9))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(NC.food.opacity(0.12))
        .foregroundStyle(NC.food)
        .clipShape(Capsule())
    }

    private func mealIcon(for type: String) -> String {
        switch type.lowercased() {
        case "breakfast": return "sunrise.fill"
        case "lunch": return "sun.max.fill"
        case "dinner": return "moon.fill"
        case "snack": return "leaf.fill"
        default: return "fork.knife"
        }
    }

    // MARK: - 4. Quick Actions

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            quickActionPill(icon: "checkmark.circle.fill", label: "Habits", color: .teal) {
                Haptic.light()
                showHabitTracker = true
            }

            quickActionPill(icon: "fork.knife", label: "Food Log", color: NC.food) {
                Haptic.light()
                showFoodLog = true
            }

            quickActionPill(icon: "face.smiling", label: "Mood", color: .purple) {
                Haptic.light()
                showMoodHistory = true
            }
        }
    }

    private func quickActionPill(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Habits Progress

    @ViewBuilder
    private var habitsProgressCard: some View {
        if !habits.isEmpty {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal)
                    Text("Today's Habits")
                        .font(.headline)
                    Spacer()

                    let done = completedHabitIds.count
                    let total = habits.count
                    Text("\(done)/\(total)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                // Progress bar
                GeometryReader { geo in
                    let pct = habits.isEmpty ? 0 : CGFloat(completedHabitIds.count) / CGFloat(habits.count)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.teal.opacity(0.15))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.teal)
                            .frame(width: geo.size.width * pct, height: 6)
                            .animation(.easeOut(duration: 0.5), value: pct)
                    }
                }
                .frame(height: 6)

                ForEach(habits.prefix(5)) { habit in
                    let isCompleted = completedHabitIds.contains(habit.id)
                    let streak = habitStreaks[habit.id] ?? 0

                    Button {
                        Haptic.light()
                        Task { await toggleHabit(habit) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isCompleted ? .teal : .secondary)
                                .animation(.spring(response: 0.3), value: isCompleted)

                            Image(systemName: habit.icon)
                                .font(.caption)
                                .foregroundStyle(habitColor(habit.color))
                                .frame(width: NC.iconSize - 10, height: NC.iconSize - 10)
                                .background(habitColor(habit.color).opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: NC.iconRadius - 2))

                            Text(habit.name)
                                .font(.subheadline)
                                .strikethrough(isCompleted, color: .secondary)
                                .foregroundStyle(isCompleted ? .secondary : .primary)

                            Spacer()

                            if streak > 0 {
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.orange)
                                    Text("\(streak)d")
                                        .font(.caption2)
                                        .fontWeight(.medium)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                if habits.count > 5 {
                    Button {
                        Haptic.light()
                        showHabitTracker = true
                    } label: {
                        Text("View All \(habits.count) Habits")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.teal)
                    }
                }
            }
            .card()
        }
    }

    private func habitColor(_ name: String) -> Color {
        switch name {
        case "pink": return .pink
        case "orange": return .orange
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "teal": return .teal
        default: return .teal
        }
    }

    // MARK: - 6. Weekly Activity Summary

    private var weeklyActivityCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(.pink)
                Text("This Week")
                    .font(.headline)
                Spacer()
            }

            // Steps bar chart
            VStack(alignment: .leading, spacing: 6) {
                Text("Steps")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(0..<7, id: \.self) { i in
                        let value = weeklySteps[i]
                        let maxVal = max(weeklySteps.max() ?? 1, 1)
                        let height = max(CGFloat(value) / CGFloat(maxVal) * 60, 4)

                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(i == 6 ? Color.pink : Color.pink.opacity(0.35))
                                .frame(height: height)
                                .animation(.easeOut(duration: 0.5).delay(Double(i) * 0.05), value: value)

                            Text(dayLabel(daysAgo: 6 - i))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 80)
            }

            // Average sleep
            if sleepHours > 0 {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "bed.double.fill")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                    Text("Last night: \(String(format: "%.1f", sleepHours))h sleep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .card()
    }

    private func dayLabel(daysAgo: Int) -> String {
        let cal = Calendar.current
        guard let date = cal.date(byAdding: .day, value: -daysAgo, to: Date()) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let label = formatter.string(from: date)
        return String(label.prefix(1))
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        let health = HealthCollector.shared

        // Health data
        async let s = health.todaySteps()
        async let c = health.todayActiveCalories()
        async let sl = health.lastNightSleepHours()
        async let hr = health.todayRestingHeartRate()

        let (stepsVal, calVal, sleepVal, hrVal) = await (s, c, sl, hr)
        steps = stepsVal
        activeCalories = calVal
        sleepHours = sleepVal
        restingHR = hrVal

        // Mood
        todayMood = await MoodStore.shared.todaysMood()

        // Food
        let entries = await FoodStore.shared.entriesForToday()
        let cal = await FoodStore.shared.todayCalories
        foodEntries = entries
        foodCalories = cal

        // Habits
        let allHabits = await HabitStore.shared.allHabits()
        habits = allHabits
        var ids = Set<String>()
        var streaks: [String: Int] = [:]
        for habit in allHabits {
            let done = await HabitStore.shared.isCompleted(habitId: habit.id, date: Date())
            if done { ids.insert(habit.id) }
            streaks[habit.id] = await HabitStore.shared.streak(for: habit.id)
        }
        completedHabitIds = ids
        habitStreaks = streaks

        // Weekly steps
        await loadWeeklySteps()
    }

    private func loadWeeklySteps() async {
        let health = HealthCollector.shared
        var result: [Int] = []
        let cal = Calendar.current
        for i in (0..<7).reversed() {
            guard let date = cal.date(byAdding: .day, value: -i, to: Date()) else {
                result.append(0)
                continue
            }
            if i == 0 {
                result.append(await health.todaySteps())
            } else {
                result.append(await health.stepsForDate(date))
            }
        }
        weeklySteps = result
    }

    // MARK: - Actions

    private func logMood(_ level: MoodStore.MoodLevel) async {
        await MoodStore.shared.logMood(level)
        todayMood = await MoodStore.shared.todaysMood()
        Haptic.success()
    }

    private func toggleHabit(_ habit: HabitStore.Habit) async {
        await HabitStore.shared.toggleHabit(id: habit.id, date: Date())
        let done = await HabitStore.shared.isCompleted(habitId: habit.id, date: Date())
        if done {
            completedHabitIds.insert(habit.id)
            Haptic.success()
        } else {
            completedHabitIds.remove(habit.id)
        }
        habitStreaks[habit.id] = await HabitStore.shared.streak(for: habit.id)
    }
}

// MARK: - Preview

#Preview {
    HealthTabView()
}
