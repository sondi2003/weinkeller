import SwiftUI

// MARK: - Seiten der Einführung

/// Die Seiten der Einführung, in der Reihenfolge, in der sie erscheinen.
enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case scan
    case cellar
    case rack
    case advisor
    case share

    var id: Int { rawValue }

    var isLast: Bool { self == OnboardingPage.allCases.last }

    var next: OnboardingPage? {
        OnboardingPage(rawValue: rawValue + 1)
    }

    var title: String {
        switch self {
        case .welcome: return "Willkommen im Wyychällerli"
        case .scan:    return "Etikett scannen statt tippen"
        case .cellar:  return "Den Bestand im Blick"
        case .rack:    return "Jede Flasche hat ihr Fach"
        case .advisor: return "Was gibt es zu essen?"
        case .share:   return "Zu zweit im Keller"
        }
    }

    var text: String {
        switch self {
        case .welcome:
            return "Dein Weinkeller in der Hosentasche: Flaschen erfassen, im Regal wiederfinden und zum Essen die passende Flasche wählen. Auf den nächsten Seiten zeigen wir dir in Kürze, wie es geht."
        case .scan:
            return "Tippe im Keller auf „+“ und dann auf „Etikett scannen“. Fotografiere die Flasche einfach ganz – die App findet das Etikett selbst, schneidet es zu und liest Name, Jahrgang, Rebsorte und Region aus. Die Rückseite lohnt sich auch: Dort stehen oft Speiseempfehlungen des Produzenten."
        case .cellar:
            return "Jede Zeile zeigt, wie viele Flaschen da sind. Öffnest du eine, tippst du auf den Minus-Knopf. Ist die letzte weg, fragt die App, ob du den Wein bewerten oder archivieren willst. Nach links wischen: archivieren oder löschen. Nach rechts: bearbeiten."
        case .rack:
            return "Im Menü oben links findest du dein Regal. Lege einmal fest, wie viele Zeilen und Spalten es hat. Danach tippst du auf einen Wein unter „Noch nicht im Regal“ und wählst seine Fächer – oder auf ein freies Fach für eine einzelne Flasche. Auf der Detailseite siehst du später, wo die Flasche liegt."
        case .advisor:
            return "Tippe ein Gericht ein, etwa „Raclette“. Zuerst schaut die App auf die Speiseempfehlungen der Etiketten in deinem Keller. Für eine echte Empfehlung braucht es einen API-Key von OpenAI, Gemini oder Anthropic – den trägst du in den Einstellungen ein. Ohne Key funktioniert alles andere trotzdem."
        case .share:
            return "In den Einstellungen teilst du deinen Keller mit deiner Partnerin oder deinem Partner. Beide sehen dieselben Flaschen und dasselbe Regal, über iCloud. Bewertet wird pro Person, die App bildet daraus ein gemeinsames Urteil und einen Kaufhinweis."
        }
    }

    /// SF Symbols, die über die Zeichnung gelegt werden (in Zeichnungskoordinaten).
    /// Symbole lassen sich in einer `Canvas` nicht sauber nachzeichnen, deshalb liegen
    /// sie als normale Views darüber.
    var symbols: [SketchSymbol] {
        switch self {
        case .welcome:
            return [
                SketchSymbol(name: "sparkle", point: CGPoint(x: 256, y: 52), size: 15, color: SketchPalette.straw),
                SketchSymbol(name: "sparkle", point: CGPoint(x: 270, y: 82), size: 9, color: SketchPalette.straw),
                SketchSymbol(name: "sparkle", point: CGPoint(x: 168, y: 40), size: 10, color: SketchPalette.straw)
            ]
        case .scan:
            return [
                SketchSymbol(name: "camera.fill", point: CGPoint(x: 82, y: 186), size: 13, color: SketchPalette.faint)
            ]
        case .cellar:
            return [
                SketchSymbol(name: "hand.point.up.left.fill", point: CGPoint(x: 264, y: 136), size: 24, color: SketchPalette.ink)
            ]
        case .rack:
            return [
                SketchSymbol(name: "hand.point.up.left.fill", point: CGPoint(x: 189, y: 122), size: 24, color: SketchPalette.ink)
            ]
        case .advisor:
            return [
                SketchSymbol(name: "fork.knife", point: CGPoint(x: 48, y: 41), size: 15, color: SketchPalette.ink),
                SketchSymbol(name: "sparkles", point: CGPoint(x: 108, y: 81), size: 11, color: .white)
            ]
        case .share:
            return [
                SketchSymbol(name: "icloud.fill", point: CGPoint(x: 150, y: 46), size: 40, color: SketchPalette.sparkling)
            ]
        }
    }

    /// Verschiedene Startwerte, damit nicht alle Seiten dasselbe Wackelmuster zeigen.
    var seed: UInt64 { UInt64(rawValue + 1) * 1000 }
}

