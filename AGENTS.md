# AGENTS.md

Anleitung für KI-Agenten (Claude Code u. a.), die an diesem Projekt arbeiten. Diese Datei wird vom Agenten selbständig erweitert, wenn sich Konventionen oder Abläufe ändern.

## Projekt in einem Satz

SwiftUI-App „Wyychällerli“ (iOS 17+, Core Data mit CloudKit, MVVM) mit Multi-AI-Service für Wein-Empfehlungen über OpenAI, Gemini oder Anthropic. Details in [README.md](README.md).

## Sprache und Stil

- Kommunikation mit dem Nutzer auf **Deutsch** (Schweizer Schreibweise ist willkommen).
- Code-Kommentare und UI-Texte auf Deutsch, Bezeichner (Typen, Variablen, Funktionen) auf Englisch.
- Deutsche Anführungszeichen in UI-Texten: „…“.
- Keine Emojis in Code oder UI.

## Build und Test

Projekt bauen (Simulator, ohne Team):

```bash
xcodebuild build -project Wyychaellerli.xcodeproj -scheme Wyychaellerli -destination 'generic/platform=iOS Simulator' 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"
```

Schneller Typecheck aller Quellen (Swift 5 und Swift 6 strict concurrency müssen beide sauber sein):

```bash
find Wyychaellerli -name '*.swift' -print0 | xargs -0 xcrun -sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios17.0-simulator -swift-version 6 -parse-as-library
```

Wichtig: Der Ordner `Preview Content` enthält ein Leerzeichen – Dateilisten immer mit `-print0 | xargs -0` übergeben.

UI-Änderungen im Simulator verifizieren (Simulator-Tool oder `xcrun simctl`). Für den Simulator-Build **nicht** `CODE_SIGNING_ALLOWED=NO` setzen, sonst fehlt die Keychain-Berechtigung und `SecItemAdd` schlägt mit -34018 fehl. Nach Tests mit Dummy-Keys aufräumen:

```bash
xcrun simctl uninstall <UDID> ch.sondinetwork.wyychaellerli && xcrun simctl keychain <UDID> reset
```

Es gibt noch keine Unit-Tests. Logik ohne UI (Schema, Prompt, Decoding, Fehler-Klassifikation) lässt sich mit einem kleinen macOS-Harness prüfen: `swiftc main.swift Wyychaellerli/Models/*.swift Wyychaellerli/Services/*.swift Wyychaellerli/Services/Providers/*.swift`.

## Projektstruktur und Regeln

- `Wyychaellerli/` ist ein **synchronisierter Ordner** im Xcode-Projekt: neue Dateien einfach im passenden Unterordner ablegen, kein Eintrag in `project.pbxproj` nötig.
- `project.pbxproj` nur bei Build-Settings anfassen (z. B. Entitlements); Xcode formatiert die Datei beim Öffnen um – das ist normal.
- **Namen und Kennungen** (die App hiess bis zur Umbenennung „Weinkeller“):
  - Angezeigter Name: **Wyychällerli**, gesetzt über `INFOPLIST_KEY_CFBundleDisplayName` in beiden Konfigurationen. Umlaute sind hier erlaubt.
  - Bundle-ID: **`ch.sondinetwork.wyychaellerli`**. Umlaute sind hier **nicht** erlaubt; Xcode meldet „invalid character in Bundle Identifier … only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.)“ und der Build läuft trotzdem durch – Signierung und App Store Connect würden ihn später abweisen.
  - **Auf der Platte alles ASCII**: Ordner `Wyychaellerli/`, `Wyychaellerli.xcodeproj`, Target und Scheme `Wyychaellerli`. Nur der angezeigte Name trägt den Umlaut. Das hält Build-Befehle, Pfade und Git frei von Normalisierungs- und Quoting-Fragen.
  - `CFBundleName` folgt `PRODUCT_NAME` und damit dem Target-Namen. Direkt setzen lässt es sich **nicht**: `INFOPLIST_KEY_CFBundleName` wird zwar als Build-Einstellung akzeptiert, aber vom Info.plist-Generator ignoriert, und ein Eintrag in `Config/Info.plist` wird von ihm überschrieben. Für die Anzeige ist ohnehin `CFBundleDisplayName` massgeblich.
  - Der Logger nutzt weiterhin `subsystem == "com.weinkeller.app"`. **So lassen**, sonst stimmen alle dokumentierten Log-Befehle nicht mehr.
