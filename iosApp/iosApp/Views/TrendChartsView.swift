import SwiftUI
import Charts

// MARK: - ViewModel

@MainActor
class TrendChartsViewModel: ObservableObject {
    @Published var selectedTab: TrendTab = .spending
    @Published var isLoading = false

    // Spending data
    @Published var dailySpending: [DayAmount] = []
    @Published var categoryComparison: [CategoryMonth] = []
    @Published var averageDailySpend: Double = 0

    // Health data
    @Published var dailySteps: [DayAmount] = []
    @Published var sleepHours: [DayAmount] = []
    @Published var workoutDays: [DayMarker] = []

    // Life Score data
    @Published var dailyLifeScores: [DayAmount] = []
    @Published var pillarBreakdown: [PillarDay] = []

    // Food data
    @Published var mealsPerDay: [DayAmount] = []
    @Published var homeVsOut: [MealSourceDay] = []

    enum TrendTab: String, CaseIterable {
        case spending = "Spending"
        case health = "Health"
        case lifeScore = "Life Score"
        case food = "Food"
    }

    // Chart data types
    struct DayAmount: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let label: String

        init(date: Date, value: Double, label: String = "") {
            self.date = date
            self.value = value
            self.label = label
        }
    }

    struct CategoryMonth: Identifiable {
        let id = UUID()
        let category: String
        let amount: Double
        let period: String   // "This Month" or "Last Month"
    }

    struct DayMarker: Identifiable {
        let id = UUID()
        let date: Date
        let didWorkout: Bool
    }

    struct PillarDay: Identifiable {
        let id = UUID()
        let date: Date
        let pillar: String   // "Wealth", "Health", "Food", "Routine"
        let value: Double
    }

    struct MealSourceDay: Identifiable {
        let id = UUID()
        let date: Date
        let source: String   // "Home" or "Eating Out"
        let count: Double
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: today)!
        let fourteenDaysAgo = cal.date(byAdding: .day, value: -14, to: today)!

        // Load all data in parallel
        async let spendingTask: () = loadSpending(cal: cal, today: today, since: thirtyDaysAgo)
        async let healthTask: () = loadHealth(cal: cal, today: today, since: thirtyDaysAgo, sleepSince: fourteenDaysAgo)
        async let lifeScoreTask: () = loadLifeScores(cal: cal, today: today)
        async let foodTask: () = loadFood(cal: cal, today: today, since: thirtyDaysAgo)

        _ = await (spendingTask, healthTask, lifeScoreTask, foodTask)
    }

    // MARK: - Spending Loading

    private func loadSpending(cal: Calendar, today: Date, since: Date) async {
        let transactions = TransactionStore.shared.transactions

        // Daily spending over last 30 days
        let debits = transactions.filter { $0.type.uppercased() == "DEBIT" && $0.date >= since }
        var dailyTotals: [Date: Double] = [:]
        for txn in debits {
            let day = cal.startOfDay(for: txn.date)
            dailyTotals[day, default: 0] += txn.amount
        }

        // Fill in zero-days
        var spendingData: [DayAmount] = []
        var totalSpend: Double = 0
        var daysWithData = 0
        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -29 + offset, to: today)!
            let amount = dailyTotals[day] ?? 0
            spendingData.append(DayAmount(date: day, value: amount))
            totalSpend += amount
            if amount > 0 { daysWithData += 1 }
        }

        dailySpending = spendingData
        averageDailySpend = daysWithData > 0 ? totalSpend / Double(daysWithData) : 0

        // Category comparison: this month vs last month
        let startOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let startOfLastMonth = cal.date(byAdding: .month, value: -1, to: startOfThisMonth)!

        let thisMonthTxns = transactions.filter { $0.type.uppercased() == "DEBIT" && $0.date >= startOfThisMonth }
        let lastMonthTxns = transactions.filter { $0.type.uppercased() == "DEBIT" && $0.date >= startOfLastMonth && $0.date < startOfThisMonth }

        var thisMonthCats: [String: Double] = [:]
        for txn in thisMonthTxns { thisMonthCats[txn.category, default: 0] += txn.amount }

        var lastMonthCats: [String: Double] = [:]
        for txn in lastMonthTxns { lastMonthCats[txn.category, default: 0] += txn.amount }

        let allCategories = Set(thisMonthCats.keys).union(lastMonthCats.keys)
        var comparison: [CategoryMonth] = []
        for cat in allCategories.sorted() {
            if let amount = thisMonthCats[cat], amount > 0 {
                comparison.append(CategoryMonth(category: cat, amount: amount, period: "This Month"))
            }
            if let amount = lastMonthCats[cat], amount > 0 {
                comparison.append(CategoryMonth(category: cat, amount: amount, period: "Last Month"))
            }
        }
        categoryComparison = comparison
    }

    // MARK: - Health Loading

    private func loadHealth(cal: Calendar, today: Date, since: Date, sleepSince: Date) async {
        // Use Life Score data as proxy for daily health metrics
        let scores = await LifeScoreEngine.shared.recentScores(days: 30)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        // Steps: use health sub-score as indicator (0-100 scale)
        var stepsData: [DayAmount] = []
        var sleepData: [DayAmount] = []
        var workoutData: [DayMarker] = []

        let scoresByDate: [String: LifeScoreEngine.DailyScore] = Dictionary(
            scores.map { ($0.dateKey, $0) },
            uniquingKeysWith: { _, last in last }
        )

        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -29 + offset, to: today)!
            let dateKey = df.string(from: day)

            if let score = scoresByDate[dateKey] {
                // Map health score components
                stepsData.append(DayAmount(date: day, value: Double(score.breakdown.stepGoal)))

                if offset >= 16 { // Last 14 days for sleep
                    sleepData.append(DayAmount(date: day, value: Double(score.breakdown.sleepQuality)))
                }

                workoutData.append(DayMarker(date: day, didWorkout: score.breakdown.workoutConsistency > 50))
            } else {
                stepsData.append(DayAmount(date: day, value: 0))
                if offset >= 16 {
                    sleepData.append(DayAmount(date: day, value: 0))
                }
                workoutData.append(DayMarker(date: day, didWorkout: false))
            }
        }

        dailySteps = stepsData
        sleepHours = sleepData
        workoutDays = workoutData
    }

    // MARK: - Life Score Loading

    private func loadLifeScores(cal: Calendar, today: Date) async {
        let scores = await LifeScoreEngine.shared.recentScores(days: 30)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        var lineData: [DayAmount] = []
        var pillarData: [PillarDay] = []

        for score in scores {
            guard let date = df.date(from: score.dateKey) else { continue }

            lineData.append(DayAmount(date: date, value: Double(score.total)))

            pillarData.append(PillarDay(date: date, pillar: "Wealth", value: Double(score.wealth) * 0.30))
            pillarData.append(PillarDay(date: date, pillar: "Health", value: Double(score.health) * 0.30))
            pillarData.append(PillarDay(date: date, pillar: "Food", value: Double(score.food) * 0.20))
            pillarData.append(PillarDay(date: date, pillar: "Routine", value: Double(score.routine) * 0.20))
        }

        dailyLifeScores = lineData
        pillarBreakdown = pillarData
    }

    // MARK: - Food Loading

    private func loadFood(cal: Calendar, today: Date, since: Date) async {
        let entries = await FoodStore.shared.entries(since: since)
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        // Meals per day
        var mealsByDay: [String: Int] = [:]
        var homeByDay: [String: Int] = [:]
        var outByDay: [String: Int] = [:]

        for entry in entries {
            let dateKey = df.string(from: entry.timestamp)
            mealsByDay[dateKey, default: 0] += 1

            if entry.source == .emailOrder {
                outByDay[dateKey, default: 0] += 1
            } else {
                homeByDay[dateKey, default: 0] += 1
            }
        }

        var mealsData: [DayAmount] = []
        var sourceData: [MealSourceDay] = []

        for offset in 0..<30 {
            let day = cal.date(byAdding: .day, value: -29 + offset, to: today)!
            let dateKey = df.string(from: day)

            mealsData.append(DayAmount(date: day, value: Double(mealsByDay[dateKey] ?? 0)))

            let homeCount = homeByDay[dateKey] ?? 0
            let outCount = outByDay[dateKey] ?? 0
            if homeCount > 0 {
                sourceData.append(MealSourceDay(date: day, source: "Home", count: Double(homeCount)))
            }
            if outCount > 0 {
                sourceData.append(MealSourceDay(date: day, source: "Eating Out", count: Double(outCount)))
            }
        }

        mealsPerDay = mealsData
        homeVsOut = sourceData
    }
}