/// Ein SF Symbol an einer Stelle der Zeichnung.
struct SketchSymbol: Identifiable {
    let name: String
    let point: CGPoint
    let size: CGFloat
    let color: Color

    var id: String { "\(name)-\(Int(point.x))-\(Int(point.y))" }
}

// MARK: - Die Zeichnungen

/// Die nachgezeichneten Bilder, eines pro Seite. Alle in einem festen Zeichnungsraum
/// von 300 × 225 Punkten; `SketchIllustrationView` skaliert auf die verfügbare Breite.
enum Sketches {

    static let designSize = CGSize(width: 300, height: 225)

    static func draw(_ page: OnboardingPage, with pen: inout SketchPen) {
        pen.tape(at: CGPoint(x: designSize.width / 2, y: 8))
        switch page {
        case .welcome: welcome(&pen)
        case .scan:    scan(&pen)
        case .cellar:  cellar(&pen)
        case .rack:    rack(&pen)
        case .advisor: advisor(&pen)
        case .share:   share(&pen)
        }
    }

    // MARK: Willkommen: Flasche und Glas

    private static func welcome(_ pen: inout SketchPen) {
        let ink = SketchPalette.ink

        // Boden
        pen.stroke(.scribble(from: CGPoint(x: 55, y: 200), to: CGPoint(x: 255, y: 200), amplitude: 1.2),
                   SketchPalette.faint, width: 1.4)

        // Flasche
        let bottleRect = CGRect(x: 85, y: 32, width: 62, height: 165)
        let bottle = BottleShape().path(in: bottleRect)
        pen.shape(bottle, fill: SketchPalette.wine.opacity(0.32), stroke: ink, width: 2.2)
        // Kapsel am Hals
        pen.fill(Path(roundedRect: CGRect(x: 104, y: 34, width: 24, height: 16), cornerRadius: 3, style: .continuous),
                 ink.opacity(0.55))
        // Etikett mit „Schrift“
        let label = CGRect(x: 93, y: 126, width: 46, height: 44)
        pen.shape(Path(roundedRect: label, cornerRadius: 4, style: .continuous),
                  fill: SketchPalette.paper, stroke: ink, width: 1.4)
        pen.stroke(.scribble(from: CGPoint(x: 100, y: 137), to: CGPoint(x: 132, y: 137)), ink.opacity(0.75), width: 1.6)
        pen.stroke(.scribble(from: CGPoint(x: 100, y: 146), to: CGPoint(x: 124, y: 146)), ink.opacity(0.55), width: 1.1)
        pen.text("2017", at: CGPoint(x: 116, y: 160), size: 9, weight: .semibold, color: SketchPalette.wine)

        // Glas
        let cx: CGFloat = 215
        let top: CGFloat = 62
        pen.fill(.wineInGlass(centerX: cx, top: top), SketchPalette.wine.opacity(0.5))
        pen.stroke(Path(ellipseIn: CGRect(x: cx - 20, y: top + 25, width: 40, height: 7)),
                   SketchPalette.wine.opacity(0.7), width: 1.2)
        pen.stroke(.wineGlass(centerX: cx, top: top), ink, width: 2.2)
        pen.shape(Path(ellipseIn: CGRect(x: cx - 24, y: top + 105, width: 48, height: 9)),
                  fill: SketchPalette.paper, stroke: ink, width: 2)
    }

    // MARK: Etikett scannen: Telefon, Pfeil, ausgefülltes Formular

