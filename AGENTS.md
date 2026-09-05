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
- Neue Ansichten bekommen eine `#Preview` mit `PreviewData`.
- SwiftData: `Wine` ist das einzige Modell. Schema-Änderungen brauchen Migrationsüberlegungen, da bestehende Installationen Daten haben.

## KI-Layer

- Alle Anbieter liefern per Structured Output dasselbe `PairingResponse`-JSON. Schema in `RecommendationSchema` – OpenAI/Anthropic mit `additionalProperties: false`, Gemini ohne (wird abgelehnt).
- Anthropic: Messages API mit `output_config.format`, `stop_reason == "refusal"` prüfen. Beta-Header `server-side-fallback-2026-07-01` + `fallbacks: "default"` sind aktiv.
- Neue Fehlerfälle in `HTTPTransport.classify` ergänzen und mit realen Fehler-Bodies aller drei Anbieter prüfen; `AIServiceError` braucht `title` und `suggestsSettings`.
- Aktiver Anbieter = der mit Key (`AISettings.activeProvider`). Kein Provider-Picker im Wein-Berater; dort nur Statusanzeige.

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