- `Wyychaellerli/Wyychaellerli.entitlements` enthält `keychain-access-groups`, iCloud/CloudKit und den Container `iCloud.com.sondinetwork.weinkeller.app`; nicht entfernen. Die Keychain-Gruppe heisst noch `com.weinkeller.app` – **so lassen**: Sie funktioniert (Team-Präfix zählt), und eine Umbenennung würde die gespeicherten API-Keys unauffindbar machen.
- **Der iCloud-Container behält den alten Namen und darf nie geändert werden.** `iCloud.com.sondinetwork.weinkeller.app` hängt nicht an der Bundle-ID. Genau deshalb hat die Umbenennung die Daten nicht gekostet: Die neue App zieht denselben Container und damit den gesamten Keller samt Freigabe wieder herunter. Eine Änderung dieser Zeichenkette wäre gleichbedeutend mit Datenverlust.
- `Config/Info.plist` liegt **bewusst außerhalb** des synchronisierten Ordners (sonst „Multiple commands produce Info.plist“). Xcode führt sie mit den generierten Keys zusammen (`GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = Config/Info.plist`). Dort steht nur, was sich nicht als Build-Setting ausdrücken lässt, z. B. `UILaunchScreen/UIColorName`.
- App-Icon: `swift Tools/MakeAppIcon.swift` rendert die drei Varianten (hell, dunkel, getönt) per CoreGraphics nach `Assets.xcassets/AppIcon.appiconset`. Design-Änderungen im Script machen, nicht in den PNGs. Keine SF Symbols im App-Icon (Lizenz).
- Startbildschirm: System-Launchscreen in `LaunchBackground` (Bordeaux), danach `SplashView` als Overlay in `ContentView` für `SplashView.displayDuration`. `accessibilityReduceMotion` wird respektiert.
- Neue Ansichten bekommen eine `#Preview` mit `PreviewData`.
- **Erscheinungsbild**: `AppearanceSetting` (System / Hell / Dunkel) liegt in `UserDefaults` unter `AppearanceSetting.storageKey` und wird in `WyychaellerliApp` mit `.preferredColorScheme` auf die ganze App gelegt. Bewusst eine Geräte-Einstellung, nicht in iCloud – am iPhone dunkel und am iPad hell soll möglich sein.
- **Feste Farben brauchen eine Dunkelvariante.** Systemfarben (`Color(.systemGroupedBackground)`, `.secondary`, Materialien) passen sich selbst an, `Color(red:green:blue:)` nicht. Die Weintyp-Farben liefen deshalb im Dunkelmodus ins Leere, Bordeaux war praktisch unlesbar. `Color.adaptive(light:dark:)` in `Theme.swift` baut aus zwei Tönen eine mitlaufende Farbe; jede neue feste Farbe gehört dort hinein. Die Akzentfarbe hat ihre Dunkelvariante bereits im Asset-Katalog.
- Schema-Änderungen brauchen Migrationsüberlegungen, da bestehende Installationen Daten haben. Neue Attribute immer mit Standardwert (CloudKit-Pflicht).
- **Weintypen** (`WineType` in `Models/Wine.swift`): `red`, `white`, `sparkling`, `rose`, `mulled` (Glühwein und verwandte Winter-Heißgetränke). Der Rohwert steht als String am `Wine`, ein neuer Fall braucht deshalb keine Migration. Ein neuer Typ ist an fünf Stellen nachzuziehen: `displayName` und `symbolName` (Wine.swift), `color` (Theme.swift), `LabelSchema` (enum-Liste), `PromptBuilder.labelSystemPrompt`, `GeneratedWineLabel` (`@Guide`) und `HeuristicLabelParser.typeKeywords`. Bei den Stichwörtern zählt die **Reihenfolge**: Glühwein steht vor den Farbbegriffen, weil solche Etiketten fast immer zusätzlich „Rotwein“ oder „vin rouge“ nennen.

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
- **Dunkle Etiketten**: `LabelTextRecognizer` erkennt jedes Bild dreimal – `original`, `enhanced` (`CIFilter.documentEnhancer`, amount 1) und `brightened` (`exposureAdjust` EV 1.4 + `colorControls` Kontrast 1.6, Sättigung 0) – und behält das beste Ergebnis. Bewertung: Summe aus Zeichenzahl × Konfidenz je Zeile (`RecognizedLine.confidence`). **Kein vorzeitiger Abbruch** nach dem Originaldurchlauf; genau der hat vorher verhindert, dass die Aufhellung je zum Zug kam. Gemessen an den echten Fotos: stark abgedunkelte Vorderseite 6 Zeilen/94 Zeichen → 8 Zeilen/228 Zeichen, Original 8/171 → 9/244. Kosten: statt ~0,5 s nun ~1–2 s pro Bild.
- **Kamera liefert das volle Bild, nicht den Zuschnitt.** `CameraCaptureView` (`UIImagePickerController`, `allowsEditing = false`). Der frühere `DocumentScannerView` (`VNDocumentCameraViewController`) ist entfernt: Er ist auf Papier ausgelegt, rastet bei einem Etikett auf runder dunkler Flasche regelmäßig auf der Flaschenkontur ein und gibt **nur** sein Ergebnis zurück, nie das Original. Damit war der Fehler nicht mehr zu reparieren, und es musste von Hand nachgeschnitten werden. Gemessen: Auf einem bereits (grob) zugeschnittenen Bild liefert die Segmentierung 93–98 % Fläche, kann also nichts mehr retten. Deshalb nie wieder eine Kamera einbauen, die vorschneidet.
- **Bedienung**: kein globaler Scan-Knopf. Die Felder „Vorderseite“ und „Rückseite“ in `LabelScanView` sind je eine antippbare Fläche, die die Kamera für **diese** Seite öffnet (`LabelScanViewModel.Side`, `scanningSide` als `.fullScreenCover(item:)`, `applyPhoto(_:to:)`). „Aus Fotos“ steht unter jeder Fläche.
- **Etikettenkante**: `LabelImageCropper` (bewusst ohne UIKit, nur CoreImage/Vision – damit am Mac testbar). Reihenfolge:
  1. `VNDetectDocumentSegmentationRequest` (ML, iOS 15+) auf dem **vollen** Foto → Perspektivkorrektur, Wachstum 1,02. Zwei Schranken gegen Fehltreffer: Viereckfläche < 88 % (sonst ist nichts gefunden, sondern das ganze Bild gemeint) und ≥ 70 % der Textzeilen liegen darin (sonst wurde ein Buch oder Tisch erkannt).
  2. Sonst `VNDetectRectanglesRequest` wie bisher, Wachstum 1,06.
  3. Sonst Textumriss + 5 % Rand – **nur** wenn der Umriss < 55 % der Bildfläche deckt. Gemessen: volle Flaschenfotos 9–13 %, bereits zugeschnittene Etiketten 72–88 %. Ohne diese Schranke schneidet die App in ein fertiges Etikett hinein.
  4. Sonst das ganze Bild.
  Kurzzeilen (< 3 Buchstaben) zählen nicht zum Umriss (Kapselaufdruck). Ergebnis: JPEG ≤ 1200 px in `Wine.labelImageData` (`externalStorage`).
