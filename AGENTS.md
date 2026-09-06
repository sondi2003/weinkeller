# AGENTS.md

Anleitung für KI-Agenten (Claude Code u. a.), die an diesem Projekt arbeiten. Diese Datei wird vom Agenten selbständig erweitert, wenn sich Konventionen oder Abläufe ändern.

## Projekt in einem Satz

SwiftUI-App „Weinkeller“ (iOS 17+, SwiftData, MVVM) mit Multi-AI-Service für Wein-Empfehlungen über OpenAI, Gemini oder Anthropic. Details in [README.md](README.md).

## Sprache und Stil

- Kommunikation mit dem Nutzer auf **Deutsch** (Schweizer Schreibweise ist willkommen).
- Code-Kommentare und UI-Texte auf Deutsch, Bezeichner (Typen, Variablen, Funktionen) auf Englisch.
- Deutsche Anführungszeichen in UI-Texten: „…“.
- Keine Emojis in Code oder UI.

## Build und Test

Projekt bauen (Simulator, ohne Team):

```bash
xcodebuild build -project Weinkeller.xcodeproj -scheme Weinkeller -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"
```

Schneller Typecheck aller Quellen (Swift 5 und Swift 6 strict concurrency müssen beide sauber sein):

```bash
find Weinkeller -name '*.swift' -print0 | xargs -0 xcrun -sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios17.0-simulator -swift-version 6 -parse-as-library
```

Wichtig: Der Ordner `Preview Content` enthält ein Leerzeichen – Dateilisten immer mit `-print0 | xargs -0` übergeben.

UI-Änderungen im Simulator verifizieren (Simulator-Tool oder `xcrun simctl`). Für den Simulator-Build **nicht** `CODE_SIGNING_ALLOWED=NO` setzen, sonst fehlt die Keychain-Berechtigung und `SecItemAdd` schlägt mit -34018 fehl. Nach Tests mit Dummy-Keys aufräumen:

```bash
xcrun simctl uninstall <UDID> com.weinkeller.app && xcrun simctl keychain <UDID> reset
```

Es gibt noch keine Unit-Tests. Logik ohne UI (Schema, Prompt, Decoding, Fehler-Klassifikation) lässt sich mit einem kleinen macOS-Harness prüfen: `swiftc main.swift Weinkeller/Models/*.swift Weinkeller/Services/*.swift Weinkeller/Services/Providers/*.swift`.

## Projektstruktur und Regeln

- `Weinkeller/` ist ein **synchronisierter Ordner** im Xcode-Projekt: neue Dateien einfach im passenden Unterordner ablegen, kein Eintrag in `project.pbxproj` nötig.
- `project.pbxproj` nur bei Build-Settings anfassen (z. B. Entitlements); Xcode formatiert die Datei beim Öffnen um – das ist normal.
- `Weinkeller/Weinkeller.entitlements` enthält `keychain-access-groups`; nicht entfernen.
- `Config/Info.plist` liegt **bewusst außerhalb** des synchronisierten Ordners (sonst „Multiple commands produce Info.plist“). Xcode führt sie mit den generierten Keys zusammen (`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Config/Info.plist`). Dort steht nur, was sich nicht als Build-Setting ausdrücken lässt, z. B. `UILaunchScreen/UIColorName`.
- App-Icon: `swift Tools/MakeAppIcon.swift` rendert die drei Varianten (hell, dunkel, getönt) per CoreGraphics nach `Assets.xcassets/AppIcon.appiconset`. Design-Änderungen im Script machen, nicht in den PNGs. Keine SF Symbols im App-Icon (Lizenz).
- Startbildschirm: System-Launchscreen in `LaunchBackground` (Bordeaux), danach `SplashView` als Overlay in `ContentView` für `SplashView.displayDuration`. `accessibilityReduceMotion` wird respektiert.
- Neue Ansichten bekommen eine `#Preview` mit `PreviewData`.
- SwiftData: `Wine` ist das einzige Modell. Schema-Änderungen brauchen Migrationsüberlegungen, da bestehende Installationen Daten haben.

## KI-Layer

