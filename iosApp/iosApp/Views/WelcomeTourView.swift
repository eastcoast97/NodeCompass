import SwiftUI

// MARK: - Welcome Tour
//
// Quick 4-card carousel shown once after onboarding completes, before the
// user lands on the main app. Brand intro only — feature flows are taught
// just-in-time via TabCoachmark on first visit to each tab.
//
// Gating: UserDefaults `hasSeenWelcomeTour`. Re-runnable from You tab's
// "Re-run Onboarding" button (which clears both flags).

struct WelcomeTourView: View {
    @Binding var isComplete: Bool
    @State private var currentPage = 0

    private struct Card {
        let icon: String
        let iconColor: Color
        let headline: String
        let body: String
    }

    private let cards: [Card] = [
        Card(
            icon: "square.grid.2x2.fill",
            iconColor: NC.teal,
            headline: "Five tabs, five views of you",
            body: "Today is your daily pulse. Wealth, Health, and Mind each show a pillar of your life. You is your settings and integrations."
        ),
        Card(
            icon: "lock.shield.fill",
            iconColor: .blue,
            headline: "Everything stays on your phone",
            body: "No cloud. No telemetry. The AI sees merchant names only — never amounts or accounts. Your data is yours."
        ),
        Card(
            icon: "brain.head.profile",
            iconColor: NC.mind,
            headline: "Your AI Coach is in Mind",
            body: "Ask anything about your patterns. \"Why did I overspend this week?\" \"Am I sleeping less on busy days?\" It connects the dots."
        ),
        Card(
            icon: "link",
            iconColor: .green,
            headline: "Get going",
            body: "Connect bank, email, or health anytime in You. The more you give it, the sharper NodeCompass gets."
        )
    ]

    var body: some View {
        ZStack {
            // Deep background matching onboarding
            Color(red: 0.03, green: 0.03, blue: 0.07)
                .ignoresSafeArea()

            // Subtle gradient
            RadialGradient(
                colors: [
                    cards[currentPage].iconColor.opacity(0.06),
                    Color(hex: "#6366F1").opacity(0.03),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 500
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)

            VStack(spacing: 0) {
                // Skip button — top-trailing, visible throughout
                HStack {
                    Spacer()
                    Button {
                        complete()
                    } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                Spacer()

                // Card pager
                TabView(selection: $currentPage) {
                    ForEach(cards.indices, id: \.self) { idx in
                        cardView(cards[idx])
                            .tag(idx)
                            .padding(.horizontal, 28)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Page dots
                HStack(spacing: 8) {
                    ForEach(cards.indices, id: \.self) { idx in
                        Circle()
                            .fill(idx == currentPage ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 7, height: 7)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 20)

                // Action button
                Button {
                    if currentPage < cards.count - 1 {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentPage += 1
                        }
                    } else {
                        complete()
                    }
                } label: {
                    Text(currentPage < cards.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [NC.teal, NC.teal.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(card.iconColor.opacity(0.15))
                    .frame(width: 110, height: 110)

                Circle()
                    .stroke(card.iconColor.opacity(0.25), lineWidth: 1)
                    .frame(width: 130, height: 130)

                Image(systemName: card.icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(card.iconColor)
            }

            VStack(spacing: 14) {
                Text(card.headline)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.body)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcomeTour")
        withAnimation(.easeInOut(duration: 0.3)) {
            isComplete = true
        }
    }
}

#Preview {
    WelcomeTourView(isComplete: .constant(false))
}
