import CoreData
import Foundation
import OSLog

/// Core-Data-Stack mit CloudKit.
///
/// Warum Core Data statt SwiftData: SwiftData kennt für CloudKit nur `private`,
/// also ausschliesslich die eigene Apple-ID. Für die Freigabe an eine zweite Person
/// braucht es `NSPersistentCloudKitContainer`, das Freigaben unterstützt.
///
/// Das Datenmodell wird im Code beschrieben statt in einer .xcdatamodeld-Datei.
/// Das hält alles an einer Stelle und funktioniert zuverlässig mit dem
/// synchronisierten Projektordner.
/// `@unchecked Sendable`: Core-Data-Contexts sind nicht `Sendable`. Zugegriffen wird
/// ausschliesslich über `viewContext` und nur vom Main Thread (Views, Siri-Intent),
/// deshalb ist die Zusicherung hier von Hand gegeben.
final class PersistenceController: @unchecked Sendable {

    static let shared = PersistenceController()

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Persistence")
    static let cloudContainerIdentifier = "iCloud.com.sondinetwork.weinkeller.app"

    let container: NSPersistentCloudKitContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// - Parameters:
    ///   - inMemory: für Previews und Tests, schreibt nichts auf die Platte.
    ///   - useCloudKit: in Previews abschaltbar.
    init(inMemory: Bool = false, useCloudKit: Bool = true) {
        container = NSPersistentCloudKitContainer(
            name: "Weinkeller",
            managedObjectModel: PersistenceController.makeModel()
        )

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Keine Store-Beschreibung vorhanden.")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
            description.cloudKitContainerOptions = nil
        } else {
            // Beides ist für CloudKit Pflicht.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            if useCloudKit {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: Self.cloudContainerIdentifier
                )
            } else {
                description.cloudKitContainerOptions = nil
            }
        }

        container.loadPersistentStores { storeDescription, error in
            if let error {
                Self.logger.error("Store konnte nicht geladen werden: \(error.localizedDescription)")
            } else {
                Self.logger.info("Store geladen: \(storeDescription.url?.lastPathComponent ?? "-")")
            }
        }

        // Änderungen vom Gerät der Partnerin sollen ohne Zutun im UI ankommen.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
    }

    /// Alle Flaschen, die aktuell trinkbereit im Keller liegen. Auch vom Siri-Intent genutzt.
    @MainActor
    func availableWines() -> [Wine] {
        let request = Wine.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "isArchived == NO AND quantity > 0")
        return (try? viewContext.fetch(request)) ?? []
    }

    // MARK: Datenmodell

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let cellar = NSEntityDescription()
        cellar.name = "Cellar"
        cellar.managedObjectClassName = "CellarEntity"

        let wine = NSEntityDescription()
        wine.name = "Wine"
        wine.managedObjectClassName = "WineEntity"

        // CloudKit verlangt: jedes Attribut optional oder mit Standardwert,
        // keine Eindeutigkeits-Bedingungen, alle Beziehungen optional.
        cellar.properties = [
            attribute("uuid", .UUIDAttributeType, optional: true),
            attribute("name", .stringAttributeType, default: "Mein Weinkeller"),
            attribute("createdAt", .dateAttributeType, optional: true)
        ]

        wine.properties = [
            attribute("uuid", .UUIDAttributeType, optional: true),
            attribute("name", .stringAttributeType, default: ""),
            attribute("producer", .stringAttributeType, default: ""),
            attribute("vintage", .integer64AttributeType, default: 0),
            attribute("grape", .stringAttributeType, default: ""),
            attribute("region", .stringAttributeType, default: ""),
            attribute("country", .stringAttributeType, default: ""),
            attribute("typeRaw", .stringAttributeType, default: WineType.red.rawValue),
            attribute("quantity", .integer64AttributeType, default: 1),
            attribute("isArchived", .booleanAttributeType, default: false),
            attribute("notes", .stringAttributeType, default: ""),
            attribute("foodPairingsRaw", .stringAttributeType, default: ""),
            binaryAttribute("labelImageData"),
            attribute("latitude", .doubleAttributeType, default: 0.0),
            attribute("longitude", .doubleAttributeType, default: 0.0),
            attribute("geocodedQuery", .stringAttributeType, default: ""),
            attribute("geocodedPlaceName", .stringAttributeType, default: ""),
            attribute("geocodePrecision", .stringAttributeType, default: ""),
            attribute("createdAt", .dateAttributeType, optional: true)
        ]

        // Beziehung in beide Richtungen: der Keller ist später die Wurzel der Freigabe.
        let winesRelation = NSRelationshipDescription()
        winesRelation.name = "wines"
        winesRelation.destinationEntity = wine
        winesRelation.minCount = 0
        winesRelation.maxCount = 0          // 0 = beliebig viele
        winesRelation.isOptional = true
        winesRelation.deleteRule = .cascadeDeleteRule

        let cellarRelation = NSRelationshipDescription()
        cellarRelation.name = "cellar"
        cellarRelation.destinationEntity = cellar
        cellarRelation.minCount = 0
        cellarRelation.maxCount = 1
        cellarRelation.isOptional = true
        cellarRelation.deleteRule = .nullifyDeleteRule

        winesRelation.inverseRelationship = cellarRelation
        cellarRelation.inverseRelationship = winesRelation

        cellar.properties.append(winesRelation)
        wine.properties.append(cellarRelation)

        model.entities = [cellar, wine]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        default defaultValue: Any? = nil,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }

    /// Etikettfotos liegen als Datei neben der Datenbank, nicht in ihr.
    private static func binaryAttribute(_ name: String) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .binaryDataAttributeType
        attribute.isOptional = true
        attribute.allowsExternalBinaryDataStorage = true
        return attribute
    }
}

// MARK: - Speichern

extension NSManagedObjectContext {

    private static let logger = Logger(subsystem: "com.weinkeller.app", category: "Persistence")

    /// Speichert nur, wenn es etwas zu speichern gibt. Fehler landen im Log statt in einem Absturz.
    func saveChanges() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            Self.logger.error("Speichern fehlgeschlagen: \(error.localizedDescription)")
        }
    }
}
