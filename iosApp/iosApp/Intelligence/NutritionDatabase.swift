import Foundation

// MARK: - Unit Type

/// How the food quantity is measured.
enum FoodUnit: String, Codable, CaseIterable {
    case qty = "qty"     // whole items: banana, egg, bread slice, roti
    case grams = "g"     // weighed items: chicken, rice, paneer
    case ml = "ml"       // liquids: milk, juice, coffee, smoothie

    var label: String {
        switch self {
        case .qty: return "pcs"
        case .grams: return "g"
        case .ml: return "ml"
        }
    }
}

// MARK: - Macros

/// Macronutrient breakdown for a food item.
struct Macros: Codable, Equatable {
    let protein: Double    // grams
    let carbs: Double      // grams
    let fat: Double        // grams
    let fiber: Double      // grams

    static let zero = Macros(protein: 0, carbs: 0, fat: 0, fiber: 0)

    /// Scale macros by a multiplier (e.g. for quantity/weight adjustments).
    func scaled(by factor: Double) -> Macros {
        Macros(
            protein: protein * factor,
            carbs: carbs * factor,
            fat: fat * factor,
            fiber: fiber * factor
        )
    }

    /// Add two macro sets together.
    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat,
            fiber: lhs.fiber + rhs.fiber
        )
    }
}

// MARK: - Nutrition Entry

/// A single food's nutrition profile from the global database.
struct NutritionEntry {
    let name: String
    let keywords: [String]
    let defaultUnit: FoodUnit
    let defaultAmount: Double        // default serving: 1 for qty, 100 for g, 200 for ml
    let caloriesPerServing: Int      // per defaultAmount
    let macrosPerServing: Macros     // per defaultAmount
}

// MARK: - Nutrition Database

/// Global average nutrition data for common foods.
/// Values are approximate per-serving averages from standard nutritional references.
/// Unit detection: grams for meats/cooked items, qty for whole items, ml for liquids.
enum NutritionDatabase {

    /// Look up nutrition info by food name. Returns best match or nil.
    static func lookup(_ name: String) -> NutritionEntry? {
        let lower = name.lowercased()
        return database.first { entry in
            entry.keywords.contains { lower.contains($0) }
        }
    }

    /// Detect the appropriate unit for a food name.
    static func detectUnit(for name: String) -> FoodUnit {
        lookup(name)?.defaultUnit ?? .qty
    }

    /// Estimate nutrition for a food item given name, amount, and unit.
    static func estimate(name: String, amount: Double, unit: FoodUnit) -> (calories: Int, macros: Macros)? {
        guard let entry = lookup(name) else { return nil }

        let factor: Double
        switch (entry.defaultUnit, unit) {
        case (.qty, .qty):
            factor = amount / entry.defaultAmount
        case (.grams, .grams):
            factor = amount / entry.defaultAmount
        case (.ml, .ml):
            factor = amount / entry.defaultAmount
        default:
            // Cross-unit: best effort — treat as direct ratio
            factor = amount / entry.defaultAmount
        }

        return (
            calories: Int(Double(entry.caloriesPerServing) * factor),
            macros: entry.macrosPerServing.scaled(by: factor)
        )
    }

    // MARK: - Database

    // All values are global averages per serving.
    // Serving sizes: qty=1 piece, g=100g, ml=200ml (1 glass) unless noted.