- **Drehung wird gemessen, nicht geraten.** `VNRecognizedTextObservation` erbt von `VNRectangleObservation` und liefert das gedrehte Zeilenviereck; `bottomLeft → bottomRight` ist die Leserichtung. Jede Zeile stimmt für eine Vierteldrehung ab, die Mehrheit gewinnt, die Gegenrichtung wird angewendet. Der frühere Weg verglich „Lesbarkeit“ (Zeichen × Konfidenz) von 90° gegen 270° – **das trägt nicht**: gemessen an einem kopfstehenden Ergebnis lagen alle vier Drehungen bei 151/202/166/170 Punkten, die falsche gewann, und die Sprachkorrektur macht aus kopfstehendem Text plausible Wörter (Vokalanteil-Prüfung ergab 96–100 % für *alle* Drehungen). Das neue Verfahren liefert über alle Belichtungen hinweg denselben Wert.
- **Beide Etikettseiten werden gespeichert**: `Wine.labelImageData` (vorne) und `Wine.backLabelImageData` (hinten), beide zugeschnitten. Die Rückseite trägt Terroir, Vinifikation und Speiseempfehlungen – die will man später nachlesen können. Auf der Detailseite blättert `LabelPager` per Wischgeste zwischen den Seiten; bei nur einem Foto verhält er sich wie ein einzelnes Bild (keine Punkte, keine Beschriftung). Die Systempunkte der `TabView` sind auf hellem Grund kaum sichtbar, deshalb eine eigene Anzeige mit Seitenname.
- **Notizen zwingend auf Deutsch**: `LabelNotesTranslator` prüft nach der Zuordnung mit `NLLanguageRecognizer`, ob die Notiz deutsch ist – die Modelle übernehmen den fremdsprachigen Rückseitentext sonst gern wörtlich, trotz Prompt. Schwellen: mindestens 25 Zeichen und 0,65 Sicherheit, sonst wird nichts angefasst (lieber stehen lassen als eine deutsche Notiz „übersetzen“). Übersetzt wird vom Billigsten zum Teuersten: Apples Übersetzung auf dem Gerät (`TranslationSession(installedSource:target:)`, ab iOS 26, kostenlos und offline, **nur** bei bereits installiertem Sprachpaket – nachladen ginge nur über einen Systemdialog aus einer View) → aktiver Cloud-Anbieter (`AIService.translateToGerman`, eine zusätzliche Anfrage) → Original behalten. Gegen zehn Fälle geprüft, darunter drei deutsche Notizen mit französischen Eigennamen, die unangetastet bleiben müssen.
- Alle Zuordnungen liefern `WineLabelExtraction`; Prompts in `PromptBuilder.labelSystemPrompt`, Schema in `LabelSchema`. Bei Feldänderungen alle vier Stellen anpassen: `WineLabelExtraction`, `LabelSchema`, `GeneratedWineLabel` (Foundation Models) und `WineFormViewModel.apply`.
- **Simulator**: Apple Intelligence meldet `.available`, die Generierung scheitert aber mit `ModelManagerError 1026` – im Simulator ist das Modell nicht nutzbar. Der On-Device-Pfad ist nur auf einem echten Gerät (iPhone 15 Pro+, Apple Intelligence aktiviert) testbar. Der iOS-26-Simulator meldet dagegen eine Kamera und öffnet sie auch (simuliertes Bild); zum Prüfen echter Fotos die Fotoauswahl nutzen (`xcrun simctl addmedia <UDID> foto.jpg`).
- Diagnose: `Logger(subsystem: "com.weinkeller.app", category: "LabelScan")`. Im Simulator mitlesen: `xcrun simctl spawn <UDID> log stream --level info --predicate 'subsystem == "com.weinkeller.app"'`.
- Auch `LabelNotesTranslator.swift` lässt sich am Mac prüfen: mit Attrappen für `AIService`/`CloudCredentials` kompilieren und `-target arm64-apple-macos26.0` setzen (sonst fehlt die Verfügbarkeit für `TranslationSession`). `LanguageAvailability().status` zeigt, welche Sprachpakete installiert sind.
- OCR, Zuschnitt und Regel-Parser lassen sich ohne Simulator prüfen: macOS-Harness, der `LabelTextRecognizer.swift` und `LabelImageCropper.swift` direkt mitkompiliert (`xcrun swiftc main.swift <die beiden Dateien> -o run`; die Datei mit Top-Level-Code muss `main.swift` heißen). Fotos via `CGImageSource`, dunkles Kellerlicht via `CIFilter.exposureAdjust` mit EV −1 bis −2. Gutes Maß für die Zuschnittqualität: im Ergebnis erneut Text suchen und den Flächenanteil des Textumrisses messen – eng am Etikett heißt 85–90 %, der alte Zuschnitt kam auf 48 %.
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

