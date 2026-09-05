import SwiftUI

/// Die drei Tabs der App.
enum AppTab: Hashable {
    case cellar
    case advisor
    case settings
}

struct ContentView: View {

    @State private var selectedTab: AppTab = .cellar

    var body: some View {
        TabView(selection: $selectedTab) {
            CellarView()
                .tabItem { Label("Weinkeller", systemImage: "cabinet") }
                .tag(AppTab.cellar)

            AdvisorView(selectedTab: $selectedTab)
                .tabItem { Label("Wein-Berater", systemImage: "sparkles") }
                .tag(AppTab.advisor)

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewData.container)
        .environment(AISettings(defaults: PreviewData.defaults))
}