    private static func scan(_ pen: inout SketchPen) {
        let ink = SketchPalette.ink

        // Telefon
        let phone = CGRect(x: 28, y: 20, width: 108, height: 186)
        pen.shape(Path(roundedRect: phone, cornerRadius: 16, style: .continuous),
                  fill: SketchPalette.paper, stroke: ink, width: 2.2)
        pen.stroke(Path(roundedRect: phone.insetBy(dx: 8, dy: 12), cornerRadius: 8, style: .continuous),
                   SketchPalette.faint, width: 1)
        pen.stroke(.line(from: CGPoint(x: 70, y: 26), to: CGPoint(x: 94, y: 26)), SketchPalette.faint, width: 1.4)

        // Flasche auf dem Bildschirm, dunkel wie in echt
        let bottleRect = CGRect(x: 63, y: 44, width: 38, height: 120)
        pen.shape(BottleShape().path(in: bottleRect), fill: SketchPalette.wine.opacity(0.7), stroke: ink, width: 1.5)
        let label = CGRect(x: 68, y: 116, width: 28, height: 26)
        pen.shape(Path(roundedRect: label, cornerRadius: 2, style: .continuous),
                  fill: SketchPalette.paper, stroke: ink, width: 1)
        pen.stroke(.scribble(from: CGPoint(x: 72, y: 124), to: CGPoint(x: 92, y: 124), amplitude: 1), ink.opacity(0.7), width: 1)
        pen.stroke(.scribble(from: CGPoint(x: 72, y: 132), to: CGPoint(x: 87, y: 132), amplitude: 1), ink.opacity(0.5), width: 0.9)

        // Sucher um das Etikett
        pen.stroke(.viewfinder(in: CGRect(x: 52, y: 104, width: 60, height: 52), arm: 12), Color.accentColor, width: 2.5)

        // Pfeil zum Formular
        pen.stroke(.arrow(from: CGPoint(x: 142, y: 112), to: CGPoint(x: 168, y: 112), head: 8), ink, width: 2)

        // Formular
        let card = CGRect(x: 172, y: 34, width: 118, height: 158)
        pen.shape(Path(roundedRect: card, cornerRadius: 12, style: .continuous),
                  fill: SketchPalette.paper, stroke: ink, width: 2)
        pen.text("Etikett gelesen", at: CGPoint(x: card.midX, y: 48), size: 9.5, weight: .semibold, color: ink)
        pen.stroke(.line(from: CGPoint(x: 182, y: 57), to: CGPoint(x: 280, y: 57)), SketchPalette.faint, width: 0.8)

        let rows: [(label: String, value: String?, width: CGFloat)] = [
            ("Name", nil, 68),
            ("Jahrgang", "2017", 0),
            ("Rebsorte", nil, 52),
            ("Region", nil, 60)
        ]
        for (index, row) in rows.enumerated() {
            let y: CGFloat = 72 + CGFloat(index) * 30
            pen.text(row.label, at: CGPoint(x: 182, y: y - 7), size: 8, color: SketchPalette.faint, anchor: .leading)
            if let value = row.value {
                pen.text(value, at: CGPoint(x: 182, y: y + 6), size: 10, weight: .semibold, color: ink, anchor: .leading)
            } else {
                pen.stroke(.scribble(from: CGPoint(x: 182, y: y + 6), to: CGPoint(x: 182 + row.width, y: y + 6)),
                           ink, width: 1.6)
            }
            pen.stroke(.line(from: CGPoint(x: 182, y: y + 13), to: CGPoint(x: 280, y: y + 13)), SketchPalette.faint, width: 0.7)
            pen.stroke(.checkmark(in: CGRect(x: 266, y: y - 3, width: 12, height: 11)), .green, width: 2)
        }
    }

    // MARK: Keller: Liste mit Bestand und Minus-Knopf