// MARK: - View

struct TrendChartsView: View {
    @StateObject private var vm = TrendChartsViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("Trend", selection: $vm.selectedTab) {
                    ForEach(TrendChartsViewModel.TrendTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, NC.hPad)
                .padding(.vertical, 8)

                if vm.isLoading {
                    Spacer()
                    ProgressView("Loading trends...")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            switch vm.selectedTab {
                            case .spending:
                                spendingCharts
                            case .health:
                                healthCharts
                            case .lifeScore:
                                lifeScoreCharts
                            case .food:
                                foodCharts
                            }
                        }
                        .padding(.horizontal, NC.hPad)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle("Trends")
            .task { await vm.load() }
        }
    }

    // MARK: - Spending Charts

    @ViewBuilder
    private var spendingCharts: some View {
        // Daily spending line chart
        chartCard(title: "Daily Spending", subtitle: "Last 30 days") {
            Chart {
                ForEach(vm.dailySpending) { point in
                    LineMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Amount", point.value)
                    )
                    .foregroundStyle(NC.teal)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Amount", point.value)
                    )
                    .foregroundStyle(NC.teal.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                }

                // Average line
                if vm.averageDailySpend > 0 {
                    RuleMark(y: .value("Average", vm.averageDailySpend))
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Avg: \(NC.money(vm.averageDailySpend))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(NC.money(v))
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 200)
        }

        // Category comparison bar chart
        if !vm.categoryComparison.isEmpty {
            chartCard(title: "Category Comparison", subtitle: "This month vs last month") {
                Chart(vm.categoryComparison) { item in
                    BarMark(
                        x: .value("Category", item.category),
                        y: .value("Amount", item.amount)
                    )
                    .foregroundStyle(by: .value("Period", item.period))
                    .position(by: .value("Period", item.period))
                }
                .chartForegroundStyleScale([
                    "This Month": NC.teal,
                    "Last Month": NC.teal.opacity(0.4)
                ])
                .chartLegend(position: .top)
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let cat = value.as(String.self) {
                                Text(cat)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .frame(height: 220)
            }
        }
    }

    // MARK: - Health Charts

    @ViewBuilder
    private var healthCharts: some View {
        // Steps line chart
        chartCard(title: "Step Goal Progress", subtitle: "Score over last 30 days") {
            Chart(vm.dailySteps) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(.pink)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(.pink.opacity(0.1))
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 180)
        }

        // Sleep bar chart
        chartCard(title: "Sleep Quality", subtitle: "Last 14 days") {
            Chart(vm.sleepHours) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(.indigo.gradient)
                .cornerRadius(3)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 160)
        }

        // Workout dots
        chartCard(title: "Workout Days", subtitle: "Last 30 days") {
            Chart(vm.workoutDays) { marker in
                PointMark(
                    x: .value("Date", marker.date, unit: .day),
                    y: .value("Workout", marker.didWorkout ? 1 : 0)
                )
                .foregroundStyle(marker.didWorkout ? .pink : Color(.systemGray4))
                .symbolSize(marker.didWorkout ? 80 : 30)
                .symbol(marker.didWorkout ? .circle : .circle)
            }
            .chartYScale(domain: -0.5...1.5)
            .chartYAxis(.hidden)
            .frame(height: 60)
        }
    }

    // MARK: - Life Score Charts

    @ViewBuilder
    private var lifeScoreCharts: some View {
        // Overall life score line
        chartCard(title: "Life Score", subtitle: "Last 30 days") {
            Chart(vm.dailyLifeScores) { point in
                LineMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(NC.teal)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                AreaMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Score", point.value)
                )
                .foregroundStyle(NC.teal.opacity(0.08))
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .frame(height: 200)
        }

        // Stacked area chart for pillar breakdown
        if !vm.pillarBreakdown.isEmpty {
            chartCard(title: "Score Breakdown", subtitle: "Wealth, Health, Food, Routine") {
                Chart(vm.pillarBreakdown) { item in
                    AreaMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Score", item.value)
                    )
                    .foregroundStyle(by: .value("Pillar", item.pillar))
                    .interpolationMethod(.catmullRom)
                }
                .chartForegroundStyleScale([
                    "Wealth": NC.teal,
                    "Health": Color.pink,
                    "Food": Color.orange,
                    "Routine": Color.blue
                ])
                .chartLegend(position: .top)
                .frame(height: 220)
            }
        }
    }

    // MARK: - Food Charts

    @ViewBuilder
    private var foodCharts: some View {
        // Meals logged per day
        chartCard(title: "Meals Logged", subtitle: "Last 30 days") {
            Chart(vm.mealsPerDay) { point in
                BarMark(
                    x: .value("Date", point.date, unit: .day),
                    y: .value("Meals", point.value)
                )
                .foregroundStyle(.orange.gradient)
                .cornerRadius(2)
            }
            .frame(height: 160)
        }

        // Home vs eating out stacked bar
        if !vm.homeVsOut.isEmpty {
            chartCard(title: "Home vs Eating Out", subtitle: "Meal source over time") {
                Chart(vm.homeVsOut) { item in
                    BarMark(
                        x: .value("Date", item.date, unit: .day),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(by: .value("Source", item.source))
                }
                .chartForegroundStyleScale([
                    "Home": NC.teal,
                    "Eating Out": Color.orange
                ])
                .chartLegend(position: .top)
                .frame(height: 180)
            }
        }
    }

    // MARK: - Chart Card Helper

    private func chartCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            content()
        }
        .card()
    }
}

#Preview {
    TrendChartsView()
}
