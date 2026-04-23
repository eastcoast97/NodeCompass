import SwiftUI

/// NodeCompass Design System — "Aurora"
///
/// Design principles:
///   1. No borders. Separation through luminance stepping and spacing.
///   2. Near-black base for OLED efficiency and color pop.
///   3. Each pillar (Wealth, Health, Mind) has a distinct color identity.
///   4. Data is the decoration — large numbers, vibrant charts, minimal chrome.
///   5. Cards only for interactive/tappable blocks. Everything else flows.
enum NC {

    // MARK: - Surface Hierarchy (Luminance Stepping)
    //
    // 4-tier background system. Each tier is 4-6% lighter than the last.
    // The eye perceives these as distinct surfaces without needing borders.

    /// App canvas, ScrollView background
    static let bgBase = Color(hex: "#08080C")
    /// Cards, panels, primary content areas
    static let bgSurface = Color(hex: "#111116")
    /// Nested cards, hover states, elevated elements
    static let bgElevated = Color(hex: "#1A1A20")
    /// Modals, popovers, overlays
    static let bgOverlay = Color(hex: "#242430")

    // MARK: - Text Hierarchy

    /// Headlines, important data values
    static let textPrimary = Color(hex: "#F0F0F5")
    /// Body text, descriptions
    static let textSecondary = Color(hex: "#9090A0")
    /// Timestamps, metadata, hints
    static let textTertiary = Color(hex: "#55555F")

    // MARK: - Brand & Pillar Colors

    /// Primary accent — mint-teal, distinct and vibrant on dark
    static let teal = Color(hex: "#3DD6D0")
    /// Wealth pillar
    static let wealth = Color(hex: "#00D4AA")
    /// Health pillar
    static let health = Color(hex: "#FF6B9D")
    /// Mind pillar
    static let mind = Color(hex: "#60A5FA")
    /// AI / Insights accent
    static let insight = Color(hex: "#FFB347")

    // MARK: - Legacy aliases (keep for compat)

    static let accent = teal
    static let deepNavy = bgBase
    static let slate = textSecondary

    // MARK: - Semantic Colors

    static let spend = Color(hex: "#FF5252")
    static let income = Color(hex: "#4ADE80")
    static let warning = Color(hex: "#FBBF24")
    static let food = Color(hex: "#FF6B9D")

    // MARK: - Design Tokens

    /// Standard corner radius for cards
    static let cardRadius: CGFloat = 16
    /// Icon background size in list rows
    static let iconSize: CGFloat = 38
    /// Icon background corner radius
    static let iconRadius: CGFloat = 10
    /// Hero card corner radius
    static let heroRadius: CGFloat = 20
    /// Standard horizontal content padding
    static let hPad: CGFloat = 16
    /// Standard vertical row padding
    static let vPad: CGFloat = 12
    /// Divider leading indent
    static let dividerIndent: CGFloat = 62

    // MARK: - Spacing Scale (8pt grid)

    static let spaceXS: CGFloat = 8
    static let spaceSM: CGFloat = 12
    static let spaceMD: CGFloat = 16
    static let spaceLG: CGFloat = 20
    static let spaceXL: CGFloat = 24
    static let space2XL: CGFloat = 32

    // MARK: - Currency

    static var currencySymbol: String {
        if let stored = UserDefaults.standard.string(forKey: "primaryCurrencySymbol"), !stored.isEmpty {
            return stored
        }
        return Locale.current.currencySymbol ?? "$"
    }

    static func money(_ amount: Double) -> String {
        "\(currencySymbol)\(Int(amount).formatted())"
    }

    static var currencyIcon: String {
        switch currencySymbol {
        case "₹": return "indianrupeesign"
        case "€": return "eurosign"
        case "£": return "sterlingsign"
        case "¥": return "yensign"
        default: return "dollarsign"
        }
    }

    static var currencyIconCircle: String {
        "\(currencyIcon).circle.fill"
    }

    // MARK: - Theme