    private static func cellar(_ pen: inout SketchPen) {
        let ink = SketchPalette.ink

        let card = CGRect(x: 22, y: 28, width: 256, height: 176)
        pen.shape(Path(roundedRect: card, cornerRadius: 14, style: .continuous),
                  fill: SketchPalette.paper, stroke: ink, width: 2)
        pen.text("Wyychällerli", at: CGPoint(x: 36, y: 44), size: 11, weight: .bold, color: ink, anchor: .leading)
        pen.text("10 Flaschen", at: CGPoint(x: 264, y: 44), size: 8.5, color: SketchPalette.faint, anchor: .trailing)
        pen.stroke(.line(from: CGPoint(x: 30, y: 57), to: CGPoint(x: 270, y: 57)), SketchPalette.faint, width: 0.8)

        let rows: [(color: Color, name: CGFloat, subtitle: CGFloat, count: String)] = [
            (SketchPalette.wine, 86, 64, "3"),
            (SketchPalette.straw, 70, 54, "1"),
            (SketchPalette.sparkling, 96, 78, "6")
        ]
        for (index, row) in rows.enumerated() {
            let y: CGFloat = 80 + CGFloat(index) * 42
            pen.bottle(in: CGRect(x: 37, y: y - 15, width: 14, height: 30), color: row.color)
            pen.stroke(.scribble(from: CGPoint(x: 62, y: y - 7), to: CGPoint(x: 62 + row.name, y: y - 7)), ink, width: 2)
            pen.stroke(.scribble(from: CGPoint(x: 62, y: y + 6), to: CGPoint(x: 62 + row.subtitle, y: y + 6)),
                       ink.opacity(0.5), width: 1.2)
            // Bestand
            let badge = CGRect(x: 204, y: y - 9, width: 26, height: 18)
            pen.shape(Path(roundedRect: badge, cornerRadius: 9, style: .continuous),
                      fill: ink.opacity(0.08), stroke: ink, width: 1.2)
            pen.text(row.count, at: CGPoint(x: badge.midX, y: badge.midY), size: 10, weight: .semibold, color: ink)
            // Minus-Knopf
            let button = CGRect(x: 240, y: y - 11, width: 22, height: 22)
            pen.fill(Path(ellipseIn: button), Color.accentColor)
            pen.stroke(.line(from: CGPoint(x: 246, y: y), to: CGPoint(x: 256, y: y)), .white, width: 2.5)
            if index < rows.count - 1 {
                pen.stroke(.line(from: CGPoint(x: 62, y: y + 21), to: CGPoint(x: 270, y: y + 21)), SketchPalette.faint, width: 0.7)
            }
        }
    }

    // MARK: Regal: Raster mit Flaschen, ein Fach hervorgehoben

    private static func rack(_ pen: inout SketchPen) {
        let ink = SketchPalette.ink
        let rows = 4
        let columns = 6
        let tile: CGFloat = 30
        let gap: CGFloat = 6
        let origin = CGPoint(x: 52, y: 46)

        // Rahmen des Regals
        let frame = CGRect(x: origin.x - 6, y: origin.y - 6,
                           width: CGFloat(columns) * tile + CGFloat(columns - 1) * gap + 12,
                           height: CGFloat(rows) * tile + CGFloat(rows - 1) * gap + 12)
        pen.shape(Path(roundedRect: frame, cornerRadius: 8, style: .continuous),
                  fill: SketchPalette.paper, stroke: ink, width: 2.2)

        // Beschriftung: Zeilen als Buchstaben, Spalten als Zahlen
        let letters = ["A", "B", "C", "D"]
        for row in 0..<rows {
            let y = origin.y + tile / 2 + CGFloat(row) * (tile + gap)
            pen.text(letters[row], at: CGPoint(x: 36, y: y), size: 8.5, color: SketchPalette.faint)
        }
        for column in 0..<columns {
            let x = origin.x + tile / 2 + CGFloat(column) * (tile + gap)
            pen.text("\(column + 1)", at: CGPoint(x: x, y: 31), size: 8.5, color: SketchPalette.faint)
        }

        let occupied: [Int: Color] = [
            0: SketchPalette.wine, 1: SketchPalette.wine, 2: SketchPalette.wine, 4: SketchPalette.straw,
            6: SketchPalette.rose, 7: SketchPalette.rose, 11: SketchPalette.sparkling,
            15: SketchPalette.wine,
            18: SketchPalette.wine, 19: SketchPalette.straw, 20: SketchPalette.straw
        ]
        let highlighted = 9 // B4

        for row in 0..<rows {
            for column in 0..<columns {
                let index = row * columns + column
                let cell = CGRect(x: origin.x + CGFloat(column) * (tile + gap),
                                  y: origin.y + CGFloat(row) * (tile + gap),
                                  width: tile, height: tile)
                let path = Path(roundedRect: cell, cornerRadius: 5, style: .continuous)
                if index == highlighted {
                    pen.shape(path, fill: Color.accentColor.opacity(0.22), stroke: Color.accentColor, width: 2.5)
                    pen.stroke(Path(ellipseIn: cell.insetBy(dx: -7, dy: -7)), Color.accentColor.opacity(0.35), width: 1.4)
                } else {
                    pen.shape(path, fill: ink.opacity(0.06), stroke: ink.opacity(0.4), width: 1)
                }
                if let color = occupied[index] {
                    pen.bottle(in: CGRect(x: cell.minX + 10, y: cell.minY + 4, width: 10, height: 22),
                               color: color, outline: false)
                }
            }
        }

        let highlightedCell = CGPoint(
            x: origin.x + CGFloat(highlighted % columns) * (tile + gap) + tile / 2,
            y: frame.maxY + 12
        )
        pen.text("Fach B4 ist frei", at: highlightedCell, size: 9, weight: .semibold, color: Color.accentColor)
    }

