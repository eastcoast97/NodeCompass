import SwiftUI

// MARK: - Food Log View

struct FoodLogView: View {
    @StateObject private var vm: FoodLogViewModel
    @StateObject private var voice = VoiceFoodParser()
    @Environment(\.dismiss) private var dismiss
    @State private var showVoiceSheet = false

    /// Default init — fresh food log.
    init() {
        _vm = StateObject(wrappedValue: FoodLogViewModel())
    }

    /// Init with a pending entry to complete (from food delivery detection).
    init(pendingEntry: FoodStore.FoodLogEntry) {
        _vm = StateObject(wrappedValue: FoodLogViewModel(pendingEntry: pendingEntry))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Pre-fill banner for pending orders
                    if let restaurant = vm.pendingRestaurant {
                        HStack(spacing: 10) {
                            Image(systemName: "bag.fill")
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Order from \(restaurant)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let spent = vm.pendingSpent {
                                    Text("$\(String(format: "%.2f", spent))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("Add what you ate")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    mealTypePicker

                    // Voice input button
                    voiceInputButton

                    if !vm.stapleSuggestions.isEmpty {
                        stapleSuggestionsSection
                    }

                    itemsSection

                    addItemSection

                    if !vm.items.isEmpty {
                        portionSection
                        macroSummary
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(vm.pendingEntryId != nil ? "Complete Order" : "Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { vm.save(); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(vm.items.isEmpty)
                }
            }
            .task { await vm.loadStaples() }
            .sheet(isPresented: $showVoiceSheet) {
                VoiceInputSheet(voice: voice) { items in
                    vm.items.append(contentsOf: items)
                }
                .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Voice Input Button

    private var voiceInputButton: some View {
        Button { showVoiceSheet = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(NC.teal, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice Input")
                        .font(.subheadline.bold())
                    Text("Say what you ate — \"2 rotis and chicken 200g\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meal Type Picker

    private var mealTypePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meal")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                ForEach(MealType.allCases, id: \.self) { meal in
                    Button {
                        withAnimation(.spring(response: 0.3)) { vm.selectedMealType = meal }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: meal.icon)
                                .font(.title3)
                            Text(meal.rawValue.capitalized)
                                .font(.caption.bold())
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            vm.selectedMealType == meal
                                ? meal.color.opacity(0.15)
                                : Color(.systemGray6)
                        )
                        .foregroundStyle(vm.selectedMealType == meal ? meal.color : .secondary)
                        .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous)
                                .stroke(vm.selectedMealType == meal ? meal.color.opacity(0.4) : .clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Staple Suggestions

    private var stapleSuggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.orange)
                Text("Your Staples")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.stapleSuggestions, id: \.name) { staple in
                        Button { vm.addStaple(staple) } label: {
                            HStack(spacing: 6) {
                                Text(staple.name)
                                    .font(.subheadline)
                                if let cal = staple.caloriesEstimate {
                                    Text("\(cal) cal")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Items Section

    private var itemsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !vm.items.isEmpty {
                Text("Items")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                ForEach(vm.items.indices, id: \.self) { idx in
                    FoodItemRow(item: vm.items[idx],
                                onIncrement: { vm.adjustAmount(at: idx, delta: vm.items[idx].unit.stepSize) },
                                onDecrement: { vm.adjustAmount(at: idx, delta: -vm.items[idx].unit.stepSize) },
                                onRemove: { vm.removeItem(at: idx) })
                }
            }
        }
    }

    // MARK: - Add Item Section

    private var addItemSection: some View {
        VStack(spacing: 12) {
            // Name + unit detection
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(NC.teal)
                TextField("Add food item...", text: $vm.newItemName)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit { vm.addCurrentItem() }
                    .onChange(of: vm.newItemName) { vm.detectUnit() }
            }
            .padding(12)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))

            // Amount + Unit + Homemade row
            if !vm.newItemName.isEmpty {
                HStack(spacing: 10) {
                    // Amount field
                    HStack(spacing: 4) {
                        TextField("Amt", value: $vm.newItemAmount, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 50)
                            .multilineTextAlignment(.center)
                        Text(vm.newItemUnit.label)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 8))

                    // Unit picker
                    Picker("Unit", selection: $vm.newItemUnit) {
                        ForEach(FoodUnit.allCases, id: \.self) { u in
                            Text(u.label).tag(u)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)

                    Spacer()

                    // Homemade toggle
                    Button {
                        vm.newItemHomemade.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: vm.newItemHomemade ? "house.fill" : "house")
                                .font(.caption)
                            Text(vm.newItemHomemade ? "Home" : "Out")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(vm.newItemHomemade ? .green : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(vm.newItemHomemade ? .green.opacity(0.1) : Color(.systemGray6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Preview macros for current item
                if let preview = vm.previewNutrition {
                    HStack(spacing: 12) {
                        MacroPill(label: "Cal", value: "\(preview.calories)", color: .orange)
                        MacroPill(label: "P", value: String(format: "%.0f", preview.macros.protein), color: .red)
                        MacroPill(label: "C", value: String(format: "%.0f", preview.macros.carbs), color: .blue)
                        MacroPill(label: "F", value: String(format: "%.0f", preview.macros.fat), color: .yellow)
                        MacroPill(label: "Fb", value: String(format: "%.0f", preview.macros.fiber), color: .green)
                    }
                    .padding(.vertical, 4)
                }

                Button { vm.addCurrentItem() } label: {
                    Text("Add \(vm.newItemName)")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(NC.teal.opacity(0.12))
                        .foregroundStyle(NC.teal)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Portion Note

    private var portionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Portion Note (optional)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("e.g. 2 out of 4 slices", text: $vm.portionNote)
                .textFieldStyle(.plain)
                .padding(10)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Macro Summary

    private var macroSummary: some View {
        VStack(spacing: 14) {
            Divider()

            // Calorie total
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(vm.items.count) item\(vm.items.count == 1 ? "" : "s")")
                        .font(.subheadline)
                    Text("~\(vm.totalCalories) calories")
                        .font(.headline.bold())
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text(vm.selectedMealType.rawValue.capitalized)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(vm.selectedMealType.color.opacity(0.12))
                    .foregroundStyle(vm.selectedMealType.color)
                    .clipShape(Capsule())
            }

            // Macro bars
            if vm.totalMacros != .zero {
                VStack(spacing: 10) {
                    MacroBar(label: "Protein", grams: vm.totalMacros.protein, color: .red, total: vm.macroTotal)
                    MacroBar(label: "Carbs", grams: vm.totalMacros.carbs, color: .blue, total: vm.macroTotal)
                    MacroBar(label: "Fat", grams: vm.totalMacros.fat, color: .yellow, total: vm.macroTotal)
                    MacroBar(label: "Fiber", grams: vm.totalMacros.fiber, color: .green, total: vm.macroTotal)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
            }
        }
    }
}

// MARK: - Food Item Row

private struct FoodItemRow: View {
    let item: FoodItem
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.bold())
                    HStack(spacing: 8) {
                        Text(amountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let cal = item.caloriesEstimate, cal > 0 {
                            Text("\(cal) cal")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if item.isHomemade {
                            Text("Home")
                                .font(.system(size: 9).bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.green.opacity(0.1), in: Capsule())
                        }
                    }
                }

                Spacer()

                // Amount stepper
                HStack(spacing: 0) {
                    Button(action: onDecrement) {
                        Image(systemName: "minus")
                            .font(.caption.bold())
                            .frame(width: 28, height: 28)
                            .background(Color(.systemGray5), in: Circle())
                    }
                    Text(amountDisplay)
                        .font(.subheadline.bold())
                        .frame(minWidth: 36)
                    Button(action: onIncrement) {
                        Image(systemName: "plus")
                            .font(.caption.bold())
                            .frame(width: 28, height: 28)
                            .background(Color(.systemGray5), in: Circle())
                    }
                }
                .buttonStyle(.plain)

                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Inline macro chips
            if let m = item.macros, m != .zero {
                HStack(spacing: 8) {
                    MacroPill(label: "P", value: String(format: "%.0f", m.protein), color: .red)
                    MacroPill(label: "C", value: String(format: "%.0f", m.carbs), color: .blue)
                    MacroPill(label: "F", value: String(format: "%.0f", m.fat), color: .yellow)
                    MacroPill(label: "Fb", value: String(format: "%.0f", m.fiber), color: .green)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private var amountLabel: String {
        let amt = item.amount == floor(item.amount) ? "\(Int(item.amount))" : String(format: "%.0f", item.amount)
        return "\(amt) \(item.unit.label)"
    }

    private var amountDisplay: String {
        item.amount == floor(item.amount) ? "\(Int(item.amount))" : String(format: "%.0f", item.amount)
    }
}

// MARK: - Macro Pill (compact inline)

private struct MacroPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9).bold())
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 10).bold())
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Macro Bar (summary)

struct MacroBar: View {
    let label: String
    let grams: Double
    let color: Color
    let total: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .frame(width: 50, alignment: .leading)

            GeometryReader { geo in
                let fraction = total > 0 ? min(grams / total, 1) : 0
                RoundedRectangle(cornerRadius: 4)
                    .fill(color.opacity(0.2))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: geo.size.width * fraction)
                    }
            }
            .frame(height: 8)

            Text(String(format: "%.0fg", grams))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Meal Type

enum MealType: String, CaseIterable {
    case breakfast, lunch, snack, dinner

    var icon: String {
        switch self {
        case .breakfast: return "sun.horizon.fill"
        case .lunch: return "sun.max.fill"
        case .snack: return "cup.and.saucer.fill"
        case .dinner: return "moon.fill"
        }
    }

    var color: Color {
        switch self {
        case .breakfast: return .orange
        case .lunch: return .yellow
        case .snack: return .mint
        case .dinner: return .indigo
        }
    }
}

// MARK: - FoodUnit Step Size

extension FoodUnit {
    var stepSize: Double {
        switch self {
        case .qty: return 1
        case .grams: return 50
        case .ml: return 50
        }
    }

    var defaultAmount: Double {
        switch self {
        case .qty: return 1
        case .grams: return 100
        case .ml: return 200
        }
    }
}

// MARK: - Food Log ViewModel

@MainActor
class FoodLogViewModel: ObservableObject {
    @Published var selectedMealType: MealType = .breakfast
    @Published var items: [FoodItem] = []
    @Published var newItemName: String = ""
    @Published var newItemAmount: Double = 1
    @Published var newItemUnit: FoodUnit = .qty
    @Published var newItemHomemade: Bool = true
    @Published var portionNote: String = ""
    @Published var stapleSuggestions: [StapleFood] = []

    // Pending entry pre-fill data
    var pendingEntryId: String?
    var pendingRestaurant: String?
    var pendingSpent: Double?

    /// Fresh food log.
    init() {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: selectedMealType = .breakfast
        case 11..<15: selectedMealType = .lunch
        case 15..<17: selectedMealType = .snack
        default: selectedMealType = .dinner
        }
    }

    /// Pre-filled from a pending food delivery order.
    init(pendingEntry: FoodStore.FoodLogEntry) {
        self.pendingEntryId = pendingEntry.id
        self.pendingRestaurant = pendingEntry.locationName
        self.pendingSpent = pendingEntry.totalSpent
        self.newItemHomemade = false  // Delivery = not homemade

        // Set meal type from the pending entry
        if let mt = MealType(rawValue: pendingEntry.mealType) {
            self.selectedMealType = mt
        } else {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<11: self.selectedMealType = .breakfast
            case 11..<15: self.selectedMealType = .lunch
            case 15..<17: self.selectedMealType = .snack
            default: self.selectedMealType = .dinner
            }
        }
    }

    func loadStaples() async {
        let suggestions = await FoodStore.shared.stapleSuggestions(for: selectedMealType.rawValue)
        stapleSuggestions = suggestions
    }

    /// Auto-detect unit and default amount when food name changes.
    func detectUnit() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let detected = NutritionDatabase.detectUnit(for: name)
        if detected != newItemUnit {
            newItemUnit = detected
            newItemAmount = detected.defaultAmount
        }
    }

    /// Preview nutrition for the item being typed.
    var previewNutrition: (calories: Int, macros: Macros)? {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        return NutritionDatabase.estimate(name: name, amount: newItemAmount, unit: newItemUnit)
    }

    func addCurrentItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let nutrition = NutritionDatabase.estimate(name: name, amount: newItemAmount, unit: newItemUnit)

        items.append(FoodItem(
            name: name,
            amount: newItemAmount,
            unit: newItemUnit,
            caloriesEstimate: nutrition?.calories,
            macros: nutrition?.macros,
            isHomemade: newItemHomemade
        ))
        newItemName = ""
        newItemAmount = 1
        newItemUnit = .qty
    }

    func addStaple(_ staple: StapleFood) {
        guard !items.contains(where: { $0.name.lowercased() == staple.name.lowercased() }) else { return }
        let unit = NutritionDatabase.detectUnit(for: staple.name)
        let defaultAmt = unit.defaultAmount
        let nutrition = NutritionDatabase.estimate(name: staple.name, amount: defaultAmt, unit: unit)

        items.append(FoodItem(
            name: staple.name,
            amount: defaultAmt,
            unit: unit,
            caloriesEstimate: nutrition?.calories ?? staple.caloriesEstimate,
            macros: nutrition?.macros,
            isHomemade: staple.isHomemade
        ))
    }

    func adjustAmount(at index: Int, delta: Double) {
        guard index < items.count else { return }
        let old = items[index]
        let newAmount = max(old.unit == .qty ? 1 : old.unit.stepSize, old.amount + delta)
        let nutrition = NutritionDatabase.estimate(name: old.name, amount: newAmount, unit: old.unit)

        items[index] = FoodItem(
            name: old.name,
            amount: newAmount,
            unit: old.unit,
            caloriesEstimate: nutrition?.calories ?? old.caloriesEstimate,
            macros: nutrition?.macros ?? old.macros,
            isHomemade: old.isHomemade
        )
    }

    func removeItem(at index: Int) {
        guard index < items.count else { return }
        items.remove(at: index)
    }

    var totalCalories: Int {
        items.compactMap { $0.caloriesEstimate }.reduce(0, +)
    }

    var totalMacros: Macros {
        items.compactMap { $0.macros }.reduce(Macros.zero, +)
    }

    /// Sum of all macro grams (for bar chart proportions).
    var macroTotal: Double {
        let m = totalMacros
        return m.protein + m.carbs + m.fat + m.fiber
    }

    func save() {
        guard !items.isEmpty else { return }
        let totalCal = totalCalories
        let macros = totalMacros

        // If completing a pending entry, update it instead of creating new
        if let pendingId = pendingEntryId {
            Task {
                await FoodStore.shared.completePendingEntry(
                    id: pendingId,
                    items: items,
                    mealType: selectedMealType.rawValue,
                    portionNote: portionNote.isEmpty ? nil : portionNote
                )
            }
            return
        }

        let entry = FoodStore.FoodLogEntry(
            mealType: selectedMealType.rawValue,
            items: items,
            source: .manual,
            totalCaloriesEstimate: totalCal > 0 ? totalCal : nil,
            totalMacros: macros == .zero ? nil : macros,
            portionNote: portionNote.isEmpty ? nil : portionNote
        )

        Task { await FoodStore.shared.addEntry(entry) }
    }
}

// MARK: - Voice Input Sheet

struct VoiceInputSheet: View {
    @ObservedObject var voice: VoiceFoodParser
    @Environment(\.dismiss) private var dismiss
    let onAdd: ([FoodItem]) -> Void

    @State private var pulsePhase = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                // Mic button
                ZStack {
                    // Pulse rings when listening
                    if voice.isListening {
                        Circle()
                            .stroke(NC.teal.opacity(0.2), lineWidth: 2)
                            .frame(width: 130, height: 130)
                            .scaleEffect(pulsePhase ? 1.2 : 0.9)
                            .opacity(pulsePhase ? 0 : 0.6)

                        Circle()
                            .fill(NC.teal.opacity(0.08))
                            .frame(width: 110, height: 110)
                            .scaleEffect(pulsePhase ? 1.1 : 1.0)
                    }

                    Button {
                        if voice.isListening {
                            voice.stopListening()
                        } else {
                            Task { await voice.startListening() }
                        }
                    } label: {
                        Circle()
                            .fill(voice.isListening ? NC.teal : Color(.systemGray4))
                            .frame(width: 80, height: 80)
                            .overlay {
                                Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                                    .font(.system(size: voice.isListening ? 24 : 32))
                                    .foregroundStyle(.white)
                            }
                            .shadow(color: voice.isListening ? NC.teal.opacity(0.4) : .clear, radius: 12)
                    }
                    .buttonStyle(.plain)
                }
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulsePhase)
                .onChange(of: voice.isListening) { _, listening in
                    pulsePhase = listening
                }

                // Status
                if voice.isListening {
                    Text("Listening... tap stop when done")
                        .font(.subheadline)
                        .foregroundStyle(NC.teal)
                } else if !voice.parsedItems.isEmpty {
                    Text("Done! Review items below")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                } else if voice.error != nil {
                    // shown below
                } else {
                    Text("Tap the mic and say what you ate")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Live transcript
                if !voice.transcript.isEmpty {
                    VStack(spacing: 6) {
                        Text("I heard:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(voice.transcript)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal)
                }

                // Error
                if let error = voice.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                // Parsed items preview
                if !voice.parsedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Detected \(voice.parsedItems.count) item\(voice.parsedItems.count == 1 ? "" : "s")")
                            .font(.subheadline.bold())

                        ForEach(voice.parsedItems) { item in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)

                                Text(item.name)
                                    .font(.subheadline)

                                Text(amountLabel(item))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                if let cal = item.caloriesEstimate, cal > 0 {
                                    Text("\(cal) cal")
                                        .font(.caption.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    .padding(.horizontal)

                    Button {
                        onAdd(voice.parsedItems)
                        dismiss()
                    } label: {
                        Text("Add \(voice.parsedItems.count) Item\(voice.parsedItems.count == 1 ? "" : "s")")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(NC.teal)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: NC.cardRadius))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
            .navigationTitle("Voice Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        voice.stopListening()
                        dismiss()
                    }
                }
            }
        }
    }

    private func amountLabel(_ item: FoodItem) -> String {
        let amt = item.amount == floor(item.amount) ? "\(Int(item.amount))" : String(format: "%.0f", item.amount)
        return "\(amt) \(item.unit.label)"
    }
}

#Preview {
    FoodLogView()
}