    static var preferredColorScheme: ColorScheme? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "preferredColorScheme") else { return nil }
            switch raw {
            case "dark": return .dark
            case "light": return .light
            default: return nil
            }
        }
        set {
            switch newValue {
            case .dark: UserDefaults.standard.set("dark", forKey: "preferredColorScheme")
            case .light: UserDefaults.standard.set("light", forKey: "preferredColorScheme")
            default: UserDefaults.standard.removeObject(forKey: "preferredColorScheme")
            }
        }
    }

    // MARK: - Category Colors (desaturated for dark mode)

    static let categoryColors: [String: Color] = [
        "Food & Dining":     Color(hex: "#FF6B9D"),
        "Groceries":         Color(hex: "#4ADE80"),
        "Transport":         Color(hex: "#60A5FA"),
        "Shopping":          Color(hex: "#A78BFA"),
        "Subscriptions":     Color(hex: "#F472B6"),
        "Bills & Utilities": Color(hex: "#818CF8"),
        "Entertainment":     Color(hex: "#FB923C"),
        "Health":            Color(hex: "#3DD6D0"),
        "Education":         Color(hex: "#A78BFA"),
        "Transfers":         Color(hex: "#6B7280"),
        "Rent":              Color(hex: "#38BDF8"),
        "Insurance":         Color(hex: "#22D3EE"),
        "Investment":        Color(hex: "#34D399"),
        "Travel":            Color(hex: "#FBBF24"),
        "Income":            Color(hex: "#4ADE80"),
        "Other":             Color(hex: "#6B7280"),
    ]

    static func color(for category: String) -> Color {
        categoryColors[category] ?? Color(hex: "#6B7280")
    }

    // MARK: - Category Icons

    static let categoryIcons: [String: String] = [
        "Food & Dining":     "fork.knife",
        "Groceries":         "cart.fill",
        "Transport":         "car.fill",
        "Shopping":          "bag.fill",
        "Subscriptions":     "repeat",
        "Bills & Utilities": "bolt.fill",
        "Entertainment":     "gamecontroller.fill",
        "Health":            "heart.fill",
        "Education":         "graduationcap.fill",
        "Transfers":         "arrow.left.arrow.right",
        "Rent":              "house.fill",
        "Insurance":         "shield.checkered",
        "Investment":        "chart.line.uptrend.xyaxis",
        "Travel":            "airplane",
        "Income":            "arrow.down.circle.fill",
        "Other":             "ellipsis.circle.fill",
    ]

    static func icon(for category: String) -> String {
        categoryIcons[category] ?? "ellipsis.circle.fill"
    }
}

// MARK: - Card Modifier (Borderless, Luminance-Based)

struct CardStyle: ViewModifier {
    var padding: CGFloat = 16
    var tint: Color? = nil

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: NC.cardRadius, style: .continuous)
                    .fill(tint != nil ? AnyShapeStyle(tint!.opacity(0.06)) : AnyShapeStyle(NC.bgSurface))
            )
    }
}

extension View {
    /// Standard card — borderless, luminance-step background.
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardStyle(padding: padding))
    }

    /// Tinted card — subtle pillar/accent color background.
    func card(padding: CGFloat = 16, tint: Color) -> some View {
        modifier(CardStyle(padding: padding, tint: tint))
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
        .background(NC.color(for: category).opacity(0.12))
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
                    gradient: Gradient(colors: [.clear, .white.opacity(0.08), .clear]),
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

// MARK: - Animated Coach Button

/// Floating AI coach button — slow breathing pulse instead of fast rotation.
struct AnimatedCoachButton: View {
    var action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button {
            Haptic.light()
            action()
        } label: {
            ZStack {
                // Soft glow
                Circle()
                    .fill(NC.mind.opacity(0.15))
                    .frame(width: 60, height: 60)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .opacity(pulse ? 0.0 : 0.6)

                Circle()
                    .fill(NC.bgSurface)
                    .frame(width: 54, height: 54)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [NC.mind, NC.mind.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 50, height: 50)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Discovery Tip (Contextual First-Visit Tips)

struct DiscoveryTip: View {
    let id: String
    let icon: String
    let title: String
    let message: String
    let accentColor: Color

    @State private var isVisible = false

    private var visitKey: String { "discovery_tip_visits_\(id)" }
    private var dismissedKey: String { "discovery_tip_dismissed_\(id)" }
    private let maxVisits = 3

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(accentColor)
                        .frame(width: 32, height: 32)
                        .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NC.textPrimary)
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundStyle(NC.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { isVisible = false }
                        UserDefaults.standard.set(true, forKey: dismissedKey)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NC.textTertiary)
                            .frame(width: 24, height: 24)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accentColor.opacity(0.06))
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear {
            let dismissed = UserDefaults.standard.bool(forKey: dismissedKey)
            guard !dismissed else { return }
            let visits = UserDefaults.standard.integer(forKey: visitKey) + 1
            UserDefaults.standard.set(visits, forKey: visitKey)
            if visits <= maxVisits {
                withAnimation(.easeOut(duration: 0.4).delay(0.5)) { isVisible = true }
            }
        }
    }
}

// MARK: - Empty State (Enhanced)

struct EnhancedEmptyState: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(color.opacity(0.5))
            }
            .scaleEffect(appeared ? 1 : 0.7)
            .opacity(appeared ? 1 : 0)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NC.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(NC.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)

            if let label = actionLabel, let action = action {
                Button {
                    Haptic.light()
                    action()
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(color.opacity(0.1), in: Capsule())
                }
                .opacity(appeared ? 1 : 0)
            }
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Smooth Transition Modifiers

struct StaggeredAppear: ViewModifier {
    let index: Int
    let baseDelay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                let delay = min(baseDelay + Double(index) * 0.04, 0.35)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8).delay(delay)) {
                    appeared = true
                }
            }
    }
}

struct SectionAppear: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.82).delay(delay)) {
                    appeared = true
                }
            }
    }
}

extension View {
    func staggerIn(index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredAppear(index: index, baseDelay: baseDelay))
    }
    func sectionAppear(delay: Double = 0.1) -> some View {
        modifier(SectionAppear(delay: delay))
    }
}

// MARK: - Hex Color Helper

extension Color {
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
