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

    /// Ob die Einführung schon gesehen wurde. Die Einstellungen setzen den Wert auf
    /// `false`, um sie erneut zu zeigen.
    @AppStorage(OnboardingView.completedKey) private var hasCompletedOnboarding = false

    /// Die Einführung kommt erst, wenn der Startbildschirm weg ist – sonst schiebt sie
    /// sich noch während der Animation darüber.
    private var isShowingOnboarding: Binding<Bool> {
        Binding(
            get: { !isShowingSplash && !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )
    }

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
        }
        .fullScreenCover(isPresented: isShowingOnboarding) {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PreviewData.context)
        .environment(AISettings(defaults: PreviewData.defaults))
}