## Zwei Apps nebeneinander: DEV und Verteilung

- **Debug und Release haben getrennte Kennungen**, damit die aus Xcode installierte Fassung und die aus TestFlight gleichzeitig auf demselben iPhone liegen können:

  | | Debug | Release |
  |---|---|---|
  | Bundle-ID | `ch.sondinetwork.wyychaellerli.dev` | `ch.sondinetwork.wyychaellerli` |
  | Anzeigename | Wyychällerli DEV | Wyychällerli |
  | Icon | `AppIconDev` (orangenes DEV-Band) | `AppIcon` |

- `Tools/MakeAppIcon.swift` rendert **beide** Sätze in einem Durchlauf; die DEV-Fassung ist dieselbe Zeichnung plus Band. Änderungen am Design nur im Script.
- **Der iCloud-Container bleibt für beide derselbe.** Getrennte Container sind nicht nötig, weil CloudKit ohnehin zwei Umgebungen führt: Aus Xcode installierte Builds sprechen **Development**, TestFlight- und App-Store-Builds sprechen **Production**. Die Daten sind damit von selbst getrennt.
- **In iCloud wandern keine Daten mit**: Der über Xcode erfasste Bestand liegt in **Development**. „Deploy Schema Changes“ überträgt das **Schema**, nicht die Datensätze; Records wechseln nie die Umgebung.
- **Der lokale Speicher überlebt trotzdem, wenn die Bundle-ID gleich bleibt.** Genau das ist beim ersten Umstieg passiert: Bis Commit `cdc5386` trugen Debug *und* Release dieselbe Kennung `ch.sondinetwork.wyychaellerli`. Die aus Xcode installierte App auf dem iPhone hatte damit exakt die Kennung des späteren TestFlight-Builds, iOS hat sie als **Aktualisierung derselben App** behandelt und den Datenbereich samt SQLite-Datei behalten. Der Keller war also sofort da – aus dem **lokalen** Speicher, nicht aus iCloud. Von dort schiebt Core Data die Datensätze anschliessend nach Production hoch.
- **Verlass dich nicht darauf.** Auf einem Gerät, das die App vorher nicht hatte (oder nach einem Löschen), beginnt die TestFlight-Fassung leer, weil Production leer ist. Vor dem Löschen einer App immer erst in der CloudKit-Konsole unter **Records / Production** prüfen, ob die Datensätze oben angekommen sind.
- **Die Freigabe wandert nicht mit.** Ein `CKShare` gehört zu einer Umgebung. Nach dem Umstieg auf TestFlight muss aus der neuen Fassung neu freigegeben und die Einladung neu angenommen werden.
- Die Keychain-Gruppe ist für beide dieselbe, die API-Keys gelten also in beiden Apps.
- Für die `.dev`-Bundle-ID muss im Entwicklerportal eine eigene App-ID bestehen, mit **demselben** iCloud-Container und Push.
- `Config/Info.plist` enthält `ITSAppUsesNonExemptEncryption = false` (nur HTTPS, von der Exportregelung ausgenommen), sonst fragt App Store Connect bei jedem Build nach.
- `Wyychaellerli/PrivacyInfo.xcprivacy` deklariert kein Tracking, keine erhobenen Daten und `UserDefaults` mit Grund `CA92.1`. Landet über den synchronisierten Ordner automatisch im Paket. Die **Datenschutzangaben in App Store Connect** sind davon unabhängig und Sache des Entwicklers – insbesondere die Übermittlung an den KI-Anbieter.

## Freigabe (CloudKit Sharing)