- Alle Anbieter liefern per Structured Output dasselbe `PairingResponse`-JSON. Schema in `RecommendationSchema` – OpenAI/Anthropic mit `additionalProperties: false`, Gemini ohne (wird abgelehnt).
- Anthropic: Messages API mit `output_config.format`, `stop_reason == "refusal"` prüfen. Beta-Header `server-side-fallback-2026-07-01` + `fallbacks: "default"` sind aktiv.
- Neue Fehlerfälle in `HTTPTransport.classify` ergänzen und mit realen Fehler-Bodies aller drei Anbieter prüfen; `AIServiceError` braucht `title` und `suggestsSettings`.
- Aktiver Anbieter = der mit Key (`AISettings.activeProvider`). Kein Provider-Picker im Wein-Berater; dort nur Statusanzeige.
- **Empfehlungen werden validiert** (`PairingValidator` in `AIService.swift`): unbekannte Weine (kein Match im Inventar), Platzhalter („placeholder“, leere Texte) und doppelte Einträge fliegen raus, Ränge werden neu vergeben. Ist nichts Brauchbares übrig, obwohl das Modell Empfehlungen geliefert hat, folgt genau ein zweiter Versuch mit `PromptBuilder.repairHint`; danach `AIServiceError.unusableResponse`. Rohantworten unbrauchbarer Versuche landen im Log (Subsystem `com.weinkeller.app`, Kategorie `AIService`).
- **Sommelier-Verhalten**: jede Empfehlung trägt `fit` (excellent/good/acceptable/poor, UI: Perfekt/Passt gut/Geht/Notlösung). `recommendations` darf leer sein, `noGoodMatch` markiert ehrliche Absagen oder Notlösungen, `shoppingTip` nennt immer das klassische Pairing als Kauftipp. Die UI zeigt bei `noGoodMatch` eine Warn-Callout plus Kauftipp, bei leeren Empfehlungen die Karte „Keine passende Flasche im Keller“.
- **Anthropic `max_tokens`**: adaptives Thinking zählt zum Budget. Mit 8192 kam es zu Minimal-JSON („placeholder“, "x", 0), weil das Modell am Limit nur noch das Schema befüllt. Deshalb 16000 + `output_config.effort: "medium"`; `stop_reason == "max_tokens"` wirft `.truncated`. Analog OpenAI `finish_reason == "length"` und Gemini `MAX_TOKENS`.

## Etikett-Scan

- Ablauf in `Services/LabelScanner/`: `LabelTextRecognizer` (Vision-OCR, auf dem Gerät) → `LabelScanService.structure` wählt die Zuordnung: `OnDeviceLabelParser` (Foundation Models, iOS 26 + Apple Intelligence) → aktiver Cloud-Anbieter (`AIService.extractLabel`, nur Text) → `HeuristicLabelParser` (Regeln). Lücken werden mit den Regel-Treffern aufgefüllt (`merge`).
- Kamera: `DocumentScannerView` (VisionKit `VNDocumentCameraViewController`) erkennt das Etikett live, schneidet zu und begradigt; Seite 1 = Vorderseite, Seite 2 = Rückseite. Solche Bilder kommen mit `ScanImage.isPreCropped = true` an, der Cropper überspringt dann Rechteck-/Textzuschnitt. Nicht im Simulator verfügbar (`isSupported`), dort nur Fotoauswahl.
- Etikett-Foto: `LabelImageCropper` (bewusst ohne UIKit, nur CoreImage/Vision – damit am Mac testbar) schneidet die Vorderseite zu: Perspektivkorrektur nur, wenn das erkannte Rechteck den gesamten Text enthält, sonst gerader Zuschnitt aus Rechteck ∪ Textumriss + 5 % Rand. Kurzzeilen (< 3 Buchstaben) zählen nicht zum Umriss (Kapselaufdruck). Drehung: nur 90°/270°, entschieden über die Geometrie der Textzeilen (hochkant = gedreht), Richtung per Lesbarkeit. 180° wird nie geprüft (kopfstehender Text liefert Schein-Treffer). Ergebnis: JPEG ≤ 1200 px in `Wine.labelImageData` (`externalStorage`).
- Alle Zuordnungen liefern `WineLabelExtraction`; Prompts in `PromptBuilder.labelSystemPrompt`, Schema in `LabelSchema`. Bei Feldänderungen alle vier Stellen anpassen: `WineLabelExtraction`, `LabelSchema`, `GeneratedWineLabel` (Foundation Models) und `WineFormViewModel.apply`.
- **Simulator**: Apple Intelligence meldet `.available`, die Generierung scheitert aber mit `ModelManagerError 1026` – im Simulator ist das Modell nicht nutzbar. Der On-Device-Pfad ist nur auf einem echten Gerät (iPhone 15 Pro+, Apple Intelligence aktiviert) testbar. Kamera ebenfalls nur auf dem Gerät; im Simulator die Fotoauswahl nutzen (`xcrun simctl addmedia <UDID> foto.jpg`).
- Diagnose: `Logger(subsystem: "com.weinkeller.app", category: "LabelScan")`. Im Simulator mitlesen: `xcrun simctl spawn <UDID> log stream --level info --predicate 'subsystem == "com.weinkeller.app"'`.
- OCR und Regel-Parser lassen sich ohne Simulator prüfen: macOS-Harness mit `LabelTextRecognizer` + `HeuristicLabelParser` und Fotos via `CGImageSource` (siehe Tools-Abschnitt oben).
- `Config/Info.plist`: Xcode überschreibt die Datei gelegentlich mit seiner In-Memory-Kopie, wenn das Projekt offen ist. Nach Änderungen prüfen, ob `NSCameraUsageDescription` noch drin ist.

