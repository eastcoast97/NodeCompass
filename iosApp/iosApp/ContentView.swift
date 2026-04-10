import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: TransactionStore
    @State private var selectedTab: Int = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            TransactionListView()
                .tabItem {
                    Label("Activity", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(1)

            InsightsView()
                .tabItem {
                    Label("Insights", systemImage: "lightbulb.fill")
                }
                .tag(2)

            YouTabView()
                .tabItem {
                    Label("You", systemImage: "person.fill")
                }
                .tag(3)
        }
        .tint(NC.teal)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("navigateToYouTab"))) { _ in
            selectedTab = 3
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TransactionStore.shared)
}
