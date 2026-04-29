import SwiftUI

// MARK: - Tab Coachmark
//
// Lightweight, top-anchored tooltip card that appears once on first visit
// to a tab. Just-in-time teaching: tells the user what to tap on THIS
// screen, then dismisses and never shows again (per tab).
//
// Persistence: each tab gets its own UserDefaults flag like `tipSeen.wealth`.
// Reset by the You tab's "Re-run Onboarding" which clears all `tipSeen.*`.
//
// Usage:
//   .overlay(alignment: .top) {
//       TabCoachmark(
//           id: "wealth",
//           icon: "lightbulb.fill",
//           title: "Welcome to Wealth",
//           body: "Tap Budgets to set monthly limits, or Subscriptions to find ghost charges.",
//           color: NC.teal
//       )
//   }

struct TabCoachmark: View {
    let id: String
    let icon: String
    let title: String
    let message: String
    let color: Color

    @State private var visible: Bool

    init(id: String, icon: String, title: String, body: String, color: Color) {
        self.id = id
        self.icon = icon
        self.title = title
        self.message = body
        self.color = color
        // Initialize visibility from persisted flag
        let key = "tipSeen.\(id)"
        let alreadySeen = UserDefaults.standard.bool(forKey: key)
        _visible = State(initialValue: !alreadySeen)
    }

    var body: some View {
        if visible {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color(.systemGray5), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.background)
                    .shadow(color: color.opacity(0.15), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(color.opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal, NC.hPad)
            .padding(.top, 4)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture { dismiss() }
        }
    }

    private func dismiss() {
        UserDefaults.standard.set(true, forKey: "tipSeen.\(id)")
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            visible = false
        }
    }
}
