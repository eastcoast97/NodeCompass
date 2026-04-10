import SwiftUI

/// "What If" simulator — shows projected impact of behavioral changes.
struct WhatIfView: View {
    @StateObject private var vm = WhatIfViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(.blue.opacity(0.1))
                                .frame(width: 72, height: 72)
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 30))
                                .foregroundStyle(.blue)
                        }
                        Text("What If...")
                            .font(.title3.bold())
                        Text("See how small changes could transform your life")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    if vm.scenarios.isEmpty {
                        VStack(spacing: 14) {
                            ProgressView()
                            Text("Analyzing your patterns...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)
                    } else {
                        // Total potential
                        if vm.totalMonthlySavings > 0 {
                            totalPotentialCard
                        }

                        // Scenarios
                        ForEach(vm.scenarios) { scenario in
                            scenarioCard(scenario)
                        }
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("What If")
            .navigationBarTitleDisplayMode(.inline)
            .task { await vm.load() }
        }
    }

    // MARK: - Total Potential

    private var totalPotentialCard: some View {
        VStack(spacing: 12) {
            Text("Total Potential Impact")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                VStack(spacing: 4) {
                    Text(NC.money(vm.totalMonthlySavings))
                        .font(.title2.bold())
                        .foregroundStyle(.green)
                    Text("/month")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text(NC.money(vm.totalYearlySavings))
                        .font(.title2.bold())
                        .foregroundStyle(NC.teal)
                    Text("/year")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 4) {
                    Text("+\(vm.totalScoreImpact)")
                        .font(.title2.bold())
                        .foregroundStyle(.blue)
                    Text("score pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(NC.hPad)
        .background(
            LinearGradient(colors: [NC.teal.opacity(0.08), .blue.opacity(0.08)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: NC.cardRadius)
        )
    }

    // MARK: - Scenario Card

    private func scenarioCard(_ s: WhatIfSimulator.Scenario) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: NC.iconRadius, style: .continuous)
                        .fill(pillarColor(s.pillar).opacity(0.12))
                        .frame(width: NC.iconSize, height: NC.iconSize)
                    Image(systemName: s.icon)
                        .font(.subheadline)
                        .foregroundStyle(pillarColor(s.pillar))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title)
                        .font(.subheadline.bold())
                    Text(s.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }

            // Impact row
            HStack(spacing: 0) {
                if s.monthlySavings > 0 {
                    impactPill(label: NC.money(s.monthlySavings) + "/mo", color: .green)
                }
                if s.yearlySavings > 0 {
                    impactPill(label: NC.money(s.yearlySavings) + "/yr", color: NC.teal)
                }
                if s.scoreImpact > 0 {
                    impactPill(label: "+\(s.scoreImpact) score", color: .blue)
                }
                Spacer()
            }

            // Before → After
            if s.monthlySavings > 0 || s.currentValue != s.projectedValue {
                HStack {
                    VStack(spacing: 2) {
                        Text("Now")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatValue(s.currentValue, scenario: s))
                            .font(.caption.bold())
                            .foregroundStyle(NC.spend)
                    }
                    .frame(maxWidth: .infinity)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 2) {
                        Text("Target")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(formatValue(s.projectedValue, scenario: s))
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: NC.iconRadius))
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    private func impactPill(label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
            .padding(.trailing, 6)
    }

    private func formatValue(_ value: Double, scenario: WhatIfSimulator.Scenario) -> String {
        switch scenario.type {
        case .cutDiningOut, .cancelGhostSubs, .reduceShopping, .increaseIncome:
            return NC.money(value)
        case .cookMoreAtHome:
            return "\(Int(value))%"
        case .walkMore:
            return "\(Int(value).formatted()) steps"
        case .sleepBetter:
            return String(format: "%.1f hrs", value)
        case .workoutMore:
            return String(format: "%.0fx/week", value)
        }
    }

    private func pillarColor(_ pillar: String) -> Color {
        switch pillar {
        case "wealth": return NC.teal
        case "health": return .pink
        case "food": return NC.food
        default: return .blue
        }
    }
}

// MARK: - ViewModel

@MainActor
class WhatIfViewModel: ObservableObject {
    @Published var scenarios: [WhatIfSimulator.Scenario] = []

    var totalMonthlySavings: Double {
        scenarios.reduce(0) { $0 + $1.monthlySavings }
    }
    var totalYearlySavings: Double {
        scenarios.reduce(0) { $0 + $1.yearlySavings }
    }
    var totalScoreImpact: Int {
        scenarios.reduce(0) { $0 + $1.scoreImpact }
    }

    func load() async {
        scenarios = await WhatIfSimulator.generateScenarios()
    }
}
