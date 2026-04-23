import SwiftUI
import CoreLocation
import HealthKit
import GoogleSignIn
import LinkKit

// MARK: - Modern Onboarding Flow
//
// 5 steps — progressive disclosure, gets smarter over time:
//   Step 0: Welcome (pillars + privacy)
//   Step 1: Focus selection (what matters most to you right now)
//   Step 2: Permissions (Location + Health — both optional, skip-friendly)
//   Step 3: Connect Data (Bank + Email)
//   Step 4: Ready — celebration + what's next

struct OnboardingView: View {
    @StateObject private var state = OnboardingState()
    @Binding var isComplete: Bool

    @State private var currentStep = 0
    @State private var appeared = false
    @State private var selectedFocus: AppLearningStage.UserFocus = .everything

    private let totalSteps = 5

    var body: some View {
        ZStack {
            // Deep background matching lock screen
            Color(red: 0.03, green: 0.03, blue: 0.07)
                .ignoresSafeArea()

            // Ambient radial glow — shifts tint per step
            RadialGradient(
                colors: [
                    stepAccentColor.opacity(0.06),
                    Color(hex: "#6366F1").opacity(0.03),
                    .clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 500
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: currentStep)

            // Floating particles (same as lock screen)
            OnboardingParticleField()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress bar (visible on steps 1-3)
                if currentStep > 0 && currentStep < totalSteps - 1 {
                    progressBar
                        .padding(.top, 12)
                        .padding(.horizontal, 32)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Step content
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: focusStep
                    case 2: permissionsStep
                    case 3: connectDataStep
                    case 4: readyStep
                    default: EmptyView()
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

                Spacer(minLength: 12)

                // Bottom action
                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appeared = true }
        }
    }

    private var stepAccentColor: Color {
        switch currentStep {
        case 0: return NC.teal
        case 1: return Color(hex: "#A855F7")
        case 2: return .blue
        case 3: return Color(hex: "#6366F1")
        case 4: return NC.teal
        default: return NC.teal
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(1..<totalSteps, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? NC.teal : Color.white.opacity(0.08))
                    .frame(height: 3)
                    .animation(.spring(response: 0.4), value: currentStep)
            }
        }
    }

    // MARK: - Step 0: Welcome

    @State private var valueCardIndex = 0

    private var welcomeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Compact logo
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(NC.teal.opacity(0.06))
                            .frame(width: 100, height: 100)
                            .blur(radius: 30)
                            .opacity(appeared ? 1 : 0)

                        Image("NodeCompassLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: NC.teal.opacity(0.25), radius: 16, y: 3)
                    }
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                    .animation(.spring(response: 0.6, dampingFraction: 0.7), value: appeared)

