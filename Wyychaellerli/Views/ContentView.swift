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
    @AppStorage(WalkthroughView.seenKey) private var hasSeenWalkthrough = false
    @State private var isShowingWalkthrough = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                CellarView()
                    .tabItem { Label("Wyychällerli", systemImage: "cabinet") }
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
            // Die Einführung kommt erst, wenn der Splash weg ist – sonst überlagern sie sich.
            if !hasSeenWalkthrough {
                try? await Task.sleep(for: .milliseconds(400))
                isShowingWalkthrough = true
            }
        }
        .fullScreenCover(isPresented: $isShowingWalkthrough) {
            WalkthroughView()
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
}
