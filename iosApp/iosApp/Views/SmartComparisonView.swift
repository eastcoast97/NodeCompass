import SwiftUI

/// Week-over-week comparison view — "How am I doing vs last week?"
struct SmartComparisonView: View {
    @StateObject private var vm = SmartComparisonViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let c = vm.comparison {
                        // Overall score comparison
                        scoreCompare(c)

                        // Pillar comparisons
                        pillarCard(
                            icon: NC.currencyIcon, title: "Spending", color: NC.teal,
                            thisWeek: NC.money(c.thisWeekSpent),
                            lastWeek: NC.money(c.lastWeekSpent),
                            change: c.spendChange,
                            lowerIsBetter: true
                        )

                        pillarCard(
                            icon: "shoeprints.fill", title: "Steps", color: .pink,
                            thisWeek: "\(c.thisWeekSteps.formatted())",
                            lastWeek: "\(c.lastWeekSteps.formatted())",
                            change: c.stepsChange,
                            lowerIsBetter: false
                        )

                        pillarCard(
                            icon: "figure.run", title: "Workouts", color: .orange,
                            thisWeek: "\(c.thisWeekWorkouts)",
                            lastWeek: "\(c.lastWeekWorkouts)",
                            change: c.lastWeekWorkouts > 0 ? Double(c.thisWeekWorkouts - c.lastWeekWorkouts) / Double(c.lastWeekWorkouts) * 100 : 0,
                            lowerIsBetter: false
                        )

                        pillarCard(
                            icon: "moon.zzz.fill", title: "Sleep", color: .indigo,
                            thisWeek: String(format: "%.1fh", c.thisWeekSleep),
                            lastWeek: String(format: "%.1fh", c.lastWeekSleep),
                            change: c.lastWeekSleep > 0 ? (c.thisWeekSleep - c.lastWeekSleep) / c.lastWeekSleep * 100 : 0,
                            lowerIsBetter: false
                        )

                        pillarCard(
                            icon: "frying.pan.fill", title: "Home Meals", color: NC.food,
                            thisWeek: "\(c.thisWeekHomeMeals)",
                            lastWeek: "\(c.lastWeekHomeMeals)",
                            change: c.lastWeekHomeMeals > 0 ? Double(c.thisWeekHomeMeals - c.lastWeekHomeMeals) / Double(c.lastWeekHomeMeals) * 100 : 0,
                            lowerIsBetter: false
                        )

                        // Spending prediction
                        if let pred = vm.prediction {
                            predictionCard(pred)
                        }
                    } else {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text("Comparing your weeks...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 60)
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("This Week vs Last")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
        }
    }

    // MARK: - Score Comparison

    private func scoreCompare(_ c: ComparisonEngine.WeekComparison) -> some View {
        HStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Last Week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(c.lastWeekAvgScore)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Image(systemName: c.scoreChange >= 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(c.scoreChange >= 0 ? .green : NC.spend)
                Text(c.scoreChange >= 0 ? "+\(c.scoreChange)" : "\(c.scoreChange)")
                    .font(.caption.bold())
                    .foregroundStyle(c.scoreChange >= 0 ? .green : NC.spend)
            }

            VStack(spacing: 6) {
                Text("This Week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(c.thisWeekAvgScore)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(c.scoreChange >= 0 ? .green : NC.spend)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Pillar Card

    private func pillarCard(icon: String, title: String, color: Color, thisWeek: String, lastWeek: String, change: Double, lowerIsBetter: Bool) -> some View {
        let improved = lowerIsBetter ? change < 0 : change > 0

        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                HStack(spacing: 8) {
                    Text(lastWeek)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                    Text(thisWeek)
                        .font(.caption.bold())
                        .foregroundStyle(improved ? .green : (change == 0 ? .secondary : NC.spend))
                }
            }

            Spacer()

            if change != 0 {
                HStack(spacing: 4) {
                    Image(systemName: improved ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.bold())
                    Text("\(abs(Int(change)))%")
                        .font(.caption.bold())
                }
                .foregroundStyle(improved ? .green : NC.spend)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((improved ? Color.green : NC.spend).opacity(0.1), in: Capsule())
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Spending Prediction

    private func predictionCard(_ p: SpendingPredictor.Prediction) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                Text("Month-End Projection")
                    .font(.subheadline.bold())
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text(NC.money(p.projectedTotal))
                        .font(.headline)
                        .foregroundStyle(p.isOverPace ? NC.spend : NC.teal)
                    Text("Projected")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("\(p.daysLeft)")
                        .font(.headline)
                    Text("Days Left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text(NC.money(p.dailyBudgetRemaining))
                        .font(.headline)
                        .foregroundStyle(p.dailyBudgetRemaining > 0 ? .green : NC.spend)
                    Text("/day left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Pace indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(p.isOverPace ? NC.spend : .green)
                    .frame(width: 6, height: 6)
                Text(p.isOverPace
                     ? "Over pace by \(Int(abs(p.percentOverUnder)))%"
                     : "Under budget — on track")
                    .font(.caption)
                    .foregroundStyle(p.isOverPace ? NC.spend : .green)
            }

            if p.projectedSavings > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "banknote.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Projected savings: \(NC.money(p.projectedSavings))")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }
}

// MARK: - ViewModel

@MainActor
class SmartComparisonViewModel: ObservableObject {
    @Published var comparison: ComparisonEngine.WeekComparison?
    @Published var prediction: SpendingPredictor.Prediction?

    func load() async {
        comparison = await ComparisonEngine.weekOverWeek()
        prediction = await SpendingPredictor.predict()
    }
}
