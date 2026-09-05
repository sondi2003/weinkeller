import Foundation

/// Die drei unterstützten KI-Anbieter. `rawValue` dient gleichzeitig als
/// Keychain-Account und als UserDefaults-Schlüssel – also nicht umbenennen.
enum AIProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openAI = "openai"
    case gemini = "gemini"
    case anthropic = "anthropic"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:    return "ChatGPT (OpenAI)"
        case .gemini:    return "Gemini (Google)"
        case .anthropic: return "Claude (Anthropic)"
        }
    }

    var shortName: String {
        switch self {
        case .openAI:    return "ChatGPT"
        case .gemini:    return "Gemini"
        case .anthropic: return "Claude"
        }
    }

    /// Modell, das verwendet wird, solange der Nutzer in den Einstellungen nichts anderes einträgt.
    var defaultModel: String {
        switch self {
        case .openAI:    return "gpt-5"
        case .gemini:    return "gemini-2.5-pro"
        case .anthropic: return "claude-opus-5"
        }
    }

    /// Hilfetext für das API-Key-Feld.
    var apiKeyHint: String {
        switch self {
        case .openAI:    return "Beginnt mit „sk-…“ – erstellen unter platform.openai.com/api-keys"
        case .gemini:    return "Erstellen unter aistudio.google.com/app/apikey"
        case .anthropic: return "Beginnt mit „sk-ant-…“ – erstellen unter console.anthropic.com"
        }
    }

    var symbolName: String {
        switch self {
        case .openAI:    return "bubble.left.and.text.bubble.right"
        case .gemini:    return "sparkles"
        case .anthropic: return "brain"
        }
    }
}
