import SwiftUI

/// Die Einführung beim ersten Start: sechs Seiten mit nachgezeichneten Bildern zu
/// Etikett-Scan, Keller, Regal, Wein-Berater und Freigabe.
///
/// Erscheint als Vollbild über den Tabs, sobald der Startbildschirm ausgeblendet ist
/// (`ContentView`), und lässt sich aus den Einstellungen jederzeit erneut öffnen.
/// Ob sie schon gesehen wurde, steht in `UserDefaults` unter `completedKey` – eine
/// Geräte-Einstellung wie das Erscheinungsbild, bewusst nicht in iCloud.
struct OnboardingView: View {

    /// Schlüssel für `@AppStorage`, an einer Stelle definiert.
    static let completedKey = "onboarding.completed"

    /// Wird beim Überspringen und auf der letzten Seite aufgerufen.
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: OnboardingPage = .welcome

    var body: some View {
        VStack(spacing: 0) {
            topBar

            TabView(selection: $selection) {
                ForEach(OnboardingPage.allCases) { page in
                    OnboardingPageView(page: page)
                        .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            controls
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }

    // MARK: Bausteine

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Überspringen", action: onFinish)
                .font(.subheadline)
                .opacity(selection.isLast ? 0 : 1)
                .disabled(selection.isLast)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.2), value: selection)
    }

    private var controls: some View {
        VStack(spacing: 16) {
            PageDots(count: OnboardingPage.allCases.count, current: selection.rawValue)

            Button {
                advance()
            } label: {
                Text(selection.isLast ? "Los geht's" : "Weiter")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)

            // Nur auf der letzten Seite; davor hält die Zeile den Platz, damit der Knopf
            // nicht springt.
            Text("Du findest diese Einführung jederzeit wieder in den Einstellungen unter „Hilfe“.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .opacity(selection.isLast ? 1 : 0)
                .accessibilityHidden(!selection.isLast)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .animation(reduceMotion ? nil : Animation.easeInOut(duration: 0.2), value: selection)
    }

    private func advance() {
        if let next = selection.next {
            withAnimation(reduceMotion ? nil : Animation.easeInOut) {
                selection = next
            }
        } else {
            onFinish()
        }
    }
}

// MARK: - Eine Seite

private struct OnboardingPageView: View {

    let page: OnboardingPage

    var body: some View {
        // Scrollbar, damit bei grosser Schrift oder kleinem Bildschirm nichts abgeschnitten wird.
        ScrollView {
            VStack(spacing: 24) {
                SketchIllustrationView(page: page)
                    .frame(maxWidth: 360)
                    .padding(.horizontal, 12)

                VStack(spacing: 10) {
                    Text(page.title)
                        .font(.system(.title2, design: .serif, weight: .bold))
                        .multilineTextAlignment(.center)
                    Text(page.text)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
            }
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Seitenpunkte

/// Eigene Punkte statt der System-Anzeige: Die ist auf hellem Grund kaum zu sehen.
private struct PageDots: View {

    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(current + 1) von \(count)")
    }
}

#Preview("Einführung") {
    OnboardingView { }
}

#Preview("Dunkel") {
    OnboardingView { }
        .preferredColorScheme(.dark)
}
