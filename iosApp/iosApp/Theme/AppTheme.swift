import SwiftUI

/// NodeCompass Design System
/// Consistent colors, typography, and reusable components across the app.
enum NC {

    // MARK: - Brand Colors

    static let accent = Color("AccentColor")
    static let teal = Color(hex: "#0EA5A1")
    static let deepNavy = Color(hex: "#0F172A")
    static let slate = Color(hex: "#334155")

    // MARK: - Semantic Colors

    static let spend = Color(hex: "#EF4444")
    static let income = Color(hex: "#22C55E")
    static let warning = Color(hex: "#F59E0B")
    static let food = Color(hex: "#F43F5E")

    // MARK: - Design Tokens

    /// Standard corner radius for all cards
    static let cardRadius: CGFloat = 14
    /// Icon background size in list rows
    static let iconSize: CGFloat = 38
    /// Icon background corner radius
    static let iconRadius: CGFloat = 10
    /// Hero card corner radius (larger for swipeable cards)
    static let heroRadius: CGFloat = 22
    /// Standard horizontal content padding
    static let hPad: CGFloat = 16
    /// Standard vertical row padding
    static let vPad: CGFloat = 12
    /// Divider leading indent (icon + spacing)
    static let dividerIndent: CGFloat = 62

    // MARK: - Currency

    /// The user's primary currency symbol, detected from their transactions.
    /// Falls back to locale-based symbol, then "$".
    static var currencySymbol: String {
        // First: check what the user's transactions use most
        if let stored = UserDefaults.standard.string(forKey: "primaryCurrencySymbol"), !stored.isEmpty {
            return stored
        }
        // Fallback: locale
        return Locale.current.currencySymbol ?? "$"
    }

    /// Format a monetary value with the user's currency symbol.
    static func money(_ amount: Double) -> String {
        "\(currencySymbol)\(Int(amount).formatted())"
    }

    // MARK: - Category Colors (vibrant, accessible palette)

    static let categoryColors: [String: Color] = [
        "Food & Dining":    Color(hex: "#F43F5E"),
        "Groceries":        Color(hex: "#22C55E"),
        "Transport":        Color(hex: "#3B82F6"),
        "Shopping":         Color(hex: "#A855F7"),
        "Subscriptions":    Color(hex: "#EC4899"),
        "Bills & Utilities": Color(hex: "#6366F1"),
        "Entertainment":    Color(hex: "#F97316"),
        "Health":           Color(hex: "#14B8A6"),
        "Education":        Color(hex: "#8B5CF6"),
        "Transfers":        Color(hex: "#64748B"),
        "Rent":             Color(hex: "#0EA5E9"),
        "Insurance":        Color(hex: "#06B6D4"),
        "Investment":       Color(hex: "#10B981"),
        "Travel":           Color(hex: "#F59E0B"),
        "Income":           Color(hex: "#22C55E"),
        "Other":            Color(hex: "#94A3B8"),
    ]

    static func color(for category: String) -> Color {
        categoryColors[category] ?? Color(hex: "#94A3B8")
    }

    // MARK: - Category Icons

    static let categoryIcons: [String: String] = [
        "Food & Dining":    "fork.knife",
        "Groceries":        "cart.fill",
        "Transport":        "car.fill",
        "Shopping":         "bag.fill",
        "Subscriptions":    "repeat",
        "Bills & Utilities": "bolt.fill",
        "Entertainment":    "gamecontroller.fill",
        "Health":           "heart.fill",
        "Education":        "graduationcap.fill",
        "Transfers":        "arrow.left.arrow.right",
        "Rent":             "house.fill",
        "Insurance":        "shield.checkered",
        "Investment":       "chart.line.uptrend.xyaxis",
        "Travel":           "airplane",
        "Income":           "arrow.down.circle.fill",
        "Other":            "ellipsis.circle.fill",
    ]

    static func icon(for category: String) -> String {
        categoryIcons[category] ?? "ellipsis.circle.fill"
    }
}

// MARK: - Reusable Card Modifier

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

// MARK: - Category Badge

struct CategoryBadge: View {
    let category: String
    var small: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: NC.icon(for: category))
                .font(small ? .system(size: 8) : .caption2)
            Text(category)
                .font(small ? .system(size: 10) : .caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, small ? 6 : 8)
        .padding(.vertical, small ? 2 : 4)
        .background(NC.color(for: category).opacity(0.15))
        .foregroundStyle(NC.color(for: category))
        .clipShape(Capsule())
    }
}

// MARK: - Shimmer Loading Effect

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [.clear, .white.opacity(0.2), .clear]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        phase = 400
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Hex Color Helper

extension Color {
    /// Create a Color from a hex string like "#FF6384"
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgbValue: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