                    VStack(spacing: 4) {
                        HStack(spacing: 2) {
                            Text("Node")
                                .font(.system(size: 28, weight: .thin))
                                .foregroundStyle(.white.opacity(0.7))
                            Text("Compass")
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        Text("Connects the dots across your money, health & habits")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 8)
                    .animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)
                }
                .padding(.top, 32)
                .padding(.bottom, 24)

                // Value showcase cards — show WHAT users get, not WHAT we track
                VStack(spacing: 10) {
                    ValueShowcaseCard(
                        icon: "chart.line.uptrend.xyaxis",
                        color: NC.teal,
                        insight: "You spent \(NC.currencySymbol)12,400 eating out this month",
                        detail: "3x more than last month. Your top spot: Starbucks.",
                        pillars: ["Wealth", "Food"],
                        delay: 0.2,
                        appeared: appeared
                    )

                    ValueShowcaseCard(
                        icon: "flame.fill",
                        color: .orange,
                        insight: "4 gym sessions this week — best streak in 2 months",
                        detail: "Auto-tracked from HealthKit + location. No manual logging.",
                        pillars: ["Health", "Places"],
                        delay: 0.3,
                        appeared: appeared
                    )

                    ValueShowcaseCard(
                        icon: "brain.head.profile",
                        color: Color(hex: "#A855F7"),
                        insight: "Every Tuesday, 8am — Starbucks. \(NC.currencySymbol)8,200/year",
                        detail: "AI coach connects spending patterns to your location habits.",
                        pillars: ["Wealth", "Mind"],
                        delay: 0.4,
                        appeared: appeared
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

                // "How it works" — 3 compact steps
                VStack(spacing: 0) {
                    HowItWorksRow(
                        step: "1",
                        title: "Connect your data",
                        desc: "Bank, Health, Location — all optional",
                        delay: 0.45, appeared: appeared
                    )
                    glassDivider
                    HowItWorksRow(
                        step: "2",
                        title: "We learn your patterns",
                        desc: "Spending, routines, habits — all on-device",
                        delay: 0.5, appeared: appeared
                    )
                    glassDivider
                    HowItWorksRow(
                        step: "3",
                        title: "Get personal insights",
                        desc: "AI coaching, nudges, goals — uniquely yours",
                        delay: 0.55, appeared: appeared
                    )
                }
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NC.bgSurface)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // Privacy badge — compact
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(NC.teal)
                    Text("100% on-device — your data never leaves your phone")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.6), value: appeared)
            }
        }
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.04))
            .frame(height: 0.5)
            .padding(.leading, 60)
    }

    // MARK: - Step 1: Focus Selection

    private var focusStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 16)

                VStack(spacing: 8) {
                    Text("What matters most?")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    Text("We'll focus here first. Everything else unlocks over time.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 4)

                VStack(spacing: 10) {
                    ForEach(AppLearningStage.UserFocus.allCases, id: \.self) { focus in
                        focusCard(focus)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func focusCard(_ focus: AppLearningStage.UserFocus) -> some View {
        let isSelected = selectedFocus == focus
        return Button {
            withAnimation(.spring(response: 0.35)) {
                Haptic.light()
                selectedFocus = focus
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? NC.teal.opacity(0.2) : Color.white.opacity(0.05))
                        .frame(width: 48, height: 48)
                    Image(systemName: focus.icon)
                        .font(.title3)
                        .foregroundStyle(isSelected ? NC.teal : .white.opacity(0.5))
                        .symbolEffect(.bounce, value: isSelected)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(focus.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(focus.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Radio indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? NC.teal : Color.white.opacity(0.12), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(NC.teal)
                            .frame(width: 12, height: 12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? NC.teal.opacity(0.06) : NC.bgSurface)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Enable Permissions")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Help NodeCompass learn your patterns")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    PermissionCard(
                        icon: "location.fill", color: .blue,
                        title: "Location",
                        subtitle: "Link spending to places, detect routines",
                        detail: "Uses iOS visit detection — less than 1% battery",
                        isGranted: state.locationConnected,
                        isDenied: state.locationDenied,
                        isLoading: state.locationLoading,
                        action: { state.enableLocation() }
                    )

                    PermissionCard(
                        icon: "heart.fill", color: .pink,
                        title: "Apple Health",
                        subtitle: "Sync steps, workouts, sleep & heart rate",
                        detail: "Read-only — NodeCompass never writes health data",
                        isGranted: state.healthConnected,
                        isDenied: state.healthDenied,
                        isLoading: state.healthLoading,
                        action: { state.enableHealth() }
                    )

                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(NC.teal.opacity(0.5))
                        Text("Both are optional. Change anytime in Settings.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Step 3: Connect Data

    private var connectDataStep: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Text("Connect Your Data")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                Text("Set up one or both — or skip for now")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    DataSourceCard(
                        icon: "building.columns.fill", color: .blue,
                        title: "Bank Account",
                        subtitle: "Auto-sync all transactions via Plaid",
                        isConnected: state.bankConnected,
                        isLoading: state.bankLoading,
                        error: state.bankError,
                        action: { state.connectBank() },
                        actionLabel: "Connect"
                    )

                    DataSourceCard(
                        icon: "envelope.fill", color: .purple,
                        title: "Gmail",
                        subtitle: state.emailConnected
                            ? (state.connectedEmail ?? "Connected")
                            : "Find receipts from Amazon, Uber Eats & more",
                        isConnected: state.emailConnected,
                        isLoading: state.emailLoading,
                        error: state.emailError,
                        action: { state.connectEmail() },
                        actionLabel: "Connect"
                    )

                    // Privacy footnote
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(NC.teal.opacity(0.6))
                            Text("Secure & Private")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        PrivacyLine(icon: "lock.fill", text: "Plaid handles bank login — we never see passwords")
                        PrivacyLine(icon: "eye.slash.fill", text: "Gmail is read-only — only receipt emails")
                        PrivacyLine(icon: "iphone", text: "All data stays on this device")
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(NC.bgSurface)
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Step 4: Ready

    private var readyStep: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 28) {
                // Celebration — animated checkmark with glow
                ZStack {
                    Circle()
                        .fill(NC.teal.opacity(0.06))
                        .frame(width: 160, height: 160)
                        .blur(radius: 40)

                    // Pulsing ring
                    OnboardingPulseRing(color: .green)

                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "#22C55E"), Color(hex: "#16A34A")],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)

                        Image(systemName: "checkmark")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.bounce, options: .speed(0.5))
                    }
                    .shadow(color: Color(hex: "#22C55E").opacity(0.3), radius: 20, y: 4)
                }

                VStack(spacing: 8) {
                    Text("You're All Set!")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    Text("NodeCompass will start learning your patterns and building your life dashboard.")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                // Summary of connected sources
                VStack(spacing: 8) {
                    if state.locationConnected {
                        ReadyCheckRow(icon: "location.fill", color: .blue, text: "Location tracking active")
                    }
                    if state.healthConnected {
                        ReadyCheckRow(icon: "heart.fill", color: .pink, text: "Apple Health connected")
                    }
                    if state.bankConnected {
                        ReadyCheckRow(icon: "building.columns.fill", color: .blue, text: "Bank account linked")
                    }
                    if state.emailConnected {
                        ReadyCheckRow(icon: "envelope.fill", color: .purple, text: state.connectedEmail ?? "Gmail connected")
                    }
                    if !state.locationConnected && !state.healthConnected && !state.bankConnected && !state.emailConnected {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Connect data sources anytime from the You tab")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.top, 4)
            }

            Spacer()
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                // Back button
                if currentStep > 0 && currentStep < totalSteps - 1 {
                    Button {
                        withAnimation(.spring(response: 0.35)) { currentStep -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(width: 50, height: 54)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(NC.bgSurface)
                            )
                    }
                }

                // Main CTA — glassmorphic teal
                Button {
                    Haptic.light()
                    handleNext()
                } label: {
                    Text(nextLabel)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [NC.teal, NC.teal.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )

                                // Subtle glass overlay on top half
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.15), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: NC.teal.opacity(0.25), radius: 16, y: 6)
                }
            }

            // Skip option
            if currentStep == 2 || currentStep == 3 {
                Button {
                    withAnimation(.spring(response: 0.35)) { currentStep += 1 }
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
        }
    }

    private var nextLabel: String {
        switch currentStep {
        case 0: return "Get Started"
        case 1: return "Continue"
        case 2: return "Continue"
        case 3: return "Continue"
        case 4: return "Open NodeCompass"
        default: return "Next"
        }
    }

    private func handleNext() {
        if currentStep == 1 {
            Task { await AppLearningStage.shared.setUserFocus(selectedFocus) }
        }
        if currentStep < totalSteps - 1 {
            withAnimation(.spring(response: 0.35)) { currentStep += 1 }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        if state.locationConnected {
            UserDefaults.standard.set(true, forKey: "locationTrackingEnabled")
            LocationCollector.shared.startTracking()
        }
        if state.healthConnected {
            UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
            Task { await HealthCollector.shared.collectAndStore() }
        }
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        withAnimation(.easeInOut(duration: 0.3)) { isComplete = true }
    }
}

// MARK: - Onboarding Particle Field

/// Lighter version of the lock screen particles for onboarding.
private struct OnboardingParticleField: View {
    @State private var animate = false

    private let particles: [OnboardingParticle] = {
        let colors: [Color] = [NC.teal, Color(hex: "#6366F1"), Color(hex: "#3B82F6")]
        return (0..<10).map { _ in
            OnboardingParticle(
                x: CGFloat.random(in: 0...1),
                y: CGFloat.random(in: 0...1),
                size: CGFloat.random(in: 3...14),
                opacity: Double.random(in: 0.03...0.12),
                duration: Double.random(in: 7...15),
                delay: Double.random(in: 0...3),
                color: colors.randomElement()!
            )
        }
    }()

    var body: some View {
        GeometryReader { geo in
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .blur(radius: p.size * 0.8)
                    .opacity(p.opacity)
                    .position(
                        x: animate ? p.x * geo.size.width + 25 : p.x * geo.size.width - 25,
                        y: animate ? p.y * geo.size.height - 15 : p.y * geo.size.height + 15
                    )
                    .animation(
                        .easeInOut(duration: p.duration)
                        .repeatForever(autoreverses: true)
                        .delay(p.delay),
                        value: animate
                    )
            }
        }
        .onAppear { animate = true }
    }
}

private struct OnboardingParticle: Identifiable {
    let id = UUID()
    let x: CGFloat; let y: CGFloat; let size: CGFloat
    let opacity: Double; let duration: Double; let delay: Double
    let color: Color
}

// MARK: - Onboarding Pulse Ring

private struct OnboardingPulseRing: View {
    var color: Color = NC.teal
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: 1.5)
                .frame(width: 130, height: 130)
                .scaleEffect(pulse ? 1.1 : 0.95)
                .opacity(pulse ? 0.0 : 0.5)

            Circle()
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.4), color.opacity(0.0), Color(hex: "#6366F1").opacity(0.2), color.opacity(0.4)],
                        center: .center
                    ),
                    lineWidth: 1
                )
                .frame(width: 115, height: 115)
                .scaleEffect(pulse ? 1.03 : 1.0)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Permission Card (Glassmorphic)

