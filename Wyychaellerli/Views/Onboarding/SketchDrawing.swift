import SwiftUI

// MARK: - Farben der Skizzen

/// Farben für die nachgezeichneten Bilder der Einführung.
///
/// Papier und Tinte haben je eine Dunkelvariante (siehe Theme.swift), die Weinfarben
/// kommen aus `WineType.color` und passen sich damit von selbst an.
enum SketchPalette {
    /// Cremefarbenes Papier, im Dunkelmodus ein warmes Dunkelgrau.
    static var paper: Color { .adaptive(light: (0.99, 0.97, 0.93), dark: (0.17, 0.15, 0.15)) }
    /// Tinte: fast schwarz auf Papier, fast weiss im Dunkelmodus.
    static var ink: Color { .adaptive(light: (0.24, 0.18, 0.18), dark: (0.93, 0.89, 0.85)) }
    /// Blasse Tinte für Nebensächliches.
    static var faint: Color { ink.opacity(0.4) }
    /// Ein Streifen Klebeband, mit dem die Skizze „aufgehängt“ ist.
    static var tape: Color { .adaptive(light: (0.95, 0.86, 0.60), dark: (0.55, 0.48, 0.30)) }
    static var wine: Color { WineType.red.color }
    static var straw: Color { WineType.white.color }
    static var rose: Color { WineType.rose.color }
    static var sparkling: Color { WineType.sparkling.color }
}

// MARK: - Zufall mit festem Startwert

/// Kleiner, deterministischer Zufallsgenerator (SplitMix64).
///
/// Das Wackeln der Linien muss bei jedem Neuzeichnen gleich ausfallen, sonst zittert
/// die Zeichnung bei jedem Layout-Durchlauf. Deshalb kein `SystemRandomNumberGenerator`.
struct SketchRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Pfade wie von Hand gezogen

extension Path {

    /// Dieselbe Linie, als wäre sie mit dem Stift nachgezogen: Gerade Strecken werden in
    /// kurze Stücke geteilt und jeder Punkt leicht verschoben. `seed` bestimmt das Muster.
    func sketched(roughness: CGFloat = 1.1, seed: UInt64) -> Path {
        var random = SketchRandom(seed: seed)
        var result = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero

        func wobble(_ point: CGPoint, _ amount: CGFloat) -> CGPoint {
            CGPoint(
                x: point.x + CGFloat.random(in: -amount...amount, using: &random),
                y: point.y + CGFloat.random(in: -amount...amount, using: &random)
            )
        }

        forEach { element in
            switch element {
            case .move(to: let point):
                current = point
                subpathStart = point
                result.move(to: wobble(point, roughness * 0.6))
            case .line(to: let point):
                let dx = point.x - current.x
                let dy = point.y - current.y
                let length = (dx * dx + dy * dy).squareRoot()
                let pieces = max(1, Int(length / 22))
                for index in 1...pieces {
                    let t = CGFloat(index) / CGFloat(pieces)
                    let along = CGPoint(x: current.x + dx * t, y: current.y + dy * t)
                    result.addLine(to: wobble(along, index == pieces ? roughness * 0.6 : roughness))
                }
                current = point
            case .quadCurve(to: let point, control: let control):
                result.addQuadCurve(to: wobble(point, roughness * 0.6), control: wobble(control, roughness))
                current = point
            case .curve(to: let point, control1: let control1, control2: let control2):
                result.addCurve(
                    to: wobble(point, roughness * 0.6),
                    control1: wobble(control1, roughness),
                    control2: wobble(control2, roughness)
                )
                current = point
            case .closeSubpath:
                result.closeSubpath()
                current = subpathStart
            }
        }
        return result
    }

    /// Gerade Linie zwischen zwei Punkten.
    static func line(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }

