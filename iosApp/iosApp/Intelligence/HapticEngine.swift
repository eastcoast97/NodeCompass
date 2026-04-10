import UIKit

/// Centralized haptic feedback for premium feel.
enum Haptic {
    /// Light tap — button presses, selections
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Medium tap — card swipes, toggles
    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Heavy tap — important actions
    static func heavy() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    /// Success — goal achieved, achievement unlocked
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Warning — budget limit approaching
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Error — something went wrong
    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Selection changed — picker, tab switch
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
