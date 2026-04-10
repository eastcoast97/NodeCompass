import SwiftUI

/// Compact sheet for completing a pending food order.
/// Shows restaurant name, auto-selects meal type, suggests past items,
/// and lets the user type what they ate in one quick flow.
struct QuickFoodLogSheet: View {
    let pendingEntry: FoodStore.FoodLogEntry
    @StateObject private var vm: QuickFoodLogVM
    @Environment(\.dismiss) private var dismiss

    init(pendingEntry: FoodStore.FoodLogEntry) {
        self.pendingEntry = pendingEntry
        _vm = StateObject(wrappedValue: QuickFoodLogVM(entry: pendingEntry))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Restaurant header
                restaurantHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Meal type (auto-selected, tappable to change)
                mealTypePills
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                Divider()
                    .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 16) {
                        // Past items / suggestions
                        if !vm.suggestions.isEmpty {
                            suggestionsSection
                        }

                        // Added items
                        if !vm.items.isEmpty {
                            addedItemsSection
                        }

                        // Text input
                        addItemField
                    }
                    .padding(20)
                }

                // Bottom bar with calorie total + save
                bottomBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
            }
            .task { await vm.loadSuggestions() }
        }
    }

    // MARK: - Restaurant Header

    private var restaurantHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 50, height: 50)
                Image(systemName: "bag.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(vm.restaurant)
                    .font(.title3.bold())
                if let address = vm.restaurantAddress {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let spent = vm.totalSpent {
                    Text("$\(String(format: "%.2f", spent))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Meal Type Pills

    private var mealTypePills: some View {
        HStack(spacing: 8) {
            ForEach(MealType.allCases, id: \.self) { meal in
                Button {
                    withAnimation(.spring(response: 0.25)) { vm.selectedMealType = meal }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: meal.icon)
                            .font(.caption2)
                        Text(meal.rawValue.capitalized)
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        vm.selectedMealType == meal
                            ? meal.color.opacity(0.15)
                            : Color(.systemGray6)
                    )
                    .foregroundStyle(vm.selectedMealType == meal ? meal.color : .secondary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(vm.selectedMealType == meal ? meal.color.opacity(0.3) : .clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(vm.hasPastOrders ? "You usually order" : "Popular items")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 8) {
                ForEach(vm.suggestions, id: \.self) { suggestion in
                    Button {
                        vm.addSuggestion(suggestion)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vm.items.contains(where: { $0.name.lowercased() == suggestion.lowercased() })
                                  ? "checkmark.circle.fill" : "plus.circle")
                                .font(.caption2)
                            Text(suggestion)
                                .font(.subheadline)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            vm.items.contains(where: { $0.name.lowercased() == suggestion.lowercased() })
                                ? Color.orange.opacity(0.12)
                                : Color(.systemGray6)
                        )
                        .foregroundStyle(
                            vm.items.contains(where: { $0.name.lowercased() == suggestion.lowercased() })
                                ? .orange : .primary
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Added Items

    private var addedItemsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(vm.items.count) item\(vm.items.count == 1 ? "" : "s")")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ForEach(vm.items.indices, id: \.self) { idx in
                HStack(spacing: 10) {
                    Text(vm.items[idx].name)
                        .font(.subheadline)

                    if let cal = vm.items[idx].caloriesEstimate, cal > 0 {
                        Text("~\(cal) cal")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    // Qty stepper
                    HStack(spacing: 0) {
                        Button { vm.decrementItem(at: idx) } label: {
                            Image(systemName: "minus")
                                .font(.caption2.bold())
                                .frame(width: 26, height: 26)
                                .background(Color(.systemGray5), in: Circle())
                        }
                        Text("\(Int(vm.items[idx].amount))")
                            .font(.subheadline.bold())
                            .frame(minWidth: 28)
                        Button { vm.incrementItem(at: idx) } label: {
                            Image(systemName: "plus")
                                .font(.caption2.bold())
                                .frame(width: 26, height: 26)
                                .background(Color(.systemGray5), in: Circle())
                        }
                    }
                    .buttonStyle(.plain)

                    Button { vm.removeItem(at: idx) } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Add Item Field

    private var addItemField: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(NC.teal)
            TextField("Type a food item...", text: $vm.newItemText)
                .textFieldStyle(.plain)
                .submitLabel(.done)
                .onSubmit { vm.addCurrentItem() }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack {
                // Calorie summary
                if vm.totalCalories > 0 {
                    Text("~\(vm.totalCalories) cal")
                        .font(.subheadline.bold())
                        .foregroundStyle(.orange)
                } else {
                    Text("\(vm.items.count) item\(vm.items.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    vm.save()
                    dismiss()
                } label: {
                    Text("Log Meal")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(vm.items.isEmpty ? Color(.systemGray4) : NC.teal)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .disabled(vm.items.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
    }
}

// MARK: - Flow Layout (for suggestion chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxWidth = max(maxWidth, x)
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}

// MARK: - ViewModel

@MainActor
class QuickFoodLogVM: ObservableObject {
    @Published var selectedMealType: MealType
    @Published var items: [FoodItem] = []
    @Published var newItemText: String = ""
    @Published var suggestions: [String] = []
    @Published var hasPastOrders: Bool = false

    let restaurant: String
    let restaurantAddress: String?
    let totalSpent: Double?
    let pendingEntryId: String

    init(entry: FoodStore.FoodLogEntry) {
        self.restaurant = entry.locationName ?? "Food Order"
        self.restaurantAddress = entry.locationAddress
        self.totalSpent = entry.totalSpent
        self.pendingEntryId = entry.id

        // Auto-select meal type based on the order timestamp
        if let mt = MealType(rawValue: entry.mealType) {
            self.selectedMealType = mt
        } else {
            let hour = Calendar.current.component(.hour, from: entry.timestamp)
            switch hour {
            case 5..<11: self.selectedMealType = .breakfast
            case 11..<15: self.selectedMealType = .lunch
            case 15..<17: self.selectedMealType = .snack
            default: self.selectedMealType = .dinner
            }
        }
    }

    func loadSuggestions() async {
        // First: past items from this restaurant
        let pastItems = await FoodStore.shared.pastItemsFromRestaurant(restaurant)
        if !pastItems.isEmpty {
            hasPastOrders = true
            suggestions = Array(pastItems.prefix(8))
        } else {
            // Fallback: general staple suggestions for this meal type
            let staples = await FoodStore.shared.stapleSuggestions(for: selectedMealType.rawValue)
            if !staples.isEmpty {
                hasPastOrders = false
                suggestions = staples.map { $0.name }
            }
        }
    }

    func addSuggestion(_ name: String) {
        // Toggle — remove if already added
        if let idx = items.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            items.remove(at: idx)
            return
        }

        let nutrition = NutritionDatabase.estimate(name: name, amount: 1, unit: .qty)
        items.append(FoodItem(
            name: name,
            amount: 1,
            unit: .qty,
            caloriesEstimate: nutrition?.calories,
            macros: nutrition?.macros,
            isHomemade: false
        ))
    }

    func addCurrentItem() {
        let name = newItemText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard !items.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            newItemText = ""
            return
        }

        let nutrition = NutritionDatabase.estimate(name: name, amount: 1, unit: .qty)
        items.append(FoodItem(
            name: name,
            amount: 1,
            unit: .qty,
            caloriesEstimate: nutrition?.calories,
            macros: nutrition?.macros,
            isHomemade: false
        ))
        newItemText = ""
    }

    func incrementItem(at idx: Int) {
        guard idx < items.count else { return }
        let old = items[idx]
        let newAmt = old.amount + 1
        let nutrition = NutritionDatabase.estimate(name: old.name, amount: newAmt, unit: old.unit)
        items[idx] = FoodItem(
            name: old.name, amount: newAmt, unit: old.unit,
            caloriesEstimate: nutrition?.calories ?? old.caloriesEstimate,
            macros: nutrition?.macros ?? old.macros,
            isHomemade: false
        )
    }

    func decrementItem(at idx: Int) {
        guard idx < items.count else { return }
        let old = items[idx]
        let newAmt = max(1, old.amount - 1)
        let nutrition = NutritionDatabase.estimate(name: old.name, amount: newAmt, unit: old.unit)
        items[idx] = FoodItem(
            name: old.name, amount: newAmt, unit: old.unit,
            caloriesEstimate: nutrition?.calories ?? old.caloriesEstimate,
            macros: nutrition?.macros ?? old.macros,
            isHomemade: false
        )
    }

    func removeItem(at idx: Int) {
        guard idx < items.count else { return }
        items.remove(at: idx)
    }

    var totalCalories: Int {
        items.compactMap { $0.caloriesEstimate }.reduce(0, +)
    }

    func save() {
        guard !items.isEmpty else { return }
        Task {
            await FoodStore.shared.completePendingEntry(
                id: pendingEntryId,
                items: items,
                mealType: selectedMealType.rawValue,
                portionNote: nil
            )
        }
    }
}
