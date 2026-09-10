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

    // MARK: Nachschlagen

    /// Keller, den jemand anderes mit uns geteilt hat. `nil`, wenn es keinen gibt.
    static func sharedWithMe(in context: NSManagedObjectContext) -> Cellar? {
        guard let store = sharedStore(for: context) else { return nil }
        return first(in: context, store: store)
    }

    /// Eigener Keller. `nil`, solange noch keiner angelegt wurde.
    static func own(in context: NSManagedObjectContext) -> Cellar? {
        guard let store = privateStore(for: context) else { return nil }
        return first(in: context, store: store)
    }

    /// Speicher aus dem Context ableiten statt aus dem Singleton – sonst greifen
    /// Previews mit eigenem Stack auf die falsche Ablage zu.
    static func sharedStore(for context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores.first { isSharedStore($0) }
    }

    static func privateStore(for context: NSManagedObjectContext) -> NSPersistentStore? {
        context.persistentStoreCoordinator?.persistentStores.first { !isSharedStore($0) }
    }

    private static func isSharedStore(_ store: NSPersistentStore) -> Bool {
        store.url?.lastPathComponent == PersistenceController.sharedStoreFileName
    }

    /// Der aktuell massgebende Keller, **ohne** ihn anzulegen.
    ///
    /// Beim Gast ist das der geteilte, sonst der eigene. Wird überall dort gebraucht, wo
    /// nur gelesen wird – etwa um zu entscheiden, welches Regal gemeint ist.
    static func current(in context: NSManagedObjectContext) -> Cellar? {
        sharedWithMe(in: context) ?? own(in: context)
    }

    /// Der Keller, in den neue Flaschen gehören.
    ///
    /// Wurde ein Keller mit uns geteilt, landen neue Flaschen dort – sonst sähe die
    /// andere Seite sie nie. Nur ohne Freigabe wird ein eigener Keller angelegt.
    static func active(in context: NSManagedObjectContext) -> Cellar {
        sharedWithMe(in: context) ?? findOrCreateOwn(in: context)
    }

    /// Eigener Keller, notfalls neu angelegt. Nur aufrufen, wenn wirklich geschrieben wird –
    /// nicht beim blossen Anzeigen einer Ansicht.
    @discardableResult
    static func findOrCreateOwn(in context: NSManagedObjectContext) -> Cellar {
        if let existing = own(in: context) { return existing }
        let cellar = Cellar(context: context)
        if let store = privateStore(for: context) {
            context.assign(cellar, to: store)
        }
        cellar.uuid = UUID()
        cellar.name = "Mein Weinkeller"
        cellar.createdAt = .now
        context.saveChanges()
        return cellar
    }

    private static func first(in context: NSManagedObjectContext, store: NSPersistentStore) -> Cellar? {
        let request = fetchRequest()
        request.fetchLimit = 1
        request.affectedStores = [store]
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try? context.fetch(request).first
    }
}