- **Zwei Speicher**: `Weinkeller.sqlite` (Scope `.private`) und `Weinkeller-shared.sqlite` (Scope `.shared`), beide am selben CloudKit-Container. Der Pfad des privaten Speichers darf sich nie ändern, sonst ist der bestehende Keller weg.
- Geteilt wird der **`Cellar`**, nicht einzelne Flaschen. CloudKit teilt Objektbäume, deshalb hängen alle Weine daran.
- `Wine.create` weist die neue Flasche per `context.assign(_:to:)` dem Speicher des Kellers zu. Ohne das landet eine Flasche im geteilten Keller im privaten Speicher und die Partnerin sieht sie nie.
- **Eine Einladung kommt auf zwei Wegen an, beide müssen bedient werden.** Läuft die App beim Tippen auf den Link schon, ruft iOS `windowScene(_:userDidAcceptCloudKitShareWith:)`. Wird die App durch den Link **erst gestartet**, gibt es noch keine Szene: Die Daten liegen dann in `UIScene.ConnectionOptions.cloudKitShareMetadata` und müssen in `scene(_:willConnectTo:options:)` abgeholt werden. Fehlt der zweite Weg, geht die Einladung spurlos verloren – ohne Fehler, ohne Meldung, beim Gast erscheint nur nie ein Keller. Ob es klappte, hing dann allein daran, ob die App zufällig noch im Hintergrund lief; **genau das war die Ursache des wochenlang unklaren Fehlers**. Beide Wege loggen jetzt („Einladung beim Start empfangen“ / „im Betrieb empfangen“). Die App-Delegate-Variante ist seit iOS 26 abgekündigt. Der Delegate hängt über `@UIApplicationDelegateAdaptor` an der App, `Config/Info.plist` braucht `CKSharingSupported`.
- **Eine angelegte, aber nie verschickte Freigabe ist noch keine Freigabe.** `container.share(...)` legt den `CKShare` lokal auch dann an, wenn der Upload scheitert. Die UI darf deshalb nicht auf „Share vorhanden“ prüfen, sondern auf Teilnehmer ohne Eigentümerrolle (`isActuallyShared`), sonst meldet sie „freigegeben, 0 Personen“.
- **Einladung kann vor dem Laden der Speicher eintreffen.** Startet der Link die App, feuert `userDidAcceptCloudKitShareWith`, bevor `loadPersistentStores` fertig ist. `sharedStore` ist dann `nil`. Deshalb legt `acceptShare` die Metadaten in `pendingShareMetadata` und holt sie nach, sobald der Speicher gesetzt wird (`didSet` auf `sharedStore`). Ohne das geht die Einladung still verloren – genau dieser Fehler ist im Test aufgetreten.
- **Titel der Einladung muss zurückgeschrieben werden.** `container.share(...)` legt die Freigabe bereits auf dem Server ab. Ein im Completion-Handler gesetzter `CKShare.SystemFieldKey.title` ist danach nur eine lokale Änderung und erreicht den Server nie – auch `UICloudSharingController` speichert sie nicht, und `itemTitle(for:)` im Delegate füllt nur die eigene Oberfläche. Auf dem Gerät der eingeladenen Person steht dann statt dem App-Namen der interne Name des Freigabe-Datensatzes, bei Core Data `cloudkit.zoneshare`. `PersistenceController.titled(_:)` setzt den Titel deshalb und schreibt ihn mit `persistUpdatedShare` zurück, bevor der Dialog erscheint. Schlägt das fehl, wird nur geloggt und weitergemacht – eine Einladung ohne Titel ist hässlich, aber brauchbar.
- **Ein nicht geladener geteilter Speicher sieht aus wie „nichts wurde geteilt“.** Scheitert `loadPersistentStores` für `Weinkeller-shared.sqlite`, läuft die App einfach ohne diesen Speicher weiter: `sharedStore` bleibt `nil`, `acceptShare` legt die Einladung für immer in die Warteschlange, `Cellar.sharedWithMe` liefert `nil`, und die Einstellungen zeigen dem Gast „Weinkeller teilen“, als wäre er Eigentümer. Genau dieses Bild hat der Nutzer gemeldet. Deshalb nennt die Fehlermeldung jetzt den Dateinamen, die Wanderungsoptionen stehen ausdrücklich in `configure`, und `isSharedStoreAvailable` wird in `CellarSharingSection` als Warnung angezeigt. Beim Prüfen im Log zuerst nachsehen, ob **beide** „Store geladen“-Zeilen erscheinen.
- **CloudKit scheitert sonst lautlos.** `observeCloudKitEvents()` hängt an `NSPersistentCloudKitContainer.eventChangedNotification` und protokolliert Einrichtung, Empfang und Versand samt Fehler unter `subsystem == "com.weinkeller.app"`. Ohne das gibt es bei „beim Gast erscheint nichts“ keinerlei Anhaltspunkt. **Mitlesen auf dem Gerät geht über die Xcode-Konsole** (Gerät per Kabel, App aus Xcode starten) oder die Konsole-App am Mac mit dem iPhone in der Seitenleiste. `log stream --device` gibt es auf aktuellem macOS nicht mehr, das schlägt mit „unrecognized option“ fehl.
- **Keller-Auswahl nie am Singleton festmachen.** `Cellar.sharedStore(for:)` / `privateStore(for:)` leiten den Speicher aus dem Context ab, sonst greifen Previews mit eigenem Stack auf die falsche Ablage zu. Unterschieden wird über den Dateinamen `PersistenceController.sharedStoreFileName`.
- **Kein Keller beim blossen Anzeigen anlegen.** `Cellar.own` und `sharedWithMe` lesen nur; `findOrCreateOwn` legt an und darf nur beim Schreiben aufgerufen werden. Sonst entsteht auf dem Gerät des Gasts ein eigener leerer Keller, und die App hält ihn fälschlich für den Eigentümer.
- `Cellar.active(in:)` liefert den Keller für neue Flaschen: den geteilten, falls vorhanden, sonst den eigenen. Damit landen Flaschen des Gasts im gemeinsamen Keller.
- **Jede Modelländerung ist eine CloudKit-Schemaänderung.** Ein neues Attribut in `makeModel()` wird zu einem neuen Feld am Record-Typ (`backLabelImageData` → `CD_backLabelImageData` an `CD_Wine`). In der **Development**-Umgebung legt `NSPersistentCloudKitContainer` das Feld beim ersten Sync selbst an – dort fällt nichts auf. In der **Production**-Umgebung ist das Schema zur Laufzeit schreibgeschützt: Das Feld muss vorher in der CloudKit-Konsole von Development nach Production übertragen werden („Deploy Schema Changes“). Aus Xcode installierte Builds nutzen Development, **TestFlight und App Store nutzen Production**. Wird das vergessen, scheitert der Abgleich, und beim Gast erscheint nichts – dasselbe Bild wie bei einer verlorenen Einladung. Zweite Falle mit gleichem Symptom: Beide Geräte müssen denselben Build haben. Läuft auf einem ein älterer Build ohne das Feld, kann er die Datensätze nicht übernehmen.
- Im Simulator nicht testbar: ohne iCloud-Konto schlägt `share(...)` mit `CKAccountStatusNoAccount` fehl. Der Fehler wird in `CellarSharingSection.friendlyMessage` in Klartext übersetzt. Echte Tests brauchen zwei Geräte mit verschiedenen Apple-IDs.

