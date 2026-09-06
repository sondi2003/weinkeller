import SwiftUI

/// Die drei Tabs der App.
enum AppTab: Hashable {
    case cellar
    case advisor
    case settings
}

struct ContentView: View {

    @State private var selectedTab: AppTab = .cellar
    @State private var isShowingSplash = true

    var body: some View {
        ZStack {
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

            if isShowingSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(1)
            }
        }
        .task {
            try? await Task.sleep(for: SplashView.displayDuration)
            withAnimation(.easeInOut(duration: 0.5)) {
                isShowingSplash = false
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
}
