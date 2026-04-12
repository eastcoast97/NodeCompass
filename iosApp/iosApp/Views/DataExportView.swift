import SwiftUI
import UniformTypeIdentifiers

/// Data export sheet. Lets users export all their on-device data as JSON —
/// critical for a privacy-first app to fulfill the "your data, your ownership"
/// promise. Users can email the file to themselves or save to Files.
struct DataExportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: TransactionStore

    @State private var isGenerating = false
    @State private var generatedFileURL: URL?
    @State private var errorMessage: String?

    @State private var includeTransactions = true
    @State private var includeFood = true
    @State private var includeHealth = false  // Usually large; opt-in
    @State private var includeInsights = true
    @State private var includeGoals = true
    @State private var includeMoods = true
    @State private var includeAchievements = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Selection
                    selectionSection

                    // Actions
                    actionsSection

                    // Privacy note
                    privacyNote

                    Spacer(minLength: 32)
                }
                .padding(.horizontal, NC.hPad)
                .padding(.top, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Export Your Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Export failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(NC.teal.opacity(0.12))
                    .frame(width: 68, height: 68)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 30))
                    .foregroundStyle(NC.teal)
            }
            Text("Your data belongs to you")
                .font(.title3.bold())
            Text("Export everything NodeCompass has learned as a JSON file.\nNothing leaves your phone without your explicit tap.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }

    private var selectionSection: some View {
        VStack(spacing: 0) {
            sectionHeader("What to include")
            VStack(spacing: 0) {
                toggleRow(title: "Transactions", detail: "\(store.transactions.count) records", icon: "creditcard.fill", color: NC.teal, isOn: $includeTransactions)
                Divider().padding(.leading, NC.dividerIndent)
                toggleRow(title: "Food log", detail: "Meals, macros, staples", icon: "fork.knife", color: NC.food, isOn: $includeFood)
                Divider().padding(.leading, NC.dividerIndent)
                toggleRow(title: "Insights", detail: "Pattern engine output", icon: "lightbulb.fill", color: .orange, isOn: $includeInsights)
                Divider().padding(.leading, NC.dividerIndent)
                toggleRow(title: "Goals", detail: "Targets and progress", icon: "target", color: .pink, isOn: $includeGoals)
                Divider().padding(.leading, NC.dividerIndent)
                toggleRow(title: "Mood log", detail: "Daily check-ins", icon: "face.smiling", color: .purple, isOn: $includeMoods)
                Divider().padding(.leading, NC.dividerIndent)
                toggleRow(title: "Achievements", detail: "Earned badges, streaks", icon: "trophy.fill", color: .yellow, isOn: $includeAchievements)
                Divider().padding(.leading, NC.dividerIndent)
                toggleRow(title: "Health events", detail: "Warning: can be large", icon: "heart.fill", color: .red, isOn: $includeHealth)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            if let fileURL = generatedFileURL {
                ShareLink(item: fileURL) {
                    HStack {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("Share Export")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(NC.teal, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                }

                Button {
                    generatedFileURL = nil
                } label: {
                    Text("Generate a new export")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Haptic.light()
                    Task { await generateExport() }
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "doc.fill.badge.plus")
                        }
                        Text(isGenerating ? "Packaging your data..." : "Generate Export")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        (isGenerating ? Color.gray : NC.teal),
                        in: RoundedRectangle(cornerRadius: NC.cardRadius)
                    )
                }
                .disabled(isGenerating || !hasAnySelection)
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(NC.teal)
            VStack(alignment: .leading, spacing: 4) {
                Text("On-device export")
                    .font(.caption.bold())
                Text("The file is generated locally. NodeCompass never uploads your data anywhere. You choose where it goes next.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(NC.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: NC.cardRadius))
    }

    // MARK: - Helpers

    private var hasAnySelection: Bool {
        includeTransactions || includeFood || includeHealth || includeInsights ||
        includeGoals || includeMoods || includeAchievements
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    private func toggleRow(title: String, detail: String, icon: String, color: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: NC.iconRadius)
                    .fill(color.opacity(0.12))
                    .frame(width: NC.iconSize, height: NC.iconSize)
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(NC.teal)
        }
        .padding(.horizontal, NC.hPad)
        .padding(.vertical, NC.vPad)
    }

    // MARK: - Export Generation

    private func generateExport() async {
        isGenerating = true
        defer { isGenerating = false }

        do {
            var exportRoot: [String: Any] = [
                "app": "NodeCompass",
                "exportVersion": 1,
                "exportedAt": ISO8601DateFormatter().string(from: Date()),
            ]

            if includeTransactions {
                let txns = store.transactions.map { txn -> [String: Any] in
                    [
                        "id": txn.id,
                        "merchant": txn.merchant,
                        "amount": txn.amount,
                        "currencySymbol": txn.currencySymbol,
                        "category": txn.category,
                        "type": txn.type,
                        "source": txn.source,
                        "date": ISO8601DateFormatter().string(from: txn.date),
                        "description": txn.description as Any
                    ]
                }
                exportRoot["transactions"] = txns
            }

            if includeFood {
                let entries = await FoodStore.shared.entriesForMonth()
                exportRoot["food_month"] = entries.map { entry in
                    [
                        "id": entry.id,
                        "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                        "mealType": entry.mealType,
                        "source": String(describing: entry.source),
                        "locationName": entry.locationName as Any,
                        "totalCaloriesEstimate": entry.totalCaloriesEstimate as Any,
                        "totalSpent": entry.totalSpent as Any,
                        "items": entry.items.map { ["name": $0.name, "quantity": $0.quantity, "calories": $0.caloriesEstimate as Any] }
                    ]
                }
            }

            if includeInsights {
                let insights = await PatternEngine.shared.activeInsights()
                exportRoot["insights"] = insights.map { insight in
                    [
                        "id": insight.id,
                        "type": insight.type.rawValue,
                        "title": insight.title,
                        "body": insight.body,
                        "priority": insight.priority.rawValue,
                        "createdAt": ISO8601DateFormatter().string(from: insight.createdAt)
                    ]
                }
            }

            if includeGoals {
                let goals = await GoalStore.shared.allGoals()
                exportRoot["goals"] = goals.map { goal in
                    [
                        "id": goal.id,
                        "type": goal.type.rawValue,
                        "targetValue": goal.targetValue,
                        "isActive": goal.isActive,
                        "createdAt": ISO8601DateFormatter().string(from: goal.createdAt)
                    ]
                }
            }

            if includeMoods {
                let moods = await MoodStore.shared.recentEntries(days: 90)
                exportRoot["moods_90d"] = moods.map { entry in
                    [
                        "dateKey": entry.dateKey,
                        "mood": entry.mood.rawValue,
                        "note": entry.note as Any
                    ]
                }
            }

            if includeAchievements {
                let achievements = await AchievementEngine.shared.allAchievements()
                exportRoot["achievements"] = achievements.map { a in
                    [
                        "id": a.id,
                        "type": a.type.rawValue,
                        "title": a.title,
                        "earnedAt": ISO8601DateFormatter().string(from: a.earnedAt),
                        "pillar": a.pillar
                    ]
                }
            }

            if includeHealth {
                let events = await EventStore.shared.recentEvents(limit: 500)
                exportRoot["recent_events"] = events.map { e -> [String: Any] in
                    [
                        "id": e.id,
                        "timestamp": ISO8601DateFormatter().string(from: e.timestamp),
                        "source": String(describing: e.source)
                    ]
                }
            }

            let jsonData = try JSONSerialization.data(
                withJSONObject: exportRoot,
                options: [.prettyPrinted, .sortedKeys]
            )

            // Write to a temp file that ShareLink can hand to the user
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "nodecompass_export_\(formatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try jsonData.write(to: url, options: .atomic)

            await MainActor.run {
                Haptic.success()
                generatedFileURL = url
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't generate export: \(error.localizedDescription)"
            }
        }
    }
}