## Übernahme aus der früheren SwiftData-Ablage

- `LegacyImporter` liest `Library/Application Support/default.store` **direkt per SQLite**, nicht über SwiftData. SwiftData verlangt ein exakt passendes Modell und versucht sonst zu migrieren; in der App schlägt das mit `SwiftDataError 1` fehl, selbst wenn dasselbe Modell in einem eigenständigen Programm funktioniert.
- Gearbeitet wird auf einer Kopie inklusive `-wal` und `-shm`; das Original wird nie verändert. Läuft genau einmal (`legacyImport.completed` in UserDefaults).
- Formate im Alt-Speicher: `[String]` liegt als `NSKeyedArchiver`-Plist vor, grosse Binärwerte als Verweis auf `.default_SUPPORT/_EXTERNAL_DATA/<UUID>`.
- **Achtung Bundle-ID**: Wurde sie geändert, liegt der alte Speicher im Container der alten App und ist für die neue unerreichbar. Dann findet die Übernahme nichts.

## Speiseempfehlung vom Etikett

- `Wine.foodPairings: [String]` hält die Empfehlungen des Produzenten, immer auf Deutsch. Die KI übersetzt sie beim Scannen (`foodPairings` in `WineLabelExtraction`, `LabelSchema`, `GeneratedWineLabel`); der Prompt verbietet ausdrücklich, aus Rebsorte oder Region etwas abzuleiten. Steht nichts auf dem Etikett, bleibt das Array leer und die UI blendet den Abschnitt aus.
- **Belegpflicht**: Die App behauptet „laut Etikett“, also muss das Etikett es hergeben. Das Modell liefert zusätzlich `foodPairingSource` – den wörtlich aus dem erkannten Text kopierten Abschnitt (unübersetzt). `LabelScanService.verifyingFoodPairings` sucht diesen Beleg im OCR-Text; werden weniger als 60 % seiner Wörter (ab 4 Buchstaben, diakritik- und Groß-/Kleinschreibungs-unempfindlich) gefunden oder sind es weniger als zwei Wörter, fallen `foodPairings` und `foodPairingSource` weg. Die Toleranz ist nötig, weil die Texterkennung Buchstaben verdreht. Das Feld gehört in alle vier Stellen (`WineLabelExtraction`, `LabelSchema`, `GeneratedWineLabel`, `PromptBuilder.labelSystemPrompt`). Gegen sechs Fälle verifiziert, darunter „Beleg erfunden“ und „aus Rebsorte abgeleitet“ → beide verworfen.
- `LabelPairingMatcher` gleicht das eingegebene Gericht lokal gegen diese Begriffe ab: Wortabgleich mit Umlaut-Faltung, Mindestlänge 4, beide Richtungen („Lamm“ in „Lammbraten“, „Fisch“ in „Fisch und Meeresfrüchte“). **Keine Bedeutungsanalyse** – „Lasagne“ trifft „Pasta“ bewusst nicht, dafür ist die KI zuständig. Die Regel ist ohne UI testbar und gegen elf Fälle verifiziert.
- Der lokale Abgleich muss **sichtbar** sein. `PairingViewModel.labelCheckOutcome` unterscheidet `matched`, `noMatch` und `nothingStored`; der Berater zeigt daraus eine Zeile „Zuerst ohne KI gesucht“. Ohne diese Rückmeldung wirkt der Fallback auf die KI wie ein übersprungener Schritt (genau so ist es dem Nutzer im Test aufgefallen).
- Ablauf im Berater: erst der lokale Abgleich. Treffer → Anzeige ohne KI-Anfrage, dazu der Knopf „Zusätzlich die KI fragen“ (`forceAI: true`). Kein Treffer → normale KI-Anfrage. Der Knopf „Empfehlung holen“ ist deshalb **auch ohne API-Key aktiv**; `canRequest` darf keinen Provider verlangen.
- Die Etikett-Empfehlungen gehen als `labelPairings` auch ins Inventar-JSON an die KI, die sie laut Prompt positiv gewichten soll.

## Nachträgliche Übersetzung bestehender Notizen

- Die automatische Übersetzung beim Scannen kam **später** als der Keller. Wer vorher erfasst oder aus der früheren Ablage übernommen hat, trägt fremdsprachige Notizen mit sich – `NotesMigration` (Services) holt das einmalig nach, ausgelöst über `NotesMigrationSection` in den Einstellungen.
- **Ausschliesslich auf dem Gerät** (`LabelNotesTranslator.appleTranslation`, deshalb nicht mehr privat). Kein Rückfall auf die Cloud: Ein einzelner Knopfdruck über den ganzen Keller würde sonst je nach Bestand dutzende kostenpflichtige Anfragen auslösen. Fehlt ein Sprachpaket, bleibt die Notiz **unangetastet** und wird gezählt.
- **Rückfrage vor dem Schreiben.** Der Durchlauf ersetzt vorhandenen Text und lässt sich nicht rückgängig machen, deshalb wird erst gezählt und die Zahl genannt (`confirmationDialog`), bevor irgendetwas geschrieben wird.
- Archivierte Weine sind eingeschlossen (kein Filter auf `isArchived`), leere Notizen werden per Prädikat ausgeschlossen.
- Verifiziert mit einem macOS-Harness gegen den **echten** Core-Data-Stack (`PersistenceController(inMemory: true, useCloudKit: false)`): drei fremdsprachige Notizen (fr, it, es – eine davon archiviert) korrekt übersetzt, deutsche Notiz und leere Notiz unangetastet, Cloud-Attrappe nie aufgerufen. Im Simulator ist **kein** Sprachpaket installiert; dort lässt sich nur der Fehlerpfad prüfen, und der lässt die Notiz erwartungsgemäss stehen.