    // MARK: Wein-Berater: Gericht eingeben, drei Empfehlungen

    private static func advisor(_ pen: inout SketchPen) {
        let ink = SketchPalette.ink

        // Eingabefeld
        let field = CGRect(x: 30, y: 24, width: 240, height: 34)
        pen.shape(Path(roundedRect: field, cornerRadius: 10, style: .continuous),
                  fill: SketchPalette.paper, stroke: ink, width: 2)
        pen.text("Raclette", at: CGPoint(x: 64, y: 41), size: 12, color: ink, anchor: .leading)
        pen.stroke(.line(from: CGPoint(x: 114, y: 33), to: CGPoint(x: 114, y: 49)), Color.accentColor, width: 1.5)

        // Knopf
        let button = CGRect(x: 92, y: 68, width: 116, height: 26)
        pen.fill(Path(roundedRect: button, cornerRadius: 13, style: .continuous), Color.accentColor)
        pen.text("Empfehlung holen", at: CGPoint(x: 158, y: 81), size: 9, weight: .semibold, color: .white)

        pen.stroke(.arrow(from: CGPoint(x: 150, y: 99), to: CGPoint(x: 150, y: 112), head: 6), ink, width: 1.8)

        let cards: [(fit: String, color: Color, name: CGFloat, subtitle: CGFloat)] = [
            ("Perfekt", Color.green, 80, 50),
            ("Passt gut", Color.accentColor, 66, 44),
            ("Geht", Color.orange, 90, 60)
        ]
        for (index, card) in cards.enumerated() {
            let y: CGFloat = 118 + CGFloat(index) * 33
            let rect = CGRect(x: 30, y: y, width: 240, height: 28)
            pen.shape(Path(roundedRect: rect, cornerRadius: 8, style: .continuous),
                      fill: SketchPalette.paper, stroke: ink, width: 1.6)
            // Rang
            pen.fill(Path(ellipseIn: CGRect(x: 38, y: y + 5, width: 18, height: 18)), Color.accentColor)
            pen.text("\(index + 1)", at: CGPoint(x: 47, y: y + 14), size: 10, weight: .bold, color: .white)
            // Name und Untertitel
            pen.stroke(.scribble(from: CGPoint(x: 64, y: y + 10), to: CGPoint(x: 64 + card.name, y: y + 10)), ink, width: 1.8)
            pen.stroke(.scribble(from: CGPoint(x: 64, y: y + 20), to: CGPoint(x: 64 + card.subtitle, y: y + 20)),
                       ink.opacity(0.5), width: 1)
            // Passung
            let badge = CGRect(x: 198, y: y + 6, width: 64, height: 16)
            pen.shape(Path(roundedRect: badge, cornerRadius: 8, style: .continuous),
                      fill: card.color.opacity(0.18), stroke: card.color, width: 1)
            pen.text(card.fit, at: CGPoint(x: badge.midX, y: badge.midY), size: 8, weight: .semibold, color: card.color)
        }
    }

    // MARK: Teilen und Bewerten: zwei Telefone, eine Wolke, Sterne