private struct PermissionCard: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    let detail: String; let isGranted: Bool; let isDenied: Bool; let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isGranted ? .green.opacity(0.12) : color.opacity(0.1))
                        .frame(width: 46, height: 46)
                    Image(systemName: isGranted ? "checkmark" : icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isGranted ? .green : color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                if isGranted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce)
                } else if isLoading {
                    ProgressView().tint(color).scaleEffect(0.8)
                } else if isDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Settings")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.orange.opacity(0.12), in: Capsule())
                    }
                } else {
                    Button(action: action) {
                        Text("Enable")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(color, in: Capsule())
                    }
                }
            }

            if !isGranted {
                HStack(spacing: 8) {
                    Image(systemName: isDenied ? "exclamationmark.circle" : "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(isDenied ? .orange.opacity(0.6) : .white.opacity(0.25))
                    Text(isDenied ? "Permission denied — tap Settings to enable" : detail)
                        .font(.system(size: 11))
                        .foregroundStyle(isDenied ? .orange.opacity(0.7) : .white.opacity(0.3))
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 60)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isGranted ? Color.green.opacity(0.04) : NC.bgSurface)
        )
    }
}

// MARK: - Data Source Card (Glassmorphic)

private struct DataSourceCard: View {
    let icon: String; let color: Color; let title: String; let subtitle: String
    let isConnected: Bool; let isLoading: Bool; let error: String?
    let action: () -> Void; let actionLabel: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isConnected ? .green.opacity(0.12) : color.opacity(0.1))
                        .frame(width: 46, height: 46)
                    Image(systemName: isConnected ? "checkmark" : icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isConnected ? .green : color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(isConnected ? .green.opacity(0.8) : .white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                if isConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce)
                } else if isLoading {
                    ProgressView().tint(color).scaleEffect(0.8)
                } else {
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(color, in: Capsule())
                    }
                }
            }

            if let error {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 10)
                .padding(.leading, 60)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isConnected ? Color.green.opacity(0.04) : NC.bgSurface)
        )
    }
}

