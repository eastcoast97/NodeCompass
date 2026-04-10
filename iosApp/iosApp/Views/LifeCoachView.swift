import SwiftUI

/// AI Life Coach — conversational interface powered by Groq/Llama.
struct LifeCoachView: View {
    @StateObject private var vm = LifeCoachViewModel()
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Welcome
                            if vm.messages.isEmpty {
                                welcomeSection
                            }

                            ForEach(vm.messages) { msg in
                                ChatBubble(message: msg)
                                    .id(msg.id)
                            }

                            if vm.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Thinking...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, NC.hPad)
                                .id("loading")
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .onChange(of: vm.messages.count) {
                        withAnimation {
                            proxy.scrollTo(vm.messages.last?.id ?? "loading", anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input bar
                inputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Life Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !vm.messages.isEmpty {
                        Button {
                            vm.clearChat()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .task { await vm.buildContext() }
        }
    }

    // MARK: - Welcome

    private var welcomeSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(NC.teal.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32))
                    .foregroundStyle(NC.teal)
            }
            .padding(.top, 40)

            VStack(spacing: 8) {
                Text("Your AI Life Coach")
                    .font(.title3.bold())
                Text("I know your spending, health, food, and routines. Ask me anything about your life patterns.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Quick suggestions
            VStack(spacing: 8) {
                Text("Try asking:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button {
                        vm.inputText = suggestion
                        Task { await vm.send() }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.caption2)
                                .foregroundStyle(NC.teal)
                            Text(suggestion)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(NC.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, NC.hPad)
        }
        .padding(.horizontal, NC.hPad)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your life...", text: $vm.inputText, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...4)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            Button {
                Haptic.light()
                Task { await vm.send() }
                isInputFocused = false
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : NC.teal)
            }
            .disabled(vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty || vm.isLoading)
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, 10)
        .background(.background)
    }
}

// MARK: - Chat Bubble

private struct ChatBubble: View {
    let message: LifeCoachViewModel.ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.isUser {
                Spacer(minLength: 60)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundStyle(NC.teal)
                    .frame(width: 28, height: 28)
                    .background(NC.teal.opacity(0.1), in: Circle())
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(message.isUser ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser
                            ? AnyShapeStyle(NC.teal)
                            : AnyShapeStyle(Color(.systemGray6)),
                        in: BubbleShape(isUser: message.isUser)
                    )

                Text(timeLabel(message.timestamp))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            if !message.isUser {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, NC.hPad)
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

// MARK: - Bubble Shape

private struct BubbleShape: Shape {
    let isUser: Bool
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: isUser
                ? [.topLeft, .topRight, .bottomLeft]
                : [.topLeft, .topRight, .bottomRight],
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - ViewModel

@MainActor
class LifeCoachViewModel: ObservableObject {
    struct ChatMessage: Identifiable {
        let id = UUID().uuidString
        let text: String
        let isUser: Bool
        let timestamp: Date
    }

    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false

    private var lifeContext = ""

    let suggestions = [
        "How did I do this week?",
        "Where am I spending the most?",
        "Am I getting enough sleep?",
        "What should I focus on improving?",
        "How are my eating habits?",
    ]

    func buildContext() async {
        // Build a comprehensive life context string from all data sources
        var ctx: [String] = []
        ctx.append("Today is \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)).")

        // Spending
        let spent = TransactionStore.shared.totalSpendThisMonth
        let income = TransactionStore.shared.totalIncomeThisMonth
        ctx.append("This month: spent \(NC.money(spent)), income \(NC.money(income)).")

        // Health
        let health = HealthCollector.shared
        let steps = await health.todaySteps()
        let sleep = await health.lastNightSleepHours()
        let workouts = await health.recentWorkoutStats()
        let cals = await health.todayActiveCalories()
        if steps > 0 { ctx.append("Today's steps: \(steps).") }
        if sleep > 0 { ctx.append("Last night's sleep: \(String(format: "%.1f", sleep)) hours.") }
        if workouts.perWeek > 0 { ctx.append("Workouts this week: \(Int(workouts.perWeek)), streak: \(workouts.streak) days.") }
        if cals > 0 { ctx.append("Active calories today: \(cals).") }

        // Life score
        if let score = await LifeScoreEngine.shared.todayScore() {
            ctx.append("Life Score: \(score.total)/100 (Wealth: \(score.wealth), Health: \(score.health), Food: \(score.food), Routine: \(score.routine)).")
        }

        // Food
        let todayFood = await FoodStore.shared.entriesForToday()
        let meals = todayFood.filter { !$0.items.isEmpty }
        if !meals.isEmpty {
            ctx.append("Meals today: \(meals.count). Items: \(meals.flatMap { $0.items.map { $0.name } }.joined(separator: ", ")).")
        }

        // Goals
        let goals = await GoalStore.shared.progressForAll()
        if !goals.isEmpty {
            let goalStr = goals.map { "\($0.goal.type.title): \(Int($0.progress * 100))% (\($0.statusText))" }.joined(separator: ", ")
            ctx.append("Goals: \(goalStr).")
        }

        // Mood
        if let mood = await MoodStore.shared.todaysMood() {
            ctx.append("Today's mood: \(mood.mood.label).")
        }
        let avgMood = await MoodStore.shared.averageMood(days: 7)
        if avgMood > 0 {
            ctx.append("7-day mood average: \(String(format: "%.1f", avgMood))/5.")
        }

        // Streaks
        let streaks = await AchievementEngine.shared.activeStreaks()
        if !streaks.isEmpty {
            let streakStr = streaks.map { "\($0.type.title): \($0.currentDays) days" }.joined(separator: ", ")
            ctx.append("Active streaks: \(streakStr).")
        }

        // Spending prediction
        let prediction = await SpendingPredictor.predict()
        ctx.append("Projected month-end spend: \(NC.money(prediction.projectedTotal)). \(prediction.daysLeft) days left, \(NC.money(prediction.dailyBudgetRemaining))/day remaining budget.")

        lifeContext = ctx.joined(separator: " ")
    }

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let userMsg = ChatMessage(text: text, isUser: true, timestamp: Date())
        messages.append(userMsg)
        inputText = ""
        isLoading = true

        let groq = GroqService.shared
        guard groq.hasApiKey else {
            messages.append(ChatMessage(
                text: "I need an AI API key to chat. Go to You \u{2192} AI Setup to configure one.",
                isUser: false, timestamp: Date()
            ))
            isLoading = false
            return
        }

        // Build prompt with context
        let recentChat = messages.suffix(10).map { ($0.isUser ? "User" : "Coach") + ": " + $0.text }.joined(separator: "\n")

        let prompt = """
        You are a personal life coach inside NodeCompass, a privacy-first life tracking app. You have access to the user's real data:

        \(lifeContext)

        Recent conversation:
        \(recentChat)

        User: \(text)

        Respond as a helpful, encouraging life coach. Be specific using the data above. Keep responses concise (2-4 sentences). Use the actual numbers from their data. If they ask about something you don't have data for, say so honestly. Never make up data.
        """

        if let response = await groq.generate(prompt: prompt, maxTokens: 300) {
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "Coach: ", with: "")
            messages.append(ChatMessage(text: cleaned, isUser: false, timestamp: Date()))
        } else {
            messages.append(ChatMessage(
                text: "Sorry, I couldn't process that. Please try again.",
                isUser: false, timestamp: Date()
            ))
        }

        isLoading = false
    }

    func clearChat() {
        messages.removeAll()
    }
}
