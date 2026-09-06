import CoreData
import Foundation

/// Wurzelobjekt für die Freigabe: Alle Flaschen hängen an einem Keller.
/// CloudKit teilt immer einen Objektbaum, deshalb braucht es dieses Dach,
/// damit „meine Frau bekommt den ganzen Keller“ mit einer Einladung funktioniert.
@objc(CellarEntity)
final class Cellar: NSManagedObject {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Cellar> {
        NSFetchRequest<Cellar>(entityName: "Cellar")
    }

    @NSManaged var uuid: UUID?
    @NSManaged var name: String
    @NSManaged var createdAt: Date?
    @NSManaged var wines: NSSet?

    /// Liefert den vorhandenen Keller oder legt ihn beim ersten Start an.
    static func findOrCreateDefault(in context: NSManagedObjectContext) -> Cellar {
        let request = fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        if let existing = try? context.fetch(request).first {
            return existing
        }
        let cellar = Cellar(context: context)
        cellar.uuid = UUID()
        cellar.name = "Mein Weinkeller"
        cellar.createdAt = .now
        context.saveChanges()
        return cellar
    }
}