## Doppelte Flaschen

- `DuplicateFinder` (Services) vergleicht Name, Produzent und Jahrgang. Bewusst ohne UI und mit einem eigenen `Candidate`-Typ, damit sich die Regel am Mac gegen echte Fälle prüfen lässt – gegen zwölf Fälle verifiziert.
- **Die Suche schliesst Archiv und leere Einträge ausdrücklich ein.** Kein Filter auf `isArchived` oder `quantity`. Genau dort liegt der Nutzen: Bei einem archivierten Wein weiss man nicht mehr auswendig, dass man ihn schon hatte.
- Regel: Bei zwei bekannten Jahrgängen müssen diese **gleich** sein, sonst kein Treffer – ein anderer Jahrgang ist ein anderer Wein. Namensähnlichkeit ab 0,85 (ohne Jahrgang strenger, 0,93). Produzent wird nur geprüft, wenn er auf beiden Seiten bekannt ist (Schwelle 0,6), sonst verhinderte ein beim Scannen fehlender Produzent den Treffer.
- Ähnlichkeit über normalisierten Levenshtein-Abstand; normalisiert heisst kleingeschrieben, ohne Akzente, ohne Satz- und Leerzeichen. Gemessene Abstände: „La Pinede“ ↔ „La Pinède“ = 1,00 (trifft), „Chianti Classico“ ↔ „Chianti Classico Riserva“ = 0,68 und „Barolo“ ↔ „Barolo Riserva“ = 0,46 (treffen nicht). Der Abstand zu den Schwellen ist damit komfortabel.
- **Zeitpunkt**: Der Hinweis erscheint sofort beim Tippen und direkt nach dem Scan, ganz oben im Formular – nicht erst beim Sichern. Nach dem Scan kommt die Frage „hatte ich den schon?“ auf, dort muss die Antwort stehen.
- „Bestand erhöhen“ bucht auf den bestehenden Eintrag, holt ihn bei Bedarf aus dem Archiv (`isArchived = false`) und ergänzt **fehlende** Etikettfotos aus dem frischen Scan, ersetzt aber nie vorhandene. „Trotzdem neu anlegen“ setzt `ignoresDuplicates` und blendet den Hinweis für diesen Vorgang aus.
- Nur im Modus `.add`. Beim Bearbeiten wäre der eigene Eintrag der Treffer.

## Bewertungen

- **Eigene Entität `Rating`, nicht Felder am Wein.** In einem geteilten Keller bewerten beide Seiten unabhängig, oft gleichzeitig auf verschiedenen Geräten. Als Felder am Wein würde die zweite Bewertung die erste überschreiben, sobald CloudKit zusammenführt. Eine Bewertung je Person und Wein, nicht je Flasche.
- **Wer bewertet**: `CurrentRater`. Kennung bevorzugt `CKContainer.userRecordID()` – stabil pro Apple-ID und übersteht Neuinstallationen. Ist iCloud nicht erreichbar (kein Konto, Simulator), wird eine lokale Kennung mit Präfix `local-` erzeugt, damit bewertet werden kann; trifft die iCloud-Kennung später ein, schreibt `adoptExistingRatings(in:)` die eigenen Bewertungen um. Ohne das stünde dieselbe Person zweimal in der Liste.
- **Den Namen kann iOS nicht liefern.** `discoverUserIdentity` ist seit iOS 17 abgekündigt, und bei einer Einladung per Link bleibt `nameComponents` der Teilnehmer teilweise leer. Deshalb trägt jede Person ihren Anzeigenamen selbst in den Einstellungen ein; ohne Eintrag steht „Ohne Namen“ plus ein Hinweis auf der Bewertungskarte.
- **Skala**: 0,5 bis 5,0 in halben Schritten (`StarRatingView`). Halbe Schritte, weil der Mittelwert aus zwei Bewertungen sonst grob springt. Feiner wäre vorgetäuschte Genauigkeit. Keine Unterbewertungen für Säure oder Tannin – das wäre ein Fachurteil, das hier niemand abgeben will; stattdessen `RatingTag` in Alltagssprache („Zu sauer“, „Aroma passt nicht“ …).
- **Gemeinsames Ergebnis** ist der schlichte Mittelwert, immer zusammen mit den Einzelbewertungen angezeigt. Bei nur einer Bewertung steht ausdrücklich „vorläufig“ – ein Durchschnitt aus einer Stimme ist kein gemeinsames Urteil.
- `Wine.buyAgain`: ab 4,0 „Wieder kaufen“, ab 3,0 „Kann man wieder“, darunter „Eher nicht wieder“. Feste Regel, bewusst keine KI-Frage.
- Der Berater bekommt `rating` im Inventar-JSON und **gewichtet** es (Regel 5b). Schwach bewertete Flaschen werden nie ausgeschlossen: Passt eine trotzdem am besten zum Gericht, soll sie mit Hinweis empfohlen werden.
- `RatingsOverviewView` (Menü in der Kellerliste) listet bewertete Weine nach Kaufhinweis gruppiert – **einschliesslich archivierter und leerer Flaschen**, denn genau die sind schon getrunken und damit die interessanten für den nächsten Einkauf.
- Gefragt wird beim Austrinken der letzten Flasche (Knopf „Bewerten“ im vorhandenen Dialog) und jederzeit über die Detailseite.