    /// Ersatz für Handschrift: eine leicht wellige Linie.
    static func scribble(from start: CGPoint, to end: CGPoint, amplitude: CGFloat = 1.6) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max((dx * dx + dy * dy).squareRoot(), 1)
        let pieces = max(2, Int(length / 12))
        let normal = CGPoint(x: -dy / length, y: dx / length)
        path.move(to: start)
        for index in 1...pieces {
            let t = CGFloat(index) / CGFloat(pieces)
            let middle = (CGFloat(index) - 0.5) / CGFloat(pieces)
            let sign: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let control = CGPoint(
                x: start.x + dx * middle + normal.x * amplitude * sign,
                y: start.y + dy * middle + normal.y * amplitude * sign
            )
            path.addQuadCurve(to: CGPoint(x: start.x + dx * t, y: start.y + dy * t), control: control)
        }
        return path
    }

    /// Pfeil mit Spitze am Ende. `bend` wölbt die Linie seitlich (positiv = rechts der Richtung).
    static func arrow(from start: CGPoint, to end: CGPoint, bend: CGFloat = 0, head: CGFloat = 8) -> Path {
        var path = Path()
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max((dx * dx + dy * dy).squareRoot(), 0.001)
        let normal = CGPoint(x: -dy / length, y: dx / length)
        let control = CGPoint(
            x: (start.x + end.x) / 2 + normal.x * bend,
            y: (start.y + end.y) / 2 + normal.y * bend
        )
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)

        // Richtung an der Spitze: vom Kontrollpunkt zum Endpunkt.
        let tx = end.x - control.x
        let ty = end.y - control.y
        let tangentLength = max((tx * tx + ty * ty).squareRoot(), 0.001)
        let ux = tx / tangentLength
        let uy = ty / tangentLength
        let angle = CGFloat.pi / 6
        for sign in [CGFloat(1), CGFloat(-1)] {
            let cosA = cos(angle)
            let sinA = sin(angle) * sign
            let bx = -(ux * cosA - uy * sinA)
            let by = -(ux * sinA + uy * cosA)
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x + bx * head, y: end.y + by * head))
        }
        return path
    }

    /// Häkchen, das `rect` ausfüllt.
    static func checkmark(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }

    /// Fünfzackiger Stern.
    static func star(center: CGPoint, radius: CGFloat, points: Int = 5) -> Path {
        var path = Path()
        let inner = radius * 0.45
        for index in 0..<(points * 2) {
            let r = index.isMultiple(of: 2) ? radius : inner
            let angle = -CGFloat.pi / 2 + CGFloat(index) * .pi / CGFloat(points)
            let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    /// Vier Ecken eines Kamera-Suchers um `rect`.
    static func viewfinder(in rect: CGRect, arm: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + arm))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + arm, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - arm, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + arm))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - arm))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + arm, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
        return path
    }

    /// Weinglas: Kelch als Bogen, Stiel, Fuss. `top` ist die Oberkante des Kelchs.
    static func wineGlass(centerX cx: CGFloat, top: CGFloat) -> Path {
        var path = Path()
        // Kelch
        path.move(to: CGPoint(x: cx - 26, y: top))
        path.addCurve(to: CGPoint(x: cx, y: top + 62),
                      control1: CGPoint(x: cx - 26, y: top + 45),
                      control2: CGPoint(x: cx - 12, y: top + 62))
        path.addCurve(to: CGPoint(x: cx + 26, y: top),
                      control1: CGPoint(x: cx + 12, y: top + 62),
                      control2: CGPoint(x: cx + 26, y: top + 45))
        path.closeSubpath()
        // Stiel
        path.move(to: CGPoint(x: cx, y: top + 62))
        path.addLine(to: CGPoint(x: cx, y: top + 108))
        return path
    }

    /// Der Wein im Kelch des Glases aus `wineGlass`.
    static func wineInGlass(centerX cx: CGFloat, top: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: cx - 21, y: top + 28))
        path.addCurve(to: CGPoint(x: cx, y: top + 61),
                      control1: CGPoint(x: cx - 22, y: top + 48),
                      control2: CGPoint(x: cx - 10, y: top + 61))
        path.addCurve(to: CGPoint(x: cx + 21, y: top + 28),
                      control1: CGPoint(x: cx + 10, y: top + 61),
                      control2: CGPoint(x: cx + 22, y: top + 48))
        path.closeSubpath()
        return path
    }
}

