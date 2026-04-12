import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedTab: Int = 0

    init() {
        // Modern translucent tab bar
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemThinMaterial)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
                .tag(0)

            WealthTabView()
                .tabItem {
                    Label("Wealth", systemImage: NC.currencyIconCircle)
                }
                .tag(1)

            HealthTabView()
                .tabItem {
                    Label("Health", systemImage: "heart.fill")
                }
                .tag(2)

            MindTabView()
                .tabItem {
                    Label("Mind", systemImage: "brain.head.profile")
                }
                .tag(3)

            YouTabView()
                .tabItem {
                    Label("You", systemImage: "person.fill")
                }
                .tag(4)
        }
        .tint(NC.teal)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("navigateToYouTab"))) { _ in
            selectedTab = 4
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TransactionStore.shared)
}