    private static func share(_ pen: inout SketchPen) {
        let ink = SketchPalette.ink
        let colors = [SketchPalette.wine, SketchPalette.straw, SketchPalette.rose]

        for (side, x) in [CGFloat(34), CGFloat(188)].enumerated() {
            let phone = CGRect(x: x, y: 62, width: 78, height: 136)
            pen.shape(Path(roundedRect: phone, cornerRadius: 12, style: .continuous),
                      fill: SketchPalette.paper, stroke: ink, width: 2)
            pen.stroke(Path(roundedRect: phone.insetBy(dx: 6, dy: 9), cornerRadius: 6, style: .continuous),
                       SketchPalette.faint, width: 1)
            for (row, color) in colors.enumerated() {
                let y = phone.minY + 26 + CGFloat(row) * 28
                pen.bottle(in: CGRect(x: x + 14, y: y - 9, width: 8, height: 18), color: color, outline: false)
                pen.stroke(.scribble(from: CGPoint(x: x + 28, y: y - 3), to: CGPoint(x: x + 64, y: y - 3), amplitude: 1.2),
                           ink, width: 1.5)
                pen.stroke(.scribble(from: CGPoint(x: x + 28, y: y + 5), to: CGPoint(x: x + 54, y: y + 5), amplitude: 1),
                           ink.opacity(0.5), width: 0.9)
            }
            // Jede Person bewertet für sich: links vier Sterne, rechts fünf.
            let filledStars = side == 0 ? 4 : 5
            for star in 0..<5 {
                pen.star(at: CGPoint(x: x + 17 + CGFloat(star) * 11, y: phone.maxY - 16), radius: 4.5, filled: star < filledStars)
            }
        }

        // Abgleich zwischen den Geräten
        pen.stroke(.arrow(from: CGPoint(x: 118, y: 104), to: CGPoint(x: 182, y: 104), head: 7), ink, width: 1.8)
        pen.stroke(.arrow(from: CGPoint(x: 182, y: 116), to: CGPoint(x: 118, y: 116), head: 7), ink, width: 1.8)

        // Gemeinsames Ergebnis
        for star in 0..<5 {
            pen.star(at: CGPoint(x: 66 + CGFloat(star) * 17, y: 213), radius: 7, filled: star < 4)
        }
        pen.text("4,5", at: CGPoint(x: 150, y: 213), size: 10, weight: .bold, color: ink)
        let badge = CGRect(x: 180, y: 204, width: 86, height: 18)
        pen.shape(Path(roundedRect: badge, cornerRadius: 9, style: .continuous),
                  fill: Color.green.opacity(0.18), stroke: .green, width: 1)
        pen.text("Wieder kaufen", at: CGPoint(x: badge.midX, y: badge.midY), size: 8, weight: .semibold, color: .green)
    }
}

// MARK: - Die Ansicht

/// Eine Skizze auf Papier: `Canvas` für die Zeichnung, SF Symbols als Overlay.
struct SketchIllustrationView: View {

    let page: OnboardingPage

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / Sketches.designSize.width,
                            proxy.size.height / Sketches.designSize.height)
            let offset = CGPoint(
                x: (proxy.size.width - Sketches.designSize.width * scale) / 2,
                y: (proxy.size.height - Sketches.designSize.height * scale) / 2
            )
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    context.translateBy(x: offset.x, y: offset.y)
                    context.scaleBy(x: scale, y: scale)
                    var pen = SketchPen(context, seed: page.seed)
                    Sketches.draw(page, with: &pen)
                }
                ForEach(page.symbols) { symbol in
                    Image(systemName: symbol.name)
                        .font(.system(size: symbol.size * scale, weight: .semibold))
                        .foregroundStyle(symbol.color)
                        .position(x: offset.x + symbol.point.x * scale, y: offset.y + symbol.point.y * scale)
                }
            }
        }
        .aspectRatio(Sketches.designSize.width / Sketches.designSize.height, contentMode: .fit)
        .background(SketchPalette.paper, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(SketchPalette.ink.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        // Die Skizze ist Illustration; Titel und Text der Seite erklären den Inhalt.
        .accessibilityHidden(true)
    }
}

#Preview("Alle Skizzen") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(OnboardingPage.allCases) { page in
                SketchIllustrationView(page: page)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }
    .background(Color(.systemGroupedBackground))
}
