import SwiftUI

/// Konfetti-Regen über dem Podest.
///
/// Bewusst selbst gezeichnet statt einer fremden Bibliothek: Es sind vierzig Zeilen,
/// und eine Abhängigkeit für einen Effekt lohnt nicht.
///
/// Jedes Schnipsel ist eine Formel, kein gespeicherter Zustand – Position und Drehung
/// ergeben sich allein aus der verstrichenen Zeit. Deshalb genügt ein `Canvas` in einer
/// `TimelineView`, ganz ohne Animation je Teilchen, und hunderte Schnipsel kosten nichts.
struct ConfettiView: View {

    /// Wie lange es rieselt. Danach bleibt der Bildschirm ruhig.
    var duration: TimeInterval = 5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private let pieces: [Piece] = {
        var random = SeededRandom(seed: 20260910)
        // Weinfarben statt Kirmesbunt – es geht schliesslich um eine Flasche.
        let palette: [Color] = [
            Color(red: 0.55, green: 0.10, blue: 0.20),   // Bordeaux
            Color(red: 0.85, green: 0.72, blue: 0.30),   // Goldgelb
            Color(red: 0.90, green: 0.55, blue: 0.62),   // Rosé
            Color(red: 0.30, green: 0.52, blue: 0.45),   // Flaschengrün
            Color(red: 0.95, green: 0.90, blue: 0.80)    // Elfenbein
        ]
        let count = 120
        return (0..<count).map { index in
            Piece(
                // Gleichmässig über die Breite verteilt, nur leicht verwackelt. Reiner
                // Zufall lässt sonst sichtbar Lücken – gemessen: eine Spalte mit 14
                // statt 25 Schnipseln.
                x: (Double(index) + random.next()) / Double(count),
                delay: random.next() * 1.6,
                speed: 0.28 + random.next() * 0.34,
                driftAmplitude: 0.02 + random.next() * 0.07,
                driftSpeed: 0.6 + random.next() * 1.8,
                spin: (random.next() - 0.5) * 8,
                width: 5 + random.next() * 6,
                height: 8 + random.next() * 8,
                color: palette[Int(random.next() * Double(palette.count)) % palette.count]
            )
        }
    }()

    var body: some View {
        // Bei reduzierter Bewegung gar nichts – ein Konfettiregen ist genau das, wovor
        // diese Einstellung schützen soll.
        if !reduceMotion {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let elapsed = timeline.date.timeIntervalSince(start)
                    guard elapsed < duration + 2 else { return }
                    for piece in pieces {
                        draw(piece, at: elapsed, in: &context, size: size)
                    }
                }
            }
            .allowsHitTesting(false)
            .ignoresSafeArea()
            .onAppear { start = Date() }
        }
    }

    private func draw(_ piece: Piece, at elapsed: TimeInterval, in context: inout GraphicsContext, size: CGSize) {
        let t = elapsed - piece.delay
        guard t > 0 else { return }

        // Fallhöhe in Bildschirmhöhen; oberhalb starten, unterhalb enden.
        let progress = t * piece.speed
        guard progress < 1.25 else { return }
        let y = (progress - 0.15) * size.height
        let x = (piece.x + sin(t * piece.driftSpeed) * piece.driftAmplitude) * size.width

        // Zum Schluss ausblenden, damit es nicht abrupt aufhört.
        let fade = elapsed > duration ? max(0, 1 - (elapsed - duration) / 2) : 1
        guard fade > 0 else { return }

        var slip = context
        slip.translateBy(x: x, y: y)
        slip.rotate(by: .radians(t * piece.spin))
        // Kippen ums Hochkant: Das Schnipsel wirkt, als drehe es sich im Fall.
        let squeeze = abs(cos(t * piece.spin * 0.7))
        let rect = CGRect(
            x: -piece.width / 2,
            y: -piece.height / 2,
            width: piece.width,
            height: max(1, piece.height * squeeze)
        )
        slip.opacity = fade
        slip.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(piece.color))
    }

    /// Ein Schnipsel – alles Nötige, um seine Bahn zu berechnen.
    private struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let driftAmplitude: Double
        let driftSpeed: Double
        let spin: Double
        let width: Double
        let height: Double
        let color: Color
    }

    /// Wiederholbarer Zufall, damit das Muster bei jedem Start gleich verteilt ist
    /// und nicht zufällig einmal alles in einer Ecke landet.
    private struct SeededRandom {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &* 6364136223846793005 &+ 1442695040888963407
        }

        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }
}
