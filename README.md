# Weinkeller

Privater Weinkeller-Assistent für iPhone und iPad. Verwaltet den Flaschenbestand und schlägt zum geplanten Essen die passenden Weine aus dem eigenen Keller vor – wahlweise über ChatGPT (OpenAI), Gemini (Google) oder Claude (Anthropic).

## Funktionen

- **Weinkeller** – Flaschen mit Name, Jahrgang, Rebsorte/Region, Typ (Rot, Weiß, Schaum, Rosé) und Bestand. Schnell-Abbuchung per Minus-Button, Filter nach Typ, Suche, Archiv. Bei der letzten Flasche fragt die App, ob der Wein archiviert oder gelöscht werden soll.
- **Herkunftskarte** – Die Detailseite zeigt einen Kartenausschnitt mit Stecknadel auf der Weinregion, ermittelt aus Region und Land des Etiketts. Ist die Region nicht eindeutig auffindbar, zeigt die Karte nur das Land statt einer falschen Nadel. Ein Tipp öffnet Apple Karten.
- **Wein-Berater** – Essens-Stichwort eingeben (z. B. „Raclette“), die KI liefert bis zu drei Empfehlungen aus dem aktuellen Bestand mit ehrlicher Passung (Perfekt, passt gut, geht, Notlösung), Begründung und Serviertipp. Passt nichts wirklich, sagt sie das offen und nennt, was klassisch passen würde, als Kauftipp. „Flasche öffnen“ bucht direkt ab. Antworten werden auf Plausibilität geprüft (nur Weine aus dem Keller, keine Platzhalter) und bei Bedarf einmal automatisch wiederholt.
- **Etikett scannen** – Die Kamera erkennt das Etikett live, löst automatisch aus, schneidet zu und begradigt (Apples Dokumentenscanner). Alternativ Fotos aus der Mediathek wählen. Die App liest den Text auf dem Gerät aus (Vision) und füllt Name, Produzent, Jahrgang, Rebsorten, Region, Typ und Notizen vor. Die Zuordnung macht Apple Intelligence auf dem Gerät (iOS 26, iPhone 15 Pro und neuer), sonst der aktive KI-Anbieter (es wird nur der erkannte Text gesendet, nie das Foto), sonst eine regelbasierte Erkennung. Das Vorderseiten-Foto wird automatisch aufs Etikett zugeschnitten und beim Wein gespeichert – sichtbar auf der Detailseite, in der Liste und in den Empfehlungen, damit die Flasche im Regal schnell gefunden ist.
- **Siri** – „Hey Siri, Wein-Berater in Weinkeller“. Siri fragt nach dem Essen, liest die Empfehlung vor und zeigt eine Karte mit Etikett. Funktioniert auch über CarPlay und in der Kurzbefehle-App. Für Siri wird ein schnelleres Modell verwendet, da Siri nicht lange wartet.
- **Einstellungen** – API-Key und Modellname pro Anbieter, dazu ein eigenes Modell für Siri. Keys lassen sich jederzeit wieder entfernen. Der Anbieter mit hinterlegtem Key ist automatisch aktiv; bei mehreren Keys lässt sich ein bevorzugter wählen. Keys liegen in der Keychain, nie in UserDefaults.

## Voraussetzungen

- Xcode 16 oder neuer (Projekt nutzt synchronisierte Ordner)
- iOS 17 oder neuer
- Ein API-Key bei mindestens einem Anbieter:
  - OpenAI: <https://platform.openai.com/api-keys>
  - Google AI Studio: <https://aistudio.google.com/app/apikey>
  - Anthropic: <https://console.anthropic.com>

## Starten

```bash
open Weinkeller.xcodeproj
```

Im Simulator läuft die App ohne Signierung. Für ein echtes Gerät unter „Signing & Capabilities“ das eigene Team wählen.

Build von der Kommandozeile:

```bash
xcodebuild build -project Weinkeller.xcodeproj -scheme Weinkeller -destination 'generic/platform=iOS Simulator'
```

## Architektur

MVVM mit SwiftUI, SwiftData und `@Observable`.

```
Weinkeller/
├── App/            WeinkellerApp und SharedModelContainer (von App und Siri genutzt)
├── Intents/        Siri-Befehl, Kurzbefehl-Anmeldung, Ergebniskarte
├── Models/         Wine (SwiftData), PairingRequest/PairingResponse, JSON-Schema
├── Services/
│   ├── AIService       Fassade: wählt den Client zum aktiven Anbieter
│   ├── AISettings      Keys (Keychain), Modelle, aktiver Anbieter
│   ├── HTTPTransport   URLSession-Layer, Fehler-Klassifikation
│   ├── PromptBuilder   System- und User-Prompt
│   ├── KeychainStore   Generic-Password-Wrapper
│   ├── LabelScanner/   Vision-OCR, Apple-Intelligence-, Cloud- und Regel-Zuordnung
│   └── Providers/      OpenAIClient, GeminiClient, AnthropicClient
├── ViewModels/     CellarViewModel, WineFormViewModel, PairingViewModel
├── Views/          Cellar, Advisor, Settings, Components, SplashView
└── Preview Content/ In-Memory-Beispieldaten für Xcode-Previews
Config/Info.plist   Launchscreen-Farbe (wird mit generierter Info.plist zusammengeführt)
Tools/MakeAppIcon.swift  Rendert das App-Icon (hell/dunkel/getönt) in die Assets
```

App-Icon neu erzeugen, z. B. nach Farbänderungen im Script:

```bash
swift Tools/MakeAppIcon.swift
```

Alle drei Anbieter werden per Structured Output auf dasselbe JSON-Schema festgelegt (`RecommendationSchema`), sodass die Antwort immer als `PairingResponse` dekodierbar ist.

### Anbieter-Anbindung

| Anbieter  | Endpoint                                              | Structured Output                          | Standardmodell     |
|-----------|-------------------------------------------------------|--------------------------------------------|--------------------|
| OpenAI    | `POST /v1/chat/completions`                           | `response_format: json_schema` (strict)    | `gpt-5`            |
| Gemini    | `POST /v1beta/models/{model}:generateContent`         | `responseMimeType` + `responseSchema`      | `gemini-2.5-pro`   |
| Anthropic | `POST /v1/messages`                                   | `output_config.format: json_schema`        | `claude-opus-5`    |

Der Modellname ist pro Anbieter in den Einstellungen überschreibbar.

### Fehlerbehandlung

`HTTPTransport.classify` ordnet Antworten sprechenden Fehlern zu: ungültiger Key, Guthaben aufgebraucht, Rate-Limit, Anbieter nicht erreichbar, unbekanntes Modell. Der Wein-Berater zeigt Titel, Erklärung und je nach Fall einen Sprung in die Einstellungen oder „Erneut versuchen“.

## Datenschutz

API-Keys werden ausschließlich in der Keychain des Geräts gespeichert (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) und nur an den jeweiligen Anbieter gesendet. Das Inventar verlässt das Gerät nur als Teil des Prompts an den gewählten Anbieter.
