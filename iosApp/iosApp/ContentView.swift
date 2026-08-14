import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedTab: Int = 0

    private let tabs: [(icon: String, label: String)] = [
        ("sun.max.fill", "Today"),
        (NC.currencyIconCircle, "Wealth"),
        ("heart.fill", "Health"),
        ("brain.head.profile", "Mind"),
        ("person.fill", "You"),
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content — finger-following page swipe. Each tab is
            // mounted as a page so horizontal swipes drag in real-time
            // (iOS Photos / Weather style). Auth cache in
            // `AnonymousIdentity.ensureSession()` prevents the re-auth
            // cascade that sunk the earlier attempt at this UX.
            TabView(selection: $selectedTab) {
                DashboardView().tag(0)
                WealthTabView().tag(1)
                HealthTabView().tag(2)
                MindTabView().tag(3)
                YouTabView().tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 70)
            }

            // Floating tab bar
            FloatingTabBar(selectedTab: $selectedTab, tabs: tabs)
        }
        .ignoresSafeArea(.keyboard)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("navigateToYouTab"))) { _ in
            selectedTab = 4
        }
    }
}

// MARK: - Floating Tab Bar

private struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    let tabs: [(icon: String, label: String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                tabButton(index: index, icon: tab.icon, label: tab.label)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(NC.bgSurface)
        )
        .padding(.horizontal, 24)
        .padding(.bottom, 6)
    }

    private func tabButton(index: Int, icon: String, label: String) -> some View {
        let isSelected = selectedTab == index
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                Haptic.light()
                selectedTab = index
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    // Selected indicator pill
                    if isSelected {
                        Capsule()
                            .fill(NC.teal.opacity(0.15))
                            .frame(width: 48, height: 28)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .symbolEffect(.bounce, value: isSelected)
                }
                .frame(height: 28)

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? NC.teal : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environmentObject(TransactionStore.shared)
}
