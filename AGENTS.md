# AGENTS.md

Anleitung für KI-Agenten (Claude Code u. a.), die an diesem Projekt arbeiten. Diese Datei wird vom Agenten selbständig erweitert, wenn sich Konventionen oder Abläufe ändern.

## Projekt in einem Satz

SwiftUI-App „Weinkeller“ (iOS 17+, Core Data mit CloudKit, MVVM) mit Multi-AI-Service für Wein-Empfehlungen über OpenAI, Gemini oder Anthropic. Details in [README.md](README.md).

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
xcrun simctl uninstall <UDID> com.sondinetwork.weinkeller.app && xcrun simctl keychain <UDID> reset
```

Es gibt noch keine Unit-Tests. Logik ohne UI (Schema, Prompt, Decoding, Fehler-Klassifikation) lässt sich mit einem kleinen macOS-Harness prüfen: `swiftc main.swift Weinkeller/Models/*.swift Weinkeller/Services/*.swift Weinkeller/Services/Providers/*.swift`.

## Projektstruktur und Regeln

- `Weinkeller/` ist ein **synchronisierter Ordner** im Xcode-Projekt: neue Dateien einfach im passenden Unterordner ablegen, kein Eintrag in `project.pbxproj` nötig.
- `project.pbxproj` nur bei Build-Settings anfassen (z. B. Entitlements); Xcode formatiert die Datei beim Öffnen um – das ist normal.
- `Weinkeller/Weinkeller.entitlements` enthält `keychain-access-groups`, iCloud/CloudKit und den Container `iCloud.com.sondinetwork.weinkeller.app`; nicht entfernen. Die Keychain-Gruppe heisst noch `com.weinkeller.app` – **so lassen**: Sie funktioniert (Team-Präfix zählt), und eine Umbenennung würde die gespeicherten API-Keys unauffindbar machen.
- `Config/Info.plist` liegt **bewusst außerhalb** des synchronisierten Ordners (sonst „Multiple commands produce Info.plist“). Xcode führt sie mit den generierten Keys zusammen (`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Config/Info.plist`). Dort steht nur, was sich nicht als Build-Setting ausdrücken lässt, z. B. `UILaunchScreen/UIColorName`.
- App-Icon: `swift Tools/MakeAppIcon.swift` rendert die drei Varianten (hell, dunkel, getönt) per CoreGraphics nach `Assets.xcassets/AppIcon.appiconset`. Design-Änderungen im Script machen, nicht in den PNGs. Keine SF Symbols im App-Icon (Lizenz).
- Startbildschirm: System-Launchscreen in `LaunchBackground` (Bordeaux), danach `SplashView` als Overlay in `ContentView` für `SplashView.displayDuration`. `accessibilityReduceMotion` wird respektiert.
- Neue Ansichten bekommen eine `#Preview` mit `PreviewData`.
- Schema-Änderungen brauchen Migrationsüberlegungen, da bestehende Installationen Daten haben. Neue Attribute immer mit Standardwert (CloudKit-Pflicht).

## KI-Layer

- Alle Anbieter liefern per Structured Output dasselbe `PairingResponse`-JSON. Schema in `RecommendationSchema` – OpenAI/Anthropic mit `additionalProperties: false`, Gemini ohne (wird abgelehnt).
- Anthropic: Messages API mit `output_config.format`, `stop_reason == "refusal"` prüfen. Beta-Header `server-side-fallback-2026-07-01` + `fallbacks: "default"` sind aktiv.
- Neue Fehlerfälle in `HTTPTransport.classify` ergänzen und mit realen Fehler-Bodies aller drei Anbieter prüfen; `AIServiceError` braucht `title` und `suggestsSettings`.
- **Modelle** (Stand der Anthropic-Übersicht): Standard für Berater und Etikett-Auswertung ist `claude-sonnet-5`, für Siri ebenfalls `claude-sonnet-5` mit `effort: low`. `claude-opus-5` bleibt über das Modellfeld wählbar. Haiku kennt kein `effort` – der Anthropic-Client lässt das Feld für Modellnamen mit „haiku“ weg. Die Vorgaben für OpenAI und Gemini sind ungeprüft und vom Nutzer zu bestätigen.
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

## Datenschicht: Core Data mit CloudKit

- **Kein SwiftData mehr.** SwiftData kennt für CloudKit nur `private` (im SDK geprüft: `CloudKitDatabase` hat genau `automatic`, `none`, `private`) und keinerlei Freigabe. Für „Zugriff für die Partnerin mit eigener Apple-ID“ braucht es `NSPersistentCloudKitContainer`.
- Das Modell steht **programmatisch** in `PersistenceController.makeModel()`, nicht in einer `.xcdatamodeld`. Grund: zuverlässig mit dem synchronisierten Projektordner, alles an einer Stelle.
- **CloudKit-Regeln, die das Modell einhalten muss**: jedes Attribut optional oder mit Standardwert, alle Beziehungen optional, keine Eindeutigkeits-Bedingungen. Neue Felder immer mit Standardwert anlegen.
- Entitäten: `Cellar` (Wurzel für die spätere Freigabe, alle Flaschen hängen daran) und `Wine`. CloudKit teilt Objektbäume, deshalb braucht es das Dach.
- **Laufzeitnamen weichen bewusst ab**: `@objc(WineEntity)` / `@objc(CellarEntity)`. Heisst die Klasse zur Laufzeit „Wine“, greift die Alt-Datenübernahme auf die falsche Klasse zu.
- Core Data speichert nicht automatisch. Nach jeder Änderung `context.saveChanges()` aufrufen (Erweiterung in `PersistenceController.swift`). `Wine.consumeBottle()`, `addBottle()` und `applyGeocode` speichern selbst.
- Ints sind `Int64`. Beim Übergeben an UI-Bausteine mit `Int(...)` wandeln.
- Views nutzen `@FetchRequest` und `@ObservedObject var wine: Wine` (nicht `@Bindable`, das ist für `@Observable`).

## Freigabe (CloudKit Sharing)

- **Zwei Speicher**: `Weinkeller.sqlite` (Scope `.private`) und `Weinkeller-shared.sqlite` (Scope `.shared`), beide am selben CloudKit-Container. Der Pfad des privaten Speichers darf sich nie ändern, sonst ist der bestehende Keller weg.
- Geteilt wird der **`Cellar`**, nicht einzelne Flaschen. CloudKit teilt Objektbäume, deshalb hängen alle Weine daran.
- `Wine.create` weist die neue Flasche per `context.assign(_:to:)` dem Speicher des Kellers zu. Ohne das landet eine Flasche im geteilten Keller im privaten Speicher und die Partnerin sieht sie nie.
- Einladungen annehmen läuft über `SceneDelegate.windowScene(_:userDidAcceptCloudKitShareWith:)`. Die App-Delegate-Variante ist seit iOS 26 abgekündigt. Der Delegate hängt über `@UIApplicationDelegateAdaptor` an der App, `Config/Info.plist` braucht `CKSharingSupported`.
- **Eine angelegte, aber nie verschickte Freigabe ist noch keine Freigabe.** `container.share(...)` legt den `CKShare` lokal auch dann an, wenn der Upload scheitert. Die UI darf deshalb nicht auf „Share vorhanden“ prüfen, sondern auf Teilnehmer ohne Eigentümerrolle (`isActuallyShared`), sonst meldet sie „freigegeben, 0 Personen“.
- Im Simulator nicht testbar: ohne iCloud-Konto schlägt `share(...)` mit `CKAccountStatusNoAccount` fehl. Der Fehler wird in `CellarSharingSection.friendlyMessage` in Klartext übersetzt. Echte Tests brauchen zwei Geräte mit verschiedenen Apple-IDs.

## Übernahme aus der früheren SwiftData-Ablage

- `LegacyImporter` liest `Library/Application Support/default.store` **direkt per SQLite**, nicht über SwiftData. SwiftData verlangt ein exakt passendes Modell und versucht sonst zu migrieren; in der App schlägt das mit `SwiftDataError 1` fehl, selbst wenn dasselbe Modell in einem eigenständigen Programm funktioniert.
- Gearbeitet wird auf einer Kopie inklusive `-wal` und `-shm`; das Original wird nie verändert. Läuft genau einmal (`legacyImport.completed` in UserDefaults).
- Formate im Alt-Speicher: `[String]` liegt als `NSKeyedArchiver`-Plist vor, grosse Binärwerte als Verweis auf `.default_SUPPORT/_EXTERNAL_DATA/<UUID>`.
- **Achtung Bundle-ID**: Wurde sie geändert, liegt der alte Speicher im Container der alten App und ist für die neue unerreichbar. Dann findet die Übernahme nichts.

## Speiseempfehlung vom Etikett

- `Wine.foodPairings: [String]` hält die Empfehlungen des Produzenten, immer auf Deutsch. Die KI übersetzt sie beim Scannen (`foodPairings` in `WineLabelExtraction`, `LabelSchema`, `GeneratedWineLabel`); der Prompt verbietet ausdrücklich, aus Rebsorte oder Region etwas abzuleiten. Steht nichts auf dem Etikett, bleibt das Array leer und die UI blendet den Abschnitt aus.
- `LabelPairingMatcher` gleicht das eingegebene Gericht lokal gegen diese Begriffe ab: Wortabgleich mit Umlaut-Faltung, Mindestlänge 4, beide Richtungen („Lamm“ in „Lammbraten“, „Fisch“ in „Fisch und Meeresfrüchte“). **Keine Bedeutungsanalyse** – „Lasagne“ trifft „Pasta“ bewusst nicht, dafür ist die KI zuständig. Die Regel ist ohne UI testbar und gegen elf Fälle verifiziert.
- Der lokale Abgleich muss **sichtbar** sein. `PairingViewModel.labelCheckOutcome` unterscheidet `matched`, `noMatch` und `nothingStored`; der Berater zeigt daraus eine Zeile „Zuerst ohne KI gesucht“. Ohne diese Rückmeldung wirkt der Fallback auf die KI wie ein übersprungener Schritt (genau so ist es dem Nutzer im Test aufgefallen).
- Ablauf im Berater: erst der lokale Abgleich. Treffer → Anzeige ohne KI-Anfrage, dazu der Knopf „Zusätzlich die KI fragen“ (`forceAI: true`). Kein Treffer → normale KI-Anfrage. Der Knopf „Empfehlung holen“ ist deshalb **auch ohne API-Key aktiv**; `canRequest` darf keinen Provider verlangen.
- Die Etikett-Empfehlungen gehen als `labelPairings` auch ins Inventar-JSON an die KI, die sie laut Prompt positiv gewichten soll.

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
