import SwiftUI

/// Monthly Wrapped — Spotify Wrapped-style summary of the month.
struct MonthlyWrappedView: View {
    @StateObject private var vm = MonthlyWrappedViewModel()
    @State private var currentSlide = 0

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background
                LinearGradient(
                    colors: slideGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: currentSlide)

                if let w = vm.wrapped {
                    VStack(spacing: 0) {
                        // Slide content
                        TabView(selection: $currentSlide) {
                            overviewSlide(w).tag(0)
                            wealthSlide(w).tag(1)
                            healthSlide(w).tag(2)
                            foodSlide(w).tag(3)
                            funFactsSlide(w).tag(4)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))

                        // Page dots
                        HStack(spacing: 8) {
                            ForEach(0..<5, id: \.self) { i in
                                Circle()
                                    .fill(i == currentSlide ? .white : .white.opacity(0.3))
                                    .frame(width: i == currentSlide ? 8 : 6, height: i == currentSlide ? 8 : 6)
                                    .animation(.spring(response: 0.3), value: currentSlide)
                            }
                        }
                        .padding(.bottom, 12)

                        // Share button
                        Button {
                            Haptic.medium()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                Text("Share")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(.white.opacity(0.2), in: Capsule())
                        }
                        .padding(.bottom, 40)
                    }
                } else {
                    VStack(spacing: 14) {
                        ProgressView().tint(.white)
                        Text("Building your monthly wrapped...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(vm.wrapped?.monthName ?? "Monthly Wrapped")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
            }
            .task { await vm.load() }
        }
    }

    // MARK: - Slide Gradients

    private var slideGradient: [Color] {
        switch currentSlide {
        case 0: return [Color(red: 0.1, green: 0.2, blue: 0.4), Color(red: 0.05, green: 0.1, blue: 0.25)]
        case 1: return [Color(red: 0.05, green: 0.35, blue: 0.35), Color(red: 0.02, green: 0.2, blue: 0.2)]
        case 2: return [Color(red: 0.4, green: 0.1, blue: 0.2), Color(red: 0.25, green: 0.05, blue: 0.12)]
        case 3: return [Color(red: 0.4, green: 0.2, blue: 0.05), Color(red: 0.25, green: 0.12, blue: 0.02)]
        case 4: return [Color(red: 0.15, green: 0.1, blue: 0.35), Color(red: 0.08, green: 0.05, blue: 0.2)]
        default: return [NC.deepNavy, NC.slate]
        }
    }

    // MARK: - Slide 0: Overview

    private func overviewSlide(_ w: MonthlyWrappedEngine.MonthlyWrapped) -> some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text("Your")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(w.monthName)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                Text("Wrapped")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Big stat
            VStack(spacing: 8) {
                Text("\(w.avgLifeScore)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Average Life Score")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }

            if w.achievementsEarned > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                    Text("\(w.achievementsEarned) achievements earned")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            Spacer()
        }
    }

    // MARK: - Slide 1: Wealth

    private func wealthSlide(_ w: MonthlyWrappedEngine.MonthlyWrapped) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: NC.currencyIconCircle)
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))

            VStack(spacing: 8) {
                Text("You spent")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                Text(NC.money(w.totalSpent))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("across \(w.transactionCount) transactions")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(spacing: 16) {
                wrappedStat("Top merchant", value: w.topMerchant, sub: "\(w.topMerchantVisits) visits • \(NC.money(w.topMerchantSpent))")
                wrappedStat("Top category", value: w.topCategory, sub: NC.money(w.topCategorySpent))
                if w.totalSaved > 0 {
                    wrappedStat("Saved", value: NC.money(w.totalSaved), sub: nil)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Slide 2: Health

    private func healthSlide(_ w: MonthlyWrappedEngine.MonthlyWrapped) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "heart.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))

            VStack(spacing: 8) {
                Text("You walked")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                Text(String(format: "%.1f km", w.totalDistanceKm))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(w.totalSteps.formatted()) total steps")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(spacing: 16) {
                wrappedStat("Daily average", value: "\(w.avgDailySteps.formatted()) steps", sub: nil)
                wrappedStat("Workouts", value: "\(w.totalWorkouts)", sub: "\(w.longestWorkoutStreak)-day best streak")
                if w.avgSleepHours > 0 {
                    wrappedStat("Avg sleep", value: String(format: "%.1f hrs", w.avgSleepHours), sub: nil)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Slide 3: Food

    private func foodSlide(_ w: MonthlyWrappedEngine.MonthlyWrapped) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))

            VStack(spacing: 8) {
                Text("You logged")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(w.totalMealsLogged)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("meals this month")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(spacing: 16) {
                wrappedStat("Home-cooked", value: "\(w.homeMeals)", sub: "out of \(w.totalMealsLogged) total")
                wrappedStat("Eating out", value: "\(w.eatingOutCount) times", sub: nil)
                if let staple = w.topStapleFood {
                    wrappedStat("Your staple", value: staple.capitalized, sub: nil)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Slide 4: Fun Facts

    private func funFactsSlide(_ w: MonthlyWrappedEngine.MonthlyWrapped) -> some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.yellow.opacity(0.8))

            Text("Fun Facts")
                .font(.title2.bold())
                .foregroundStyle(.white)

            VStack(spacing: 16) {
                ForEach(w.funFacts, id: \.self) { fact in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow.opacity(0.6))
                            .padding(.top, 3)
                        Text(fact)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 8)

            if w.daysAbove80 > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text("\(w.daysAbove80) days scoring 80+")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Helper

    private func wrappedStat(_ label: String, value: String, sub: String?) -> some View {
        VStack(spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)
            Text(value)
                .font(.headline)
                .foregroundStyle(.white)
            if let sub {
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class MonthlyWrappedViewModel: ObservableObject {
    @Published var wrapped: MonthlyWrappedEngine.MonthlyWrapped?

    func load() async {
        wrapped = await MonthlyWrappedEngine.shared.generateWrapped()
    }
}