    static let database: [NutritionEntry] = [

        // ── Proteins (grams) ──────────────────────────────────────────

        NutritionEntry(name: "Chicken Breast", keywords: ["chicken breast", "grilled chicken"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 165,
                       macrosPerServing: Macros(protein: 31, carbs: 0, fat: 3.6, fiber: 0)),

        NutritionEntry(name: "Chicken", keywords: ["chicken"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 239,
                       macrosPerServing: Macros(protein: 27, carbs: 0, fat: 14, fiber: 0)),

        NutritionEntry(name: "Fish", keywords: ["fish", "salmon", "tuna"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 206,
                       macrosPerServing: Macros(protein: 22, carbs: 0, fat: 12, fiber: 0)),

        NutritionEntry(name: "Prawn", keywords: ["prawn", "shrimp"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 99,
                       macrosPerServing: Macros(protein: 24, carbs: 0.2, fat: 0.3, fiber: 0)),

        NutritionEntry(name: "Mutton", keywords: ["mutton", "lamb", "goat"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 258,
                       macrosPerServing: Macros(protein: 25, carbs: 0, fat: 17, fiber: 0)),

        NutritionEntry(name: "Paneer", keywords: ["paneer", "cottage cheese"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 265,
                       macrosPerServing: Macros(protein: 18, carbs: 1.2, fat: 21, fiber: 0)),

        NutritionEntry(name: "Tofu", keywords: ["tofu"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 76,
                       macrosPerServing: Macros(protein: 8, carbs: 1.9, fat: 4.8, fiber: 0.3)),

        // ── Whole items (quantity) ────────────────────────────────────

        NutritionEntry(name: "Egg", keywords: ["egg", "boiled egg", "fried egg", "omelette"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 78,
                       macrosPerServing: Macros(protein: 6, carbs: 0.6, fat: 5, fiber: 0)),

        NutritionEntry(name: "Banana", keywords: ["banana"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 105,
                       macrosPerServing: Macros(protein: 1.3, carbs: 27, fat: 0.4, fiber: 3.1)),

        NutritionEntry(name: "Apple", keywords: ["apple"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 95,
                       macrosPerServing: Macros(protein: 0.5, carbs: 25, fat: 0.3, fiber: 4.4)),

        NutritionEntry(name: "Orange", keywords: ["orange"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 62,
                       macrosPerServing: Macros(protein: 1.2, carbs: 15, fat: 0.2, fiber: 3.1)),

        NutritionEntry(name: "Bread", keywords: ["bread", "toast"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 79,
                       macrosPerServing: Macros(protein: 2.7, carbs: 15, fat: 1, fiber: 0.6)),

        NutritionEntry(name: "Roti", keywords: ["roti", "chapati", "phulka"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 104,
                       macrosPerServing: Macros(protein: 3.1, carbs: 18, fat: 3.4, fiber: 2)),

        NutritionEntry(name: "Naan", keywords: ["naan", "garlic naan"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 262,
                       macrosPerServing: Macros(protein: 8.7, carbs: 45, fat: 5.1, fiber: 1.8)),

        NutritionEntry(name: "Dosa", keywords: ["dosa", "masala dosa"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 168,
                       macrosPerServing: Macros(protein: 3.9, carbs: 27, fat: 5.2, fiber: 1)),

        NutritionEntry(name: "Idli", keywords: ["idli"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 58,
                       macrosPerServing: Macros(protein: 2, carbs: 12, fat: 0.4, fiber: 0.6)),

        NutritionEntry(name: "Paratha", keywords: ["paratha", "aloo paratha"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 260,
                       macrosPerServing: Macros(protein: 5, carbs: 36, fat: 10, fiber: 2)),

        NutritionEntry(name: "Burger", keywords: ["burger", "hamburger", "cheeseburger"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 450,
                       macrosPerServing: Macros(protein: 25, carbs: 40, fat: 22, fiber: 2)),

        NutritionEntry(name: "Pizza Slice", keywords: ["pizza"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 285,
                       macrosPerServing: Macros(protein: 12, carbs: 36, fat: 10, fiber: 2.5)),

        NutritionEntry(name: "Taco", keywords: ["taco"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 210,
                       macrosPerServing: Macros(protein: 9, carbs: 21, fat: 10, fiber: 3)),

        NutritionEntry(name: "Sandwich", keywords: ["sandwich", "sub"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 350,
                       macrosPerServing: Macros(protein: 15, carbs: 35, fat: 16, fiber: 3)),

        NutritionEntry(name: "Wrap", keywords: ["wrap", "burrito", "shawarma", "roll"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 400,
                       macrosPerServing: Macros(protein: 18, carbs: 44, fat: 16, fiber: 3)),

        NutritionEntry(name: "Samosa", keywords: ["samosa"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 252,
                       macrosPerServing: Macros(protein: 4, carbs: 24, fat: 15, fiber: 2)),

        NutritionEntry(name: "Vada Pav", keywords: ["vada pav", "vada"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 290,
                       macrosPerServing: Macros(protein: 5, carbs: 36, fat: 14, fiber: 2)),

        NutritionEntry(name: "Cake Slice", keywords: ["cake", "pastry"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 350,
                       macrosPerServing: Macros(protein: 4, carbs: 50, fat: 15, fiber: 1)),

        NutritionEntry(name: "Cookie", keywords: ["cookie", "biscuit"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 78,
                       macrosPerServing: Macros(protein: 1, carbs: 10, fat: 3.6, fiber: 0.3)),

        // ── Grains & Cooked (grams) ──────────────────────────────────

        NutritionEntry(name: "Rice", keywords: ["rice", "steamed rice", "white rice", "brown rice"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 130,
                       macrosPerServing: Macros(protein: 2.7, carbs: 28, fat: 0.3, fiber: 0.4)),

        NutritionEntry(name: "Biryani", keywords: ["biryani", "pulao"],
                       defaultUnit: .grams, defaultAmount: 200,
                       caloriesPerServing: 500,
                       macrosPerServing: Macros(protein: 20, carbs: 60, fat: 18, fiber: 2)),

        NutritionEntry(name: "Pasta", keywords: ["pasta", "spaghetti", "noodle", "penne", "macaroni"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 160,
                       macrosPerServing: Macros(protein: 5.8, carbs: 31, fat: 0.9, fiber: 1.8)),

        NutritionEntry(name: "Oats", keywords: ["oat", "oatmeal", "porridge"],
                       defaultUnit: .grams, defaultAmount: 40,
                       caloriesPerServing: 150,
                       macrosPerServing: Macros(protein: 5, carbs: 27, fat: 2.5, fiber: 4)),

        NutritionEntry(name: "Dal", keywords: ["dal", "lentil"],
                       defaultUnit: .grams, defaultAmount: 150,
                       caloriesPerServing: 180,
                       macrosPerServing: Macros(protein: 12, carbs: 28, fat: 2, fiber: 8)),

        NutritionEntry(name: "Curry", keywords: ["curry", "sabzi", "gravy"],
                       defaultUnit: .grams, defaultAmount: 150,
                       caloriesPerServing: 250,
                       macrosPerServing: Macros(protein: 10, carbs: 18, fat: 14, fiber: 3)),

        NutritionEntry(name: "Salad", keywords: ["salad"],
                       defaultUnit: .grams, defaultAmount: 150,
                       caloriesPerServing: 100,
                       macrosPerServing: Macros(protein: 3, carbs: 12, fat: 4, fiber: 4)),

        NutritionEntry(name: "Soup", keywords: ["soup"],
                       defaultUnit: .ml, defaultAmount: 250,
                       caloriesPerServing: 150,
                       macrosPerServing: Macros(protein: 6, carbs: 18, fat: 5, fiber: 2)),

        NutritionEntry(name: "French Fries", keywords: ["fries", "chips", "french fries"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 312,
                       macrosPerServing: Macros(protein: 3.4, carbs: 41, fat: 15, fiber: 3.8)),

        NutritionEntry(name: "Ice Cream", keywords: ["ice cream", "gelato"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 207,
                       macrosPerServing: Macros(protein: 3.5, carbs: 24, fat: 11, fiber: 0.7)),

        NutritionEntry(name: "Chocolate", keywords: ["chocolate"],
                       defaultUnit: .grams, defaultAmount: 30,
                       caloriesPerServing: 160,
                       macrosPerServing: Macros(protein: 2, carbs: 17, fat: 9, fiber: 1.5)),

        NutritionEntry(name: "Yogurt", keywords: ["yogurt", "curd", "dahi", "raita"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 59,
                       macrosPerServing: Macros(protein: 3.5, carbs: 5, fat: 3.3, fiber: 0)),

        NutritionEntry(name: "Cheese", keywords: ["cheese"],
                       defaultUnit: .grams, defaultAmount: 30,
                       caloriesPerServing: 113,
                       macrosPerServing: Macros(protein: 7, carbs: 0.4, fat: 9, fiber: 0)),

        NutritionEntry(name: "Peanut Butter", keywords: ["peanut butter"],
                       defaultUnit: .grams, defaultAmount: 32,
                       caloriesPerServing: 190,
                       macrosPerServing: Macros(protein: 7, carbs: 7, fat: 16, fiber: 2)),

        NutritionEntry(name: "Almonds", keywords: ["almond", "nuts", "cashew", "walnut"],
                       defaultUnit: .grams, defaultAmount: 30,
                       caloriesPerServing: 170,
                       macrosPerServing: Macros(protein: 6, carbs: 6, fat: 14, fiber: 3.5)),

        // ── Liquids & Beverages (ml) ─────────────────────────────────

        NutritionEntry(name: "Milk", keywords: ["milk"],
                       defaultUnit: .ml, defaultAmount: 200,
                       caloriesPerServing: 122,
                       macrosPerServing: Macros(protein: 6.6, carbs: 10, fat: 6.4, fiber: 0)),

        NutritionEntry(name: "Coffee", keywords: ["coffee", "latte", "cappuccino", "espresso", "americano"],
                       defaultUnit: .ml, defaultAmount: 250,
                       caloriesPerServing: 120,
                       macrosPerServing: Macros(protein: 4, carbs: 12, fat: 5, fiber: 0)),

        NutritionEntry(name: "Tea", keywords: ["tea", "chai"],
                       defaultUnit: .ml, defaultAmount: 200,
                       caloriesPerServing: 50,
                       macrosPerServing: Macros(protein: 1, carbs: 8, fat: 1.5, fiber: 0)),

        NutritionEntry(name: "Juice", keywords: ["juice", "orange juice", "apple juice"],
                       defaultUnit: .ml, defaultAmount: 250,
                       caloriesPerServing: 112,
                       macrosPerServing: Macros(protein: 0.7, carbs: 26, fat: 0.3, fiber: 0.5)),

        NutritionEntry(name: "Smoothie", keywords: ["smoothie", "shake", "protein shake", "lassi"],
                       defaultUnit: .ml, defaultAmount: 300,
                       caloriesPerServing: 280,
                       macrosPerServing: Macros(protein: 10, carbs: 42, fat: 8, fiber: 3)),

        NutritionEntry(name: "Buttermilk", keywords: ["buttermilk", "chaas"],
                       defaultUnit: .ml, defaultAmount: 200,
                       caloriesPerServing: 40,
                       macrosPerServing: Macros(protein: 3.3, carbs: 5, fat: 0.9, fiber: 0)),

        NutritionEntry(name: "Coconut Water", keywords: ["coconut water", "nariyal pani"],
                       defaultUnit: .ml, defaultAmount: 250,
                       caloriesPerServing: 46,
                       macrosPerServing: Macros(protein: 1.7, carbs: 9, fat: 0.5, fiber: 2.6)),

        NutritionEntry(name: "Soda", keywords: ["soda", "cola", "coke", "pepsi", "sprite", "fanta"],
                       defaultUnit: .ml, defaultAmount: 330,
                       caloriesPerServing: 140,
                       macrosPerServing: Macros(protein: 0, carbs: 39, fat: 0, fiber: 0)),

        NutritionEntry(name: "Beer", keywords: ["beer", "ale", "lager"],
                       defaultUnit: .ml, defaultAmount: 330,
                       caloriesPerServing: 150,
                       macrosPerServing: Macros(protein: 1.6, carbs: 13, fat: 0, fiber: 0)),

        NutritionEntry(name: "Wine", keywords: ["wine"],
                       defaultUnit: .ml, defaultAmount: 150,
                       caloriesPerServing: 125,
                       macrosPerServing: Macros(protein: 0.1, carbs: 3.8, fat: 0, fiber: 0)),

        NutritionEntry(name: "Water", keywords: ["water"],
                       defaultUnit: .ml, defaultAmount: 250,
                       caloriesPerServing: 0,
                       macrosPerServing: Macros(protein: 0, carbs: 0, fat: 0, fiber: 0)),

        // ── Fruits (quantity / grams) ────────────────────────────────

        NutritionEntry(name: "Mango", keywords: ["mango"],
                       defaultUnit: .qty, defaultAmount: 1,
                       caloriesPerServing: 150,
                       macrosPerServing: Macros(protein: 1.4, carbs: 35, fat: 0.6, fiber: 3.7)),

        NutritionEntry(name: "Grapes", keywords: ["grape"],
                       defaultUnit: .grams, defaultAmount: 100,
                       caloriesPerServing: 69,
                       macrosPerServing: Macros(protein: 0.7, carbs: 18, fat: 0.2, fiber: 0.9)),

        NutritionEntry(name: "Watermelon", keywords: ["watermelon"],
                       defaultUnit: .grams, defaultAmount: 200,
                       caloriesPerServing: 60,
                       macrosPerServing: Macros(protein: 1.2, carbs: 15, fat: 0.3, fiber: 0.8)),

        NutritionEntry(name: "Papaya", keywords: ["papaya"],
                       defaultUnit: .grams, defaultAmount: 150,
                       caloriesPerServing: 65,
                       macrosPerServing: Macros(protein: 0.7, carbs: 16, fat: 0.4, fiber: 2.7)),

        NutritionEntry(name: "Pineapple", keywords: ["pineapple"],
                       defaultUnit: .grams, defaultAmount: 150,
                       caloriesPerServing: 75,
                       macrosPerServing: Macros(protein: 0.8, carbs: 20, fat: 0.2, fiber: 2.1)),
    ]
}