// MARK: - Der Stift

/// Zeichnet in eine `GraphicsContext` wie mit einem Filzstift: jede Linie leicht wackelig
/// und doppelt gezogen, der zweite Strich blasser und etwas versetzt.
///
/// Der Stift hält eine Kopie des Kontexts. Zeichenbefehle auf einer Kopie landen auf
/// derselben Fläche; nur Zustand wie Transformation oder Clip bleibt bei der Kopie.
struct SketchPen {

    var context: GraphicsContext
    var roughness: CGFloat = 1.1
    private var seed: UInt64

    init(_ context: GraphicsContext, seed: UInt64 = 1) {
        self.context = context
        self.seed = seed
    }

    private mutating func nextSeed() -> UInt64 {
        seed &+= 1
        return seed
    }

    /// Linie im Doppelstrich.
    mutating func stroke(_ path: Path, _ color: Color, width: CGFloat = 2) {
        let main = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let second = StrokeStyle(lineWidth: width * 0.7, lineCap: .round, lineJoin: .round)
        context.stroke(path.sketched(roughness: roughness, seed: nextSeed()), with: .color(color), style: main)
        context.stroke(path.sketched(roughness: roughness * 1.3, seed: nextSeed()),
                       with: .color(color.opacity(0.35)), style: second)
    }

    /// Fläche, ebenfalls mit leicht unruhigem Rand.
    mutating func fill(_ path: Path, _ color: Color) {
        context.fill(path.sketched(roughness: roughness, seed: nextSeed()), with: .color(color))
    }

    /// Fläche mit Umriss.
    mutating func shape(_ path: Path, fill: Color, stroke: Color, width: CGFloat = 2) {
        self.fill(path, fill)
        self.stroke(path, stroke, width: width)
    }

    /// Beschriftung in der runden Systemschrift, die zur Skizze passt.
    mutating func text(
        _ string: String,
        at point: CGPoint,
        size: CGFloat = 10,
        weight: Font.Weight = .medium,
        color: Color,
        anchor: UnitPoint = .center
    ) {
        let text = Text(string)
            .font(.system(size: size, weight: weight, design: .rounded))
            .foregroundStyle(color)
        context.draw(text, at: point, anchor: anchor)
    }

    /// Ein Streifen Klebeband, leicht schräg.
    mutating func tape(at center: CGPoint, width: CGFloat = 64, angle: CGFloat = -0.06) {
        let rect = CGRect(x: -width / 2, y: -8, width: width, height: 16)
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle)
        let path = Path(roundedRect: rect, cornerRadius: 2, style: .continuous).applying(transform)
        fill(path, SketchPalette.tape.opacity(0.85))
        stroke(path, SketchPalette.ink.opacity(0.25), width: 1)
    }

    /// Stehende Flasche in der Farbe der Weinart, mit hellem Etikettstreifen.
    mutating func bottle(in rect: CGRect, color: Color, outline: Bool = true) {
        let body = BottleShape().path(in: rect)
        fill(body, color.opacity(0.85))
        if outline {
            stroke(body, SketchPalette.ink, width: max(0.8, rect.width * 0.09))
        }
        let label = CGRect(
            x: rect.minX + rect.width * 0.18,
            y: rect.minY + rect.height * 0.58,
            width: rect.width * 0.64,
            height: rect.height * 0.2
        )
        fill(Path(roundedRect: label, cornerRadius: rect.width * 0.08, style: .continuous),
             SketchPalette.paper.opacity(0.85))
    }

    /// Stern, gefüllt oder nur als Umriss.
    mutating func star(at center: CGPoint, radius: CGFloat, filled: Bool) {
        let path = Path.star(center: center, radius: radius)
        if filled {
            fill(path, SketchPalette.straw)
        }
        stroke(path, filled ? SketchPalette.straw : SketchPalette.faint, width: 1.2)
    }
}