## Trinkreife

- `Wine.drinkFrom` / `drinkTo` (Jahre, 0 = unbekannt) und `drinkWindowFromLabel`. Daraus leiten sich `drinkWindow`, `maturity` (`tooYoung`, `ready`, `drinkSoon`, `pastPeak`, `unknown`) und `needsDrinkingSoon` ab. Regel: kleiner als `from` = zu jung, grösser als `to` = überschritten, gleich `to` = bald trinken, sonst reif.
- **Schätzung als Schätzung kennzeichnen.** Auf dem Etikett steht die Trinkreife selten; das Modell leitet sie meist aus Jahrgang, Rebsorte und Region ab. Die Detailseite schreibt deshalb entweder „laut Etikett“ oder „geschätzt“ – wie beim Speiseempfehlungs-Beleg gilt: Eine Ableitung darf nie wie eine Etikettangabe aussehen. `drinkWindowFromLabel` transportiert das durch alle drei Zuordnungswege.
- In der Liste erscheint nur `drinkSoon` und `pastPeak` als Hinweis. „Trinkreif“ und „zu jung“ stünden bei fast jeder Flasche und wären Rauschen.
- Filter „Nur was dran ist“ liegt im Toolbar-Menü neben dem Archiv, nicht bei den Typ-Chips: Typ und Reife sind zwei verschiedene Achsen, gemischte Chips wären missverständlich. Das Menü-Symbol wechselt, sobald irgendein Filter aktiv ist (`CellarViewModel.isFiltering`).
- Das Fenster geht als `drinkWindow` ins Inventar-JSON. Der Berater soll bei sonst gleicher Eignung die Flasche bevorzugen, die dran ist (Regel 5a im System-Prompt).

## Herkunftskarte

- `Services/RegionGeocoder.swift` löst „Region, Land“ über `CLGeocoder` auf. Kein API-Key, keine Standortfreigabe (Forward Geocoding braucht keine). Ergebnis wird am Wein gespeichert (`latitude`, `longitude`, `geocodedQuery`, `geocodedPlaceName`, `geocodePrecision`).
- **Regionsnamen sind mehrdeutig** – gemessen: „Mosel, Deutschland“ liefert einen Ortsteil von Zwickau in Sachsen, „Wallis, Schweiz“ einen Weiler im Aargau. Deshalb prüft `RegionGeocoder.matches` jeden Treffer gegen `locality` / `subAdministrativeArea` / `administrativeArea`. `name` allein zählt nur bei Treffern ohne `locality` (reine Verwaltungsgebiete wie Piemont). Passt nichts, wird auf Landesebene zurückgefallen: Karte ohne Stecknadel plus Hinweis „Region nicht genau gefunden“. Lieber ungenau als falsch.
- Die Prüfregel ist ohne CoreLocation testbar (`matches(locality:subAdministrativeArea:administrativeArea:name:region:)`) und gegen echte Geocoder-Antworten verifiziert.
- Nicht versuchen, den Treffer mit Zusätzen wie „Weinregion X“ zu verbessern: gemessen liefert das fast immer `kCLErrorDomain error 8` (kein Treffer).
- `.task` niemals an eine potenziell leere `Group` hängen – an einer EmptyView läuft sie nicht. In `WineOriginMapView` sorgt ein `Color.clear`-Zweig dafür, dass immer ein View-Knoten existiert.
- Das Land steht als eigenes Feld am Wein (`Wine.country`), wird vom Etikett mitgelesen (KI und regelbasiert über „Product of France“ und Verwandte) und ist im Formular editierbar.

## Siri / App Intents

- `Intents/WinePairingIntent.swift` ist der Siri-Befehl, `Intents/WyychaellerliShortcuts.swift` meldet ihn beim System an, `Intents/PairingSnippet.swift` ist die Karte unter der Sprachantwort.
- Apple verlangt, dass **jeder** Siri-Satz `\(.applicationName)` enthält. Ein freier Satz wie „Siri, welcher Wein passt zu Lasagne“ ist nicht möglich; das Gericht erfragt Siri über `requestValueDialog` am `@Parameter`.
- **Der Rückgabetyp von `perform()` muss an allen `return`-Stellen identisch sein.** Hilfsfunktionen mit `some IntentResult & ...` erzeugen je eigene opake Typen und brechen den Build. Deshalb sammelt `perform` alles in einer internen `Ausgabe`-Struktur und hat genau eine Rückgabe.
- Siri nutzt `AISpeed.fast`: schnelleres Modell (`AISettings.fastModel(for:)`), bei Anthropic zusätzlich `effort: "low"`, und **kein** zweiter Reparaturversuch. Der Keller-Tab bleibt bei `.quality`.
- App und Intent teilen sich `SharedModelContainer.shared`. Nicht zwei Container anlegen, sonst sieht Siri einen leeren Keller.
- Testen ohne Gerät: App einmal starten (registriert die Intents), dann Kurzbefehle-App im Simulator öffnen, dort erscheint „Wein empfehlen“ unter „Wyychällerli“. Metadaten prüfen: `Metadata.appintents/extract.actionsdata` im gebauten `.app`.
- CarPlay braucht keine eigene Arbeit und ist als eigene App auch nicht erlaubt (die App passt in keine zugelassene CarPlay-Kategorie). Siri im Auto nutzt denselben Intent.

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
