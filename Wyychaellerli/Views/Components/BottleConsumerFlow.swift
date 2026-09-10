import CoreData
import SwiftUI

/// Hängt an eine Ansicht alles, was nach dem Abbuchen passieren kann: Fach wählen,
/// Frage nach der letzten Flasche, Bewerten, Löschen mit Rückfrage.
///
/// Als ein Modifier, damit der Berater denselben Ablauf hat wie die Kellerliste –
/// vorher buchte er still ab, und die Frage nach Archiv oder Bewertung fehlte.
struct BottleConsumerFlow: ViewModifier {

    @Bindable var consumer: BottleConsumer
    @Environment(\.managedObjectContext) private var context

    func body(content: Content) -> some View {
        content
            .sheet(item: $consumer.wineToTakeFromRack) { wine in
                WineRackSheet(wine: wine, mode: .take)
            }
            .confirmationDialog(
                "Letzte Flasche getrunken",
                isPresented: Binding(
                    get: { consumer.justEmptiedWine != nil },
                    set: { if !$0 { consumer.justEmptiedWine = nil } }
                ),
                titleVisibility: .visible,
                presenting: consumer.justEmptiedWine
            ) { wine in
                Button("Bewerten") { consumer.wineToRate = wine }
                Button("Archivieren") {
                    wine.isArchived = true
                    context.saveChanges()
                }
                Button("Löschen", role: .destructive) { consumer.wineToDelete = wine }
                Button("Im Keller behalten", role: .cancel) { }
            } message: { wine in
                Text("„\(wine.nameWithVintage)“ ist jetzt leer. Was soll damit passieren?")
            }
            .sheet(item: $consumer.wineToRate) { wine in
                RatingSheet(wine: wine)
            }
            .confirmationDialog(
                "Wein löschen?",
                isPresented: Binding(
                    get: { consumer.wineToDelete != nil },
                    set: { if !$0 { consumer.wineToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: consumer.wineToDelete
            ) { wine in
                Button("Endgültig löschen", role: .destructive) {
                    context.delete(wine)
                    context.saveChanges()
                    consumer.wineToDelete = nil
                }
                Button("Abbrechen", role: .cancel) { consumer.wineToDelete = nil }
            } message: { wine in
                Text("„\(wine.nameWithVintage)“ wird mit Etikett, Bewertungen und Regalplatz entfernt – auch auf den anderen Geräten. Zum Aufbewahren lieber archivieren.")
            }
            .sensoryFeedback(.decrease, trigger: consumer.consumeCount)
    }
}

extension View {
    func bottleConsumerFlow(_ consumer: BottleConsumer) -> some View {
        modifier(BottleConsumerFlow(consumer: consumer))
    }
}