// MARK: - Reusable Components

// MARK: - Value Showcase Card

/// Shows a real-world insight example to convey the app's value.
private struct ValueShowcaseCard: View {
    let icon: String
    let color: Color
    let insight: String
    let detail: String
    let pillars: [String]
    let delay: Double
    let appeared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(insight)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                ForEach(pillars, id: \.self) { pillar in
                    Text(pillar)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(color.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.08), in: Capsule())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.04))
        )
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: appeared)
    }
}

// MARK: - How It Works Row

private struct HowItWorksRow: View {
    let step: String
    let title: String
    let desc: String
    let delay: Double
    let appeared: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text(step)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NC.teal)
                .frame(width: 28, height: 28)
                .background(NC.teal.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 16)
        .animation(.spring(response: 0.5).delay(delay), value: appeared)
    }
}

private struct PillarRow: View {
    let icon: String; let color: Color; let title: String; let desc: String
    let delay: Double; let appeared: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : 20)
        .animation(.spring(response: 0.5).delay(delay), value: appeared)
    }
}

private struct PrivacyLine: View {
    let icon: String; let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(NC.teal.opacity(0.5))
                .frame(width: 18)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct ReadyCheckRow: View {
    let icon: String; let color: Color; let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1), in: Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.green)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Onboarding State

