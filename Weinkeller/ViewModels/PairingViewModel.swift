import Foundation
import Observation

/// Zustand des Tabs „Wein-Berater“: Eingabe, Ladezustand, Ergebnis, Fehler.
@Observable
@MainActor
final class PairingViewModel {

    /// Schnellvorschläge für die Eingabe.
    static let suggestions = [
        "Raclette", "Spaghetti Bolognese", "Gegrillter Lachs", "Rindsfilet",
        "Pizza Margherita", "Sushi", "Käseplatte", "Thai-Curry", "Apéro"
    ]

    var dish = ""
    var isLoading = false
    var response: PairingResponse?

    /// Letzter Fehler, typisiert – damit die UI Titel und passende Aktionen anbieten kann.
    var error: AIServiceError?

    /// Für welchen Anbieter und welches Gericht das aktuelle Ergebnis gilt.
    private(set) var resultProvider: AIProvider?
    private(set) var resultModel = ""
    private(set) var resultDish = ""

    var trimmedDish: String { dish.trimmingCharacters(in: .whitespacesAndNewlines) }

    func canRequest(settings: AISettings, hasInventory: Bool) -> Bool {
        !trimmedDish.isEmpty && !isLoading && settings.activeProvider != nil && hasInventory
    }

    func requestRecommendation(
        inventory: [WineInventoryItem],
        settings: AISettings,
        service: AIService
    ) async {
        let dish = trimmedDish
        guard !dish.isEmpty else { return }

        isLoading = true
        error = nil
        response = nil
        defer { isLoading = false }

        let provider = settings.activeProvider
        let model = settings.activeModel ?? ""
        do {
            let result = try await service.recommend(
                PairingRequest(dish: dish, inventory: inventory),
                using: settings
            )
            response = result
            resultProvider = provider
            resultModel = model
            resultDish = dish
        } catch let serviceError as AIServiceError {
            error = serviceError
        } catch {
            self.error = .network(error.localizedDescription)
        }
    }

    func reset() {
        response = nil
        error = nil
        resultProvider = nil
        resultModel = ""
        resultDish = ""
    }
}
