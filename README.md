# Weinkeller

Privater Weinkeller-Assistent für iPhone und iPad. Verwaltet den Flaschenbestand und schlägt zum geplanten Essen die passenden Weine aus dem eigenen Keller vor – wahlweise über ChatGPT (OpenAI), Gemini (Google) oder Claude (Anthropic).

## Funktionen

- **Weinkeller** – Flaschen mit Name, Jahrgang, Rebsorte/Region, Typ (Rot, Weiß, Schaum, Rosé) und Bestand. Schnell-Abbuchung per Minus-Button, Filter nach Typ, Suche, Archiv. Bei der letzten Flasche fragt die App, ob der Wein archiviert oder gelöscht werden soll.
- **Wein-Berater** – Essens-Stichwort eingeben (z. B. „Raclette“), die KI liefert bis zu drei Empfehlungen aus dem aktuellen Bestand mit Begründung und Serviertipp. „Flasche öffnen“ bucht direkt ab.
- **Einstellungen** – API-Key und Modellname pro Anbieter. Der Anbieter mit hinterlegtem Key ist automatisch aktiv; bei mehreren Keys lässt sich ein bevorzugter wählen. Keys liegen in der Keychain, nie in UserDefaults.

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
├── App/            WeinkellerApp – ModelContainer, Settings und AIService im Environment
├── Models/         Wine (SwiftData), PairingRequest/PairingResponse, JSON-Schema
├── Services/
│   ├── AIService       Fassade: wählt den Client zum aktiven Anbieter
│   ├── AISettings      Keys (Keychain), Modelle, aktiver Anbieter
│   ├── HTTPTransport   URLSession-Layer, Fehler-Klassifikation
│   ├── PromptBuilder   System- und User-Prompt
│   ├── KeychainStore   Generic-Password-Wrapper
│   └── Providers/      OpenAIClient, GeminiClient, AnthropicClient
├── ViewModels/     CellarViewModel, WineFormViewModel, PairingViewModel
├── Views/          Cellar, Advisor, Settings, Components
└── Preview Content/ In-Memory-Beispieldaten für Xcode-Previews
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