class OnboardingState: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationConnected = false
    @Published var locationLoading = false
    @Published var locationDenied = false

    @Published var healthConnected = false
    @Published var healthLoading = false
    @Published var healthDenied = false

    @Published var bankConnected = false
    @Published var bankLoading = false
    @Published var bankError: String?

    @Published var emailConnected = false
    @Published var emailLoading = false
    @Published var emailError: String?
    @Published var connectedEmail: String?

    private var linkHandler: Handler?
    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()

    override init() {
        super.init()
        locationManager.delegate = self

        let locStatus = locationManager.authorizationStatus
        locationConnected = (locStatus == .authorizedAlways || locStatus == .authorizedWhenInUse)
        locationDenied = (locStatus == .denied || locStatus == .restricted)

        if HKHealthStore.isHealthDataAvailable() {
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
            let status = healthStore.authorizationStatus(for: stepType)
            healthConnected = (status == .sharingAuthorized)
            healthDenied = (status == .sharingDenied)
        }

        if UserDefaults.standard.bool(forKey: "healthKitAuthorized") {
            healthConnected = true
        }

        Task {
            let accounts = (try? await PlaidService.shared.getConnectedAccounts()) ?? []
            await MainActor.run { bankConnected = !accounts.isEmpty }
        }

        let emails = GmailService.shared.connectedEmails
        emailConnected = !emails.isEmpty
        connectedEmail = emails.first
    }

    // MARK: - Location

    func enableLocation() {
        locationLoading = true
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        } else if status == .denied || status == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            locationLoading = false
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            let granted = manager.authorizationStatus == .authorizedAlways ||
                          manager.authorizationStatus == .authorizedWhenInUse
            self.locationConnected = granted
            self.locationDenied = (manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted)
            self.locationLoading = false
            if granted { LocationCollector.shared.requestPermissionAndStart() }
        }
    }

    // MARK: - Health

    func enableHealth() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthDenied = true
            return
        }
        healthLoading = true

        let readTypes: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .stepCount)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.workoutType()
        ]

        healthStore.requestAuthorization(toShare: nil, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.healthConnected = success
                self?.healthDenied = !success
                self?.healthLoading = false
                if success {
                    UserDefaults.standard.set(true, forKey: "healthKitAuthorized")
                }
            }
        }
    }

    // MARK: - Bank

    func connectBank() {
        bankLoading = true
        bankError = nil
        Task {
            do {
                let plaid = PlaidService.shared
                let online = await plaid.isServerReachable()
                if !online {
                    await MainActor.run {
                        bankError = "Server offline — set up later in Settings"
                        bankLoading = false
                    }
                    return
                }
                let linkToken = try await plaid.createLinkToken()
                await MainActor.run {
                    var config = LinkTokenConfiguration(token: linkToken) { [weak self] success in
                        Task { @MainActor in
                            guard let self else { return }
                            do {
                                try await plaid.exchangePublicToken(success.publicToken, institutionName: success.metadata.institution.name)
                                let synced = try await plaid.syncTransactions()
                                for txn in synced where !txn.pending { TransactionStore.shared.addFromBank(txn) }
                                self.bankConnected = true; self.bankLoading = false
                            } catch {
                                self.bankError = "Sync failed — try again later"
                                self.bankLoading = false
                            }
                        }
                    }
                    config.onExit = { [weak self] exit in
                        Task { @MainActor in
                            if let e = exit.error { self?.bankError = e.errorMessage }
                            self?.bankLoading = false
                        }
                    }
                    let result = Plaid.create(config)
                    switch result {
                    case .success(let handler):
                        self.linkHandler = handler
                        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                              let vc = scene.windows.first?.rootViewController else {
                            self.bankError = "Cannot present bank screen"; self.bankLoading = false; return
                        }
                        handler.open(presentUsing: .viewController(vc))
                    case .failure(let e):
                        self.bankError = e.localizedDescription; self.bankLoading = false
                    }
                }
            } catch {
                await MainActor.run { bankError = error.localizedDescription; bankLoading = false }
            }
        }
    }

    // MARK: - Email

    func connectEmail() {
        emailLoading = true; emailError = nil
        Task {
            do {
                let email = try await GmailService.shared.signInNewAccount()
                await MainActor.run { emailConnected = true; connectedEmail = email; emailLoading = false }
            } catch {
                await MainActor.run {
                    if (error as NSError).code != GIDSignInError.canceled.rawValue {
                        emailError = "Sign-in failed — try again"
                    }
                    emailLoading = false
                }
            }
        }
    }
}
