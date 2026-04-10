import SwiftUI
import CoreLocation

/// Guided onboarding sheet for location intelligence.
/// Explains value, privacy, and battery before requesting permission.
struct LocationSetupView: View {
    @Binding var isPresented: Bool
    @StateObject private var locationCollector = LocationCollector.shared
    @State private var currentStep = 0
    @State private var permissionRequested = false
    @State private var showSuccess = false

    private var isAuthorized: Bool {
        locationCollector.authorizationStatus == .authorizedAlways ||
        locationCollector.authorizationStatus == .authorizedWhenInUse
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSuccess {
                    successView
                } else {
                    // Step dots
                    stepIndicator
                        .padding(.top, 16)
                        .padding(.bottom, 24)

                    TabView(selection: $currentStep) {
                        step1WhyView.tag(0)
                        step2HowView.tag(1)
                        step3EnableView.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: currentStep)

                    Spacer()

                    bottomButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { isPresented = false }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: locationCollector.authorizationStatus) { _, newStatus in
                if permissionRequested &&
                   (newStatus == .authorizedAlways || newStatus == .authorizedWhenInUse) {
                    UserDefaults.standard.set(true, forKey: "locationTrackingEnabled")
                    withAnimation { showSuccess = true }
                }
            }
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { step in
                Capsule()
                    .fill(step <= currentStep ? Color.blue : Color(.systemGray4))
                    .frame(width: step == currentStep ? 24 : 8, height: 8)
                    .animation(.spring(), value: currentStep)
            }
        }
    }

    // MARK: - Step 1: Why

    private var step1WhyView: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "location.fill.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                }
                .padding(.top, 20)

                Text("Location Intelligence")
                    .font(.title2.bold())

                Text("NodeCompass passively learns where you go and connects it to your spending — building a complete picture of your life.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 14) {
                    featureRow(
                        icon: "mappin.and.ellipse",
                        color: .blue,
                        title: "Connect Spending to Places",
                        detail: "\"You spent $12.50 at Chipotle on Market St\""
                    )
                    featureRow(
                        icon: "clock.arrow.2.circlepath",
                        color: .purple,
                        title: "Learn Your Routines",
                        detail: "Detect gym habits, eating out patterns, commute times"
                    )
                    featureRow(
                        icon: "building.2.fill",
                        color: .orange,
                        title: "Know Your Frequent Places",
                        detail: "Auto-label home, work, gym, favorite restaurants"
                    )
                    featureRow(
                        icon: "lightbulb.fill",
                        color: NC.teal,
                        title: "Smarter Insights",
                        detail: "\"Eating out 4x/week, mostly on Fridays\""
                    )
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 2: How it works

    private var step2HowView: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 44))
                        .foregroundStyle(.green)
                }
                .padding(.top, 20)

                Text("Private & Battery-Friendly")
                    .font(.title2.bold())

                Text("Designed to be invisible. No battery drain, no data leaving your phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 16) {
                    privacyRow(
                        icon: "battery.100percent.bolt",
                        color: .green,
                        title: "Near-Zero Battery Impact",
                        detail: "Uses iOS visit detection — not continuous GPS. Your battery won't notice."
                    )
                    privacyRow(
                        icon: "iphone.gen3",
                        color: .blue,
                        title: "100% On-Device",
                        detail: "GPS coordinates never leave your phone. Not even to our servers (we don't have any)."
                    )
                    privacyRow(
                        icon: "eye.slash.fill",
                        color: .purple,
                        title: "You Control It",
                        detail: "Turn it off anytime in Settings. All location data is deleted when you clear data."
                    )
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .padding(.horizontal, 20)

                // Battery comparison visual
                VStack(spacing: 8) {
                    Text("Battery comparison")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        batteryBar(label: "NodeCompass", percent: 0.02, color: .green)
                        batteryBar(label: "Continuous GPS", percent: 0.45, color: .red)
                    }
                    .padding(.horizontal, 8)
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 3: Enable

    private var step3EnableView: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.blue)
                }
                .padding(.top, 20)

                Text("Enable Location")
                    .font(.title2.bold())

                Text("When iOS asks, choose \"Allow While Using App\" or \"Always Allow\" for the best experience.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                // Permission tips
                VStack(alignment: .leading, spacing: 14) {
                    tipRow(
                        recommended: true,
                        title: "Always Allow",
                        detail: "Best experience — learns places even when app is closed"
                    )
                    tipRow(
                        recommended: false,
                        title: "While Using App",
                        detail: "Works but only tracks when you open NodeCompass"
                    )
                }
                .padding(16)
                .background(.background, in: RoundedRectangle(cornerRadius: NC.cardRadius))
                .padding(.horizontal, 20)

                if locationCollector.authorizationStatus == .denied ||
                   locationCollector.authorizationStatus == .restricted {
                    VStack(spacing: 10) {
                        Text("Location access was previously denied")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.orange, in: Capsule())
                        }
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: NC.cardRadius))
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
            }

            Text("Location Intelligence Active")
                .font(.title.bold())

            Text("NodeCompass is now passively learning your places. Insights will appear as you go about your day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    Text("First insights appear within 24–48 hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.secondary)
                    Text("Manage in Settings anytime")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)

            Spacer()

            Button {
                isPresented = false
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Bottom Buttons

    private var bottomButtons: some View {
        HStack {
            if currentStep > 0 {
                Button {
                    withAnimation { currentStep -= 1 }
                } label: {
                    Text("Back")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }

            Spacer()

            if currentStep < 2 {
                Button {
                    withAnimation { currentStep += 1 }
                } label: {
                    Text("Next")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(Color.blue, in: Capsule())
                }
            } else {
                Button {
                    enableLocation()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        Text("Enable Location")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                    .background(Color.blue, in: Capsule())
                }
            }
        }
    }

    // MARK: - Actions

    private func enableLocation() {
        permissionRequested = true
        LocationCollector.shared.requestPermissionAndStart()

        // If already authorized (e.g., re-enabling), go straight to success
        if isAuthorized {
            UserDefaults.standard.set(true, forKey: "locationTrackingEnabled")
            withAnimation { showSuccess = true }
        }
    }

    // MARK: - Subviews

    private func featureRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func privacyRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func tipRow(recommended: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(recommended ? Color.blue.opacity(0.12) : Color(.systemGray5))
                    .frame(width: 36, height: 36)
                Image(systemName: recommended ? "star.fill" : "minus")
                    .font(.callout)
                    .foregroundStyle(recommended ? .blue : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.bold())
                    if recommended {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue, in: Capsule())
                    }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func batteryBar(label: String, percent: Double, color: Color) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: geo.size.width * percent)
                }
            }
            .frame(height: 12)

            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Text(percent < 0.1 ? "<1%/hr" : "\(Int(percent * 100))%/hr")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
        }
    }
}
