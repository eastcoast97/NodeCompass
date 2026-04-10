import SwiftUI

/// Quick mood check-in — one tap to log how you feel.
struct MoodCheckInView: View {
    @StateObject private var vm = MoodCheckInViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Today's mood (or log prompt)
                    if let today = vm.todaysMood {
                        todayCard(today)
                    } else {
                        logPrompt
                    }

                    // Mood trend
                    if !vm.recentMoods.isEmpty {
                        trendSection
                    }

                    // Correlations
                    if !vm.correlations.isEmpty {
                        correlationsSection
                    }

                    // History
                    if !vm.recentMoods.isEmpty {
                        historySection
                    }
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Mood")
            .navigationBarTitleDisplayMode(.large)
            .task { await vm.load() }
        }
    }

    // MARK: - Log Prompt

    private var logPrompt: some View {
        VStack(spacing: 16) {
            Text("How are you feeling?")
                .font(.title3.bold())

            HStack(spacing: 12) {
                ForEach(MoodStore.MoodLevel.allCases, id: \.rawValue) { mood in
                    Button {
                        Haptic.medium()
                        Task {
                            await vm.logMood(mood)
                            Haptic.success()
                        }
                    } label: {
                        VStack(spacing: 6) {
                            Text(mood.emoji)
                                .font(.system(size: 36))
                            Text(mood.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            vm.selectedMood == mood
                                ? moodColor(mood).opacity(0.15)
                                : Color(.systemGray6),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(vm.selectedMood == mood ? moodColor(mood) : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if vm.streak > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("\(vm.streak)-day check-in streak")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Today Card

    private func todayCard(_ entry: MoodStore.MoodEntry) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(entry.mood.emoji)
                    .font(.system(size: 44))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Today: \(entry.mood.label)")
                        .font(.headline)
                    Text("Logged \(timeAgo(entry.date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if vm.streak > 0 {
                    VStack(spacing: 2) {
                        Text("\(vm.streak)")
                            .font(.title3.bold())
                            .foregroundStyle(.orange)
                        Image(systemName: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            // Quick re-log option
            HStack(spacing: 8) {
                Text("Update:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(MoodStore.MoodLevel.allCases, id: \.rawValue) { mood in
                    Button {
                        Haptic.light()
                        Task { await vm.logMood(mood) }
                    } label: {
                        Text(mood.emoji)
                            .font(.title3)
                            .padding(4)
                            .background(
                                entry.mood == mood ? moodColor(mood).opacity(0.15) : .clear,
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Trend

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(NC.teal)
                Text("Last 7 Days")
                    .font(.subheadline.bold())
                Spacer()

                let trend = vm.moodTrend
                if trend != 0 {
                    HStack(spacing: 4) {
                        Image(systemName: trend > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.bold())
                        Text(trend > 0 ? "Improving" : "Declining")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(trend > 0 ? .green : NC.spend)
                }
            }

            // Mood dots timeline
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { dayOffset in
                    let date = Calendar.current.date(byAdding: .day, value: -(6 - dayOffset), to: Date())!
                    let entry = vm.entryForDate(date)

                    VStack(spacing: 6) {
                        if let entry {
                            Text(entry.mood.emoji)
                                .font(.title3)
                        } else {
                            Circle()
                                .fill(Color(.systemGray4))
                                .frame(width: 10, height: 10)
                        }

                        Text(dayLabel(date))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Average
            HStack(spacing: 6) {
                Text("Avg:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.1f", vm.avgMood))
                    .font(.caption.bold())
                Text("/ 5")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Correlations

    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                Text("What Affects Your Mood")
                    .font(.subheadline.bold())
            }

            ForEach(vm.correlations) { correlation in
                HStack(spacing: 12) {
                    Image(systemName: correlation.icon)
                        .font(.caption)
                        .foregroundStyle(impactColor(correlation.impact))
                        .frame(width: 32, height: 32)
                        .background(impactColor(correlation.impact).opacity(0.1), in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(correlation.factor)
                                .font(.caption.bold())
                            Text(correlation.impact == .positive ? "+" : "−")
                                .font(.caption.bold())
                                .foregroundStyle(impactColor(correlation.impact))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(impactColor(correlation.impact).opacity(0.1), in: Capsule())
                        }
                        Text(correlation.insight)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    // Confidence bar
                    VStack(spacing: 2) {
                        Text("\(Int(correlation.confidence * 100))%")
                            .font(.system(size: 9).bold())
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.subheadline.bold())

            ForEach(vm.recentMoods.prefix(14)) { entry in
                HStack(spacing: 12) {
                    Text(entry.mood.emoji)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.mood.label)
                            .font(.caption.bold())
                        if let note = entry.note, !note.isEmpty {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Text(dateLabel(entry.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(NC.hPad)
        .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
    }

    // MARK: - Helpers

    private func moodColor(_ mood: MoodStore.MoodLevel) -> Color {
        switch mood {
        case .terrible: return NC.spend
        case .bad: return .orange
        case .okay: return .yellow
        case .good: return NC.teal
        case .great: return .green
        }
    }

    private func impactColor(_ impact: MoodStore.MoodCorrelation.Impact) -> Color {
        switch impact {
        case .positive: return .green
        case .negative: return NC.spend
        case .neutral: return .secondary
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func dateLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    private func timeAgo(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - ViewModel

@MainActor
class MoodCheckInViewModel: ObservableObject {
    @Published var todaysMood: MoodStore.MoodEntry?
    @Published var recentMoods: [MoodStore.MoodEntry] = []
    @Published var correlations: [MoodStore.MoodCorrelation] = []
    @Published var avgMood: Double = 0
    @Published var moodTrend: Int = 0
    @Published var streak: Int = 0
    @Published var selectedMood: MoodStore.MoodLevel?

    func load() async {
        todaysMood = await MoodStore.shared.todaysMood()
        recentMoods = await MoodStore.shared.recentEntries(days: 30)
        correlations = await MoodStore.shared.analyzeCorrelations()
        avgMood = await MoodStore.shared.averageMood(days: 7)
        moodTrend = await MoodStore.shared.moodTrend()
        streak = await MoodStore.shared.streakDays()
    }

    func logMood(_ mood: MoodStore.MoodLevel) async {
        selectedMood = mood
        await MoodStore.shared.logMood(mood)
        await load()
    }

    func entryForDate(_ date: Date) -> MoodStore.MoodEntry? {
        let cal = Calendar.current
        return recentMoods.first { cal.isDate($0.date, inSameDayAs: date) }
    }
}
