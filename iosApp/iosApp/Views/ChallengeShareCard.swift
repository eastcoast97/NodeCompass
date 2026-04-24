import SwiftUI
import UIKit

// MARK: - Share Card View

/// SwiftUI view rendered to a UIImage via `ImageRenderer` (iOS 16+) so the
/// user can post a completion celebration to social apps in one tap.
///
/// Card is 1080×1080 (Instagram square) on an Aurora dark background, with a
/// pillar-tinted radial gradient and the NodeCompass wordmark.
struct ChallengeShareCard: View {
    let challenge: ChallengeStore.Challenge
    let achievement: AchievementEngine.Achievement?

    private var accentColor: Color {
        switch challenge.pillar {
        case .wealth: return NC.wealth
        case .health: return NC.health
        case .mind:   return NC.mind
        case .cross:  return NC.insight
        }
    }

    private var dayCount: Int {
        let cal = Calendar.current
        let start = cal.startOfDay(for: challenge.startDate)
        let end = cal.startOfDay(for: challenge.completedAt ?? Date())
        return max(1, cal.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    private var iconName: String {
        achievement?.icon ?? challenge.type.icon
    }

    var body: some View {
        ZStack {
            // Base dark background
            NC.bgBase

            // Pillar-tinted radial gradient glow in the upper half
            RadialGradient(
                colors: [accentColor.opacity(0.35), accentColor.opacity(0)],
                center: .init(x: 0.5, y: 0.3),
                startRadius: 20,
                endRadius: 600
            )

            VStack(spacing: 48) {
                Spacer(minLength: 40)

                // Achievement / challenge icon in a glowing ring
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 280, height: 280)
                    Circle()
                        .stroke(accentColor.opacity(0.4), lineWidth: 3)
                        .frame(width: 280, height: 280)
                    Image(systemName: iconName)
                        .font(.system(size: 120, weight: .regular))
                        .foregroundStyle(accentColor)
                }

                VStack(spacing: 20) {
                    Text("CHALLENGE COMPLETE")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .kerning(4)
                        .foregroundStyle(accentColor)

                    Text(challenge.title)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .foregroundStyle(NC.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 60)

                    if let badge = achievement {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(NC.insight)
                            Text("Unlocked: \(badge.title)")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundStyle(NC.textPrimary.opacity(0.9))
                        }
                        .padding(.top, 8)
                    }

                    Text("Completed in \(dayCount) day\(dayCount == 1 ? "" : "s")")
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .foregroundStyle(NC.textPrimary.opacity(0.6))
                        .padding(.top, 4)
                }

                Spacer(minLength: 40)

                // Wordmark
                HStack(spacing: 12) {
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(accentColor)
                    Text("NodeCompass")
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .foregroundStyle(NC.textPrimary.opacity(0.75))
                }
                .padding(.bottom, 60)
            }
            .padding(40)
        }
        .frame(width: 1080, height: 1080)
    }
}

// MARK: - Renderer

enum ChallengeShareCardRenderer {

    /// Render the share card to a UIImage. Must be called on MainActor because
    /// ImageRenderer evaluates SwiftUI views on the main thread.
    @MainActor
    static func render(
        challenge: ChallengeStore.Challenge,
        achievement: AchievementEngine.Achievement?
    ) -> UIImage? {
        let card = ChallengeShareCard(challenge: challenge, achievement: achievement)
        let renderer = ImageRenderer(content: card)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

// MARK: - Share Sheet Wrapper

/// Thin `UIViewControllerRepresentable` wrapper so SwiftUI can present an
/// iOS `UIActivityViewController` (the standard share sheet with Photos,
/// Messages, Instagram, etc.).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
