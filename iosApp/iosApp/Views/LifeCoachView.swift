import SwiftUI

/// AI Life Coach — agentic conversational interface powered by Groq/Llama.
/// Can answer questions AND take actions (set budgets, create goals, start challenges, etc.)
struct LifeCoachView: View {
    @StateObject private var vm = LifeCoachViewModel()
    @StateObject private var tokenTracker = GroqTokenTracker.shared
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Token usage bar
                tokenUsageBar

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

                // Input bar + session token info
                VStack(spacing: 0) {
                    inputBar

                    // Session / last request tokens
                    if tokenTracker.sessionTokens > 0 {
                        HStack(spacing: 12) {
                            Label("Session: \(tokenTracker.sessionTokens)", systemImage: "bolt.fill")
                            if tokenTracker.lastRequestTokens > 0 {
                                Label("Last: \(tokenTracker.lastRequestTokens)", systemImage: "arrow.up.right")
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, NC.hPad)
                        .padding(.bottom, 6)
                    }
                }
                .background(.background)
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

    // MARK: - Token Usage Bar

    private var tokenUsageBar: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "cpu")
                    .font(.system(size: 10))
                    .foregroundStyle(NC.teal)
                Text("Daily Tokens")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(tokenTracker.formattedUsage)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tokenBarColor)
                        .frame(width: geo.size.width * min(tokenTracker.todayPercentage, 1.0), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, 8)
        .background(.background)
    }

    private var tokenBarColor: Color {
        let pct = tokenTracker.todayPercentage
        if pct > 0.9 { return .red }
        if pct > 0.7 { return .orange }
        return NC.teal
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
                Text("I can answer questions AND take actions. Try \"Set a dining budget of 5000\" or \"Start a no eating out challenge\".")
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
            TextField("Ask or command...", text: $vm.inputText, axis: .vertical)
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
                // Action badge (if an action was taken). Out-of-scope renders
                // in muted gray so users don't mistake a polite decline for
                // a successful action.
                if let action = message.actionTaken {
                    let isDecline = action == CoachAction.outOfScope.label
                    HStack(spacing: 4) {
                        Image(systemName: isDecline ? "hand.raised.fill" : "checkmark.circle.fill")
                            .font(.system(size: 10))
                        Text(action)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isDecline ? Color.gray : Color.green, in: Capsule())
                }

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

// MARK: - CoachAction

enum CoachAction: String, CaseIterable {
    case setBudget
    case createGoal
    case startChallenge
    case addHabit
    case logMood
    case logFood
    case logExpense
    case setDietPlan
    case outOfScope
    case question

    var label: String {
        switch self {
        case .setBudget:      return "Budget Set"
        case .createGoal:     return "Goal Created"
        case .startChallenge: return "Challenge Started"
        case .addHabit:       return "Habit Added"
        case .logMood:        return "Mood Logged"
        case .logFood:        return "Food Logged"
        case .logExpense:     return "Expense Logged"
        case .setDietPlan:    return "Diet Plan Set"
        case .outOfScope:     return "Outside My Scope"
        case .question:       return "Answered"
        }
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
        let actionTaken: String?

        init(text: String, isUser: Bool, timestamp: Date, actionTaken: String? = nil) {
            self.text = text
            self.isUser = isUser
            self.timestamp = timestamp
            self.actionTaken = actionTaken
        }
    }

    @Published var messages: [ChatMessage] = []
    @Published var inputText = ""
    @Published var isLoading = false

    private var lifeContext = ""

    let suggestions = [
        "Set a dining budget of 5000",
        "Start a no eating out challenge",
        "Add a meditation habit",
        "How did I do this week?",
        "Where am I spending the most?",
        "Log my mood as great",
        "I spent 200 at Starbucks",
    ]

    // MARK: - Build Context

    func buildContext() async {
        var ctx: [String] = []
        ctx.append("Today is \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)).")

        // Body metrics — needed for diet plan TDEE calculation. Coach is told
        // explicitly when each is missing so it can ask the user instead of
        // hallucinating.
        let info = await MainActor.run { PersonalInfoStore.shared.info }
        var bodyParts: [String] = []
        if let age = info.age { bodyParts.append("age \(age)") }
        if let h = info.heightCm { bodyParts.append("height \(Int(h))cm") }
        if let w = info.weightKg { bodyParts.append("weight \(Int(w))kg") }
        if !bodyParts.isEmpty {
            ctx.append("Body: \(bodyParts.joined(separator: ", ")).")
        }
        var missing: [String] = []
        if info.age == nil { missing.append("age") }
        if info.heightCm == nil { missing.append("height") }
        if info.weightKg == nil { missing.append("weight") }
        if !missing.isEmpty {
            ctx.append("Missing body info: \(missing.joined(separator: ", ")). Ask the user before computing a diet plan from scratch.")
        }

        // Today's food intake (calories + macros) — diet plan progress comes
        // from this aggregation, so the coach should reference it when asked.
        let foodCal = await FoodStore.shared.todayCalories
        let foodMac = await FoodStore.shared.todayMacros
        if foodCal > 0 || foodMac != .zero {
            ctx.append("Eaten today: \(foodCal) kcal, \(Int(round(foodMac.protein)))g P, \(Int(round(foodMac.carbs)))g C, \(Int(round(foodMac.fat)))g F.")
        }

        // Active diet plan — so coach knows whether one is already running.
        if let plan = await ChallengeStore.shared.activeDietPlan(), let t = plan.macroTargets {
            ctx.append("Active diet plan '\(plan.title)': \(Int(t.calories)) kcal/\(Int(t.protein))g P/\(Int(t.carbs))g C/\(Int(t.fat))g F per day, streak \(plan.dietStreakDays) days.")
        }

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

        // Budgets
        let budgetProgress = await BudgetStore.shared.progressForAll()
        if !budgetProgress.isEmpty {
            let budgetStr = budgetProgress.map { "\($0.category): \(NC.money($0.spent))/\(NC.money($0.limit)) (\(Int($0.percentage * 100))%)" }.joined(separator: ", ")
            ctx.append("Budgets: \(budgetStr).")
        }

        // Habits
        let habitProgress = await HabitStore.shared.todayProgress()
        if habitProgress.total > 0 {
            let habits = await HabitStore.shared.allHabits()
            let habitNames = habits.map(\.name).joined(separator: ", ")
            ctx.append("Habits (\(habitProgress.completed)/\(habitProgress.total) today): \(habitNames).")
        }

        // Challenges
        let activeChallenges = await ChallengeStore.shared.activeChallenges()
        if !activeChallenges.isEmpty {
            let challengeStr = activeChallenges.map { "\($0.title): \(Int($0.currentValue))/\(Int($0.targetValue))" }.joined(separator: ", ")
            ctx.append("Active challenges: \(challengeStr).")
        }

        // Savings goals
        let savingsGoals = await SavingsGoalStore.shared.allGoals()
        if !savingsGoals.isEmpty {
            let goalStr = savingsGoals.filter { !$0.isCompleted }.map { "\($0.name): target \(NC.money($0.targetAmount))" }.joined(separator: ", ")
            if !goalStr.isEmpty { ctx.append("Savings goals: \(goalStr).") }
        }

        // Subscriptions
        let subs = await SubscriptionManager.shared.allSubscriptions()
        let activeSubs = subs.filter(\.isActive)
        if !activeSubs.isEmpty {
            let subMonthly = await SubscriptionManager.shared.monthlyTotal()
            let subStr = activeSubs.prefix(5).map { "\($0.merchant): \(NC.money($0.amount))/\($0.frequency.label.lowercased())" }.joined(separator: ", ")
            ctx.append("Active subscriptions (\(activeSubs.count), \(NC.money(subMonthly))/mo): \(subStr).")
        }

        // Place Intelligence — frequent locations, routines, spending places
        let profile = await UserProfileStore.shared.currentProfile()
        let routines = profile.frequentLocations
            .filter { $0.visitCount >= 3 && $0.label != nil }
            .sorted { $0.visitCount > $1.visitCount }
            .prefix(5)
        if !routines.isEmpty {
            let placeStr = routines.map { loc -> String in
                let tag = loc.behaviorTag ?? "visit"
                let pillars = (loc.pillarTags ?? []).joined(separator: "/")
                return "\(loc.label ?? "?"): \(tag.replacingOccurrences(of: "_", with: " ")) (\(loc.visitCount)x, pillars: \(pillars))"
            }.joined(separator: "; ")
            ctx.append("Frequent places: \(placeStr).")
        }

        lifeContext = ctx.joined(separator: " ")
    }

    // MARK: - Send (Agentic)

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

        // Refresh context before responding
        await buildContext()

        // Build agentic prompt
        let recentChat = messages.suffix(10).map { ($0.isUser ? "User" : "Coach") + ": " + $0.text }.joined(separator: "\n")

        let systemPrompt = """
        You are NodeCompass's AI life coach. You help users track and improve their wealth, health, and habits — and you can take actions on their behalf inside the app.

        SCOPE — what you handle:
        • Money: spending, budgets, savings goals, subscriptions, transactions
        • Health: steps, sleep, workouts, mood, weight, fitness goals
        • Food: meals, calories, macros, diet plans
        • Habits & challenges: building consistent behaviors
        • Reflections on the user's own data: "how am I doing?", "where do I overspend?", trends, patterns
        • General lifestyle/fitness/nutrition advice IF it directly leads to setting up something in the app

        SCOPE — what you DON'T handle:
        • General knowledge (capitals, history, math, programming, recipes-without-context)
        • External services (booking, browsing the web, sending messages, calling APIs)
        • Medical/legal/financial advice that requires a licensed professional
        • Creative writing, jokes, casual chitchat unrelated to the user's life data
        • Anything you can't accomplish via the actions listed below

        USER DATA:
        \(lifeContext)

        RECENT CONVERSATION:
        \(recentChat)

        You MUST respond with valid JSON in this EXACT shape:
        {
          "type": "action" | "question" | "outOfScope",
          "action": <one of the action names below, or null>,
          "params": { ... } | null,
          "response": "friendly natural-language reply to the user"
        }

        DECISION TREE:
        1. Does the user want to DO something inside the app (set up a budget, log a meal, start a challenge, etc.)? → type="action", pick the most relevant action, fill params, write a confirming response.
        2. Are they asking ABOUT their existing data, or for advice that requires reading their data? → type="question", action=null, params=null, write the answer.
        3. Is the request outside the SCOPE list above? → type="outOfScope", action=null, params=null, response should be a short, friendly decline that names what you CAN help with. Examples: "That's outside what I track. I can help with budgets, goals, challenges, food, mood, and your spending or health patterns — what would be useful?" — be polite, don't lecture.

        Pick exactly ONE action per response. If the user asks for multiple things at once ("set a dining budget AND start a no-eating-out challenge"), pick the most impactful one and offer the other in your response text.

        ACTIONS (use camelCase exactly):

        setBudget — when user wants to cap spending in a category
          { "category": "Dining" | "Shopping" | "Transport" | "Groceries" | "Entertainment" | "Health" | "Education" | "Travel" | "Bills" | "Other",
            "amount": <number> }

        createGoal — when user wants to save toward a named target with optional deadline
          { "name": "Vacation Fund", "target": 50000, "icon": "airplane" }
          Pick a relevant SF Symbol icon. Keep names short and concrete.

        startChallenge — when user wants to commit to a behavior streak
          { "type": "noEatingOut" | "dailySpendLimit" | "stepGoal" | "homeCooking" | "savingsTarget" | "workoutStreak" | "habitStreak",
            "target": <number>, "days": <number> }
          Pick the type that best matches: "stop ordering food" → noEatingOut, "walk more" → stepGoal, "cook more" → homeCooking, etc.

        addHabit — when user wants a recurring daily/weekly behavior to track
          { "name": "Meditate", "icon": "brain.head.profile", "color": "teal" | "pink" | "orange" | "blue" | "purple" | "green" }

        logMood — when user states their current mood
          { "level": "great" | "good" | "okay" | "bad" | "terrible", "note": "optional" }

        logFood — when user says they ate something specific just now
          { "meal": "breakfast" | "lunch" | "snack" | "dinner", "items": ["..."], "calories": <number> }

        logExpense — when user states a specific transaction they made
          { "amount": <number>, "merchant": "Starbucks", "category": "Dining" }

        setDietPlan — when user asks for a diet/macro/cutting/bulking/maintenance plan, OR explicitly states a daily calorie/macro target
          { "name": "Lean Bulk", "calories": 2400, "protein": 180, "carbs": 280, "fat": 80, "fiber": 30 }
          • If body metrics (age, height, weight) are known: derive cals/macros via Mifflin-St Jeor BMR × activity factor (sedentary 1.4, moderate 1.55, active 1.75) ± goal delta (-15% cut, +10% lean bulk, 0 maintenance).
          • Protein: ~2.2g/kg lean bulk, ~2.6g/kg cut, ~1.8g/kg maintenance.
          • If body metrics OR activity level are MISSING and user didn't supply explicit targets → return type="question" and ASK for the missing info. DO NOT guess.
          • If user gave explicit targets ("1800 cal/day"), use those directly and fill remaining macros sensibly.
          • Round all values to whole grams and whole calories. "fiber" is optional.

        SF Symbol icons you can use: brain.head.profile, figure.run, book.fill, fork.knife, leaf.fill, drop.fill, moon.fill, cart, heart.fill, star.fill, airplane, house.fill, car.fill, graduationcap.fill, dumbbell.fill, target, flame.fill

        STYLE:
        • Reference REAL numbers from USER DATA when relevant. Never fabricate.
        • Keep responses to 2-4 sentences. Be encouraging without being saccharine.
        • If the user is missing information you need (like body metrics for a diet plan), ask a single clear question — don't list every missing field.
        • For outOfScope, be brief and pivot back to what you CAN do.

        User: \(text)
        """

        if let rawResponse = await groq.generate(prompt: systemPrompt, maxTokens: 400) {
            // Parse JSON response
            let cleaned = rawResponse
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let data = cleaned.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let responseText = json["response"] as? String ?? "Done!"
                let type = json["type"] as? String ?? "question"
                let actionStr = json["action"] as? String
                let params = json["params"] as? [String: Any]

                if type == "action",
                   let actionStr,
                   let action = CoachAction(rawValue: actionStr),
                   action != .question, action != .outOfScope {
                    // Execute the action
                    let success = await executeAction(action, params: params ?? [:])
                    if success {
                        Haptic.success()
                        messages.append(ChatMessage(
                            text: responseText,
                            isUser: false,
                            timestamp: Date(),
                            actionTaken: action.label
                        ))
                    } else {
                        messages.append(ChatMessage(
                            text: responseText + "\n\n(Action could not be completed — please check the parameters.)",
                            isUser: false,
                            timestamp: Date()
                        ))
                    }
                } else if type == "outOfScope" {
                    // Polite decline — annotate the bubble so the user
                    // sees this was intentional, not a failure.
                    Haptic.light()
                    messages.append(ChatMessage(
                        text: responseText,
                        isUser: false,
                        timestamp: Date(),
                        actionTaken: CoachAction.outOfScope.label
                    ))
                } else {
                    // Plain question/answer
                    messages.append(ChatMessage(text: responseText, isUser: false, timestamp: Date()))
                }
            } else {
                // Fallback: treat raw text as response if JSON parse fails
                let fallback = rawResponse
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "Coach: ", with: "")
                messages.append(ChatMessage(text: fallback, isUser: false, timestamp: Date()))
            }
        } else {
            messages.append(ChatMessage(
                text: "Sorry, I couldn't process that. Please try again.",
                isUser: false, timestamp: Date()
            ))
        }

        isLoading = false
    }

    // MARK: - Execute Action

    private func executeAction(_ action: CoachAction, params: [String: Any]) async -> Bool {
        switch action {
        case .setBudget:
            guard let category = params["category"] as? String,
                  let amount = params["amount"] as? Double ?? (params["amount"] as? Int).map(Double.init) else { return false }
            await BudgetStore.shared.addBudget(category: category, limit: amount)
            return true

        case .createGoal:
            guard let name = params["name"] as? String,
                  let target = params["target"] as? Double ?? (params["target"] as? Int).map(Double.init) else { return false }
            let icon = params["icon"] as? String ?? "star.fill"
            await SavingsGoalStore.shared.addGoal(name: name, target: target, deadline: nil, icon: icon)
            return true

        case .startChallenge:
            guard let typeStr = params["type"] as? String,
                  let challengeType = ChallengeStore.ChallengeType(rawValue: typeStr) else { return false }
            let target = params["target"] as? Double ?? (params["target"] as? Int).map(Double.init) ?? challengeType.defaultTarget
            let days = params["days"] as? Int ?? challengeType.defaultDuration
            await ChallengeStore.shared.createChallenge(type: challengeType, target: target, days: days)
            return true

        case .addHabit:
            guard let name = params["name"] as? String else { return false }
            let icon = params["icon"] as? String ?? "checkmark.circle"
            let color = params["color"] as? String ?? "teal"
            await HabitStore.shared.addHabit(name: name, icon: icon, color: color)
            return true

        case .logMood:
            guard let levelStr = params["level"] as? String else { return false }
            let level: MoodStore.MoodLevel
            switch levelStr.lowercased() {
            case "great":    level = .great
            case "good":     level = .good
            case "okay":     level = .okay
            case "bad":      level = .bad
            case "terrible": level = .terrible
            default:         return false
            }
            let note = params["note"] as? String
            await MoodStore.shared.logMood(level, note: note)
            return true

        case .logFood:
            let meal = params["meal"] as? String ?? "snack"
            let itemNames = params["items"] as? [String] ?? []
            guard !itemNames.isEmpty else { return false }
            let items = itemNames.map { FoodItem(name: $0) }
            let calories = params["calories"] as? Int
            let entry = FoodStore.FoodLogEntry(
                mealType: meal,
                items: items,
                source: .manual,
                totalCaloriesEstimate: calories
            )
            await FoodStore.shared.addEntry(entry)
            return true

        case .logExpense:
            guard let amount = params["amount"] as? Double ?? (params["amount"] as? Int).map(Double.init),
                  let merchant = params["merchant"] as? String else { return false }
            let category = params["category"] as? String
            TransactionStore.shared.addManualTransaction(amount: amount, merchant: merchant, category: category)
            return true

        case .setDietPlan:
            // Tolerate Int OR Double for every macro field — Groq sometimes
            // returns whole-number ints, sometimes decimals.
            func d(_ key: String) -> Double? {
                if let v = params[key] as? Double { return v }
                if let v = params[key] as? Int { return Double(v) }
                return nil
            }
            guard let name = params["name"] as? String,
                  let cals = d("calories"), cals > 0,
                  let protein = d("protein"), protein > 0,
                  let carbs = d("carbs"),
                  let fat = d("fat") else {
                return false
            }
            let targets = ChallengeStore.MacroTargets(
                calories: cals,
                protein: protein,
                carbs: carbs,
                fat: fat,
                fiber: d("fiber")
            )
            await ChallengeStore.shared.createDietPlan(name: name, targets: targets)
            // Refresh progress immediately so the new plan card shows today's
            // running totals on first render.
            await ChallengeStore.shared.updateProgress()
            return true

        case .outOfScope, .question:
            return true
        }
    }

    func clearChat() {
        messages.removeAll()
    }
}