## Herkunftskarte

- `Services/RegionGeocoder.swift` löst „Region, Land“ über `CLGeocoder` auf. Kein API-Key, keine Standortfreigabe (Forward Geocoding braucht keine). Ergebnis wird am Wein gespeichert (`latitude`, `longitude`, `geocodedQuery`, `geocodedPlaceName`, `geocodePrecision`).
- **Regionsnamen sind mehrdeutig** – gemessen: „Mosel, Deutschland“ liefert einen Ortsteil von Zwickau in Sachsen, „Wallis, Schweiz“ einen Weiler im Aargau. Deshalb prüft `RegionGeocoder.matches` jeden Treffer gegen `locality` / `subAdministrativeArea` / `administrativeArea`. `name` allein zählt nur bei Treffern ohne `locality` (reine Verwaltungsgebiete wie Piemont). Passt nichts, wird auf Landesebene zurückgefallen: Karte ohne Stecknadel plus Hinweis „Region nicht genau gefunden“. Lieber ungenau als falsch.
- Die Prüfregel ist ohne CoreLocation testbar (`matches(locality:subAdministrativeArea:administrativeArea:name:region:)`) und gegen echte Geocoder-Antworten verifiziert.
- Nicht versuchen, den Treffer mit Zusätzen wie „Weinregion X“ zu verbessern: gemessen liefert das fast immer `kCLErrorDomain error 8` (kein Treffer).
- `.task` niemals an eine potenziell leere `Group` hängen – an einer EmptyView läuft sie nicht. In `WineOriginMapView` sorgt ein `Color.clear`-Zweig dafür, dass immer ein View-Knoten existiert.
- Das Land steht als eigenes Feld am Wein (`Wine.country`), wird vom Etikett mitgelesen (KI und regelbasiert über „Product of France“ und Verwandte) und ist im Formular editierbar.

## Siri / App Intents

- `Intents/WinePairingIntent.swift` ist der Siri-Befehl, `Intents/WeinkellerShortcuts.swift` meldet ihn beim System an, `Intents/PairingSnippet.swift` ist die Karte unter der Sprachantwort.
- Apple verlangt, dass **jeder** Siri-Satz `\(.applicationName)` enthält. Ein freier Satz wie „Siri, welcher Wein passt zu Lasagne“ ist nicht möglich; das Gericht erfragt Siri über `requestValueDialog` am `@Parameter`.
- **Der Rückgabetyp von `perform()` muss an allen `return`-Stellen identisch sein.** Hilfsfunktionen mit `some IntentResult & ...` erzeugen je eigene opake Typen und brechen den Build. Deshalb sammelt `perform` alles in einer internen `Ausgabe`-Struktur und hat genau eine Rückgabe.
- Siri nutzt `AISpeed.fast`: schnelleres Modell (`AISettings.fastModel(for:)`), bei Anthropic zusätzlich `effort: "low"`, und **kein** zweiter Reparaturversuch. Der Keller-Tab bleibt bei `.quality`.
- App und Intent teilen sich `SharedModelContainer.shared`. Nicht zwei Container anlegen, sonst sieht Siri einen leeren Keller.
- Testen ohne Gerät: App einmal starten (registriert die Intents), dann Kurzbefehle-App im Simulator öffnen, dort erscheint „Wein empfehlen“ unter „Weinkeller“. Metadaten prüfen: `Metadata.appintents/extract.actionsdata` im gebauten `.app`.
- CarPlay braucht keine eigene Arbeit und ist als eigene App auch nicht erlaubt (Weinkeller passt in keine zugelassene CarPlay-Kategorie). Siri im Auto nutzt denselben Intent.

## Bekannte Stolperfallen

- `Text("\(intValue)")` lokalisiert Zahlen (Jahrgang wird zu „2'024“). Für Jahrgänge `String(vintage)` verwenden.
- In Toolbars werden `Label`s auf das Icon reduziert; für Text + Icon eine `HStack` bauen.
- `ContentUnavailableView.search` nur anzeigen, wenn wirklich gesucht wird.

## Git-Workflow

Der Nutzer testet Änderungen selbst. Am Ende jeder Antwort mit Dateiänderungen einen fertigen Befehl liefern, den er per Klick ausführen kann:

```bash
git add . && git commit -m "Kurze deutsche Beschreibung" && git push
```

Nicht selbst committen oder pushen, sofern nicht ausdrücklich gewünscht.

## Pflege dieser Datei

Wenn sich Konventionen, Build-Schritte oder Stolperfallen ändern, diese Datei im selben Änderungsschritt aktualisieren.
