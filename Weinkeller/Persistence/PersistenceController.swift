import CloudKit
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
    /// Dateiname der Ablage für Keller, die andere mit uns geteilt haben.
    static let sharedStoreFileName = "Weinkeller-shared.sqlite"

    let container: NSPersistentCloudKitContainer

    /// Eigener Keller. Neue Flaschen landen hier.
    private(set) var privateStore: NSPersistentStore?
    /// Keller, die andere mit uns geteilt haben.
    private(set) var sharedStore: NSPersistentStore? {
        didSet { drainPendingShares() }
    }

    /// Einladungen, die eintrafen, bevor der geteilte Speicher bereit war.
    /// Ohne diese Warteschlange geht eine Einladung verloren, wenn der Link die App startet.
    private var pendingShareMetadata: [CKShare.Metadata] = []

    /// Beobachter für die CloudKit-Ereignisse; festhalten, damit er nicht abgeräumt wird.
    private var cloudEventObserver: NSObjectProtocol?

    var viewContext: NSManagedObjectContext { container.viewContext }

    /// `false`, wenn der geteilte Speicher nicht geladen werden konnte.
    ///
    /// Dann kann keine Einladung angenommen werden, und die Einstellungen zeigen fälschlich
    /// „Weinkeller teilen“, als wäre man Eigentümer ohne Freigabe. Ohne diese Auskunft ist
    /// der Zustand von aussen nicht von „es wurde nichts geteilt“ zu unterscheiden.
    var isSharedStoreAvailable: Bool { sharedStore != nil }

    /// - Parameters:
    ///   - inMemory: für Previews und Tests, schreibt nichts auf die Platte.
    ///   - useCloudKit: in Previews abschaltbar.
    init(inMemory: Bool = false, useCloudKit: Bool = true) {
        container = NSPersistentCloudKitContainer(
            name: "Weinkeller",
            managedObjectModel: PersistenceController.makeModel()
        )

        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("Keine Store-Beschreibung vorhanden.")
        }

        if inMemory {
            privateDescription.url = URL(fileURLWithPath: "/dev/null")
            privateDescription.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [privateDescription]
        } else {
            let directory = NSPersistentContainer.defaultDirectoryURL()
            // Der Pfad des privaten Speichers muss unverändert bleiben, sonst wäre der
            // bestehende Keller weg.
            privateDescription.url = directory.appendingPathComponent("Weinkeller.sqlite")
            Self.configure(privateDescription, scope: .private, useCloudKit: useCloudKit)

            if useCloudKit {
                // Zweiter Speicher für Keller, die andere mit uns geteilt haben.
                let sharedDescription = privateDescription.copy() as! NSPersistentStoreDescription
                sharedDescription.url = directory.appendingPathComponent(Self.sharedStoreFileName)
                Self.configure(sharedDescription, scope: .shared, useCloudKit: true)
                container.persistentStoreDescriptions = [privateDescription, sharedDescription]
            } else {
                container.persistentStoreDescriptions = [privateDescription]
            }
        }

        container.loadPersistentStores { [weak self] storeDescription, error in
            let fileName = storeDescription.url?.lastPathComponent ?? "-"
            if let error {
                // Welcher Speicher betroffen ist, entscheidet alles: Fehlt der geteilte,
                // kann keine Einladung angenommen werden und die App merkt es nie.
                Self.logger.error("Store \(fileName, privacy: .public) nicht geladen: \(error.localizedDescription, privacy: .public)")
                return
            }
            Self.logger.info("Store geladen: \(fileName, privacy: .public)")
            guard let self, let url = storeDescription.url,
                  let store = self.container.persistentStoreCoordinator.persistentStore(for: url) else { return }
            switch storeDescription.cloudKitContainerOptions?.databaseScope {
            case .shared: self.sharedStore = store
            default:      self.privateStore = store
            }
        }

        // Änderungen vom Gerät der Partnerin sollen ohne Zutun im UI ankommen.
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        observeCloudKitEvents()
    }

    /// Schreibt mit, ob CloudKit Einrichtung, Empfang und Versand schafft.
    ///
    /// Ohne das scheitert der Abgleich lautlos: Auf dem Gerät des Gasts erscheinen einfach
    /// keine Daten, und es gibt nichts, woran man die Ursache festmachen könnte. Die
    /// Meldungen laufen unter demselben Subsystem wie der Rest der App und sind damit
    /// über `log stream` oder die Konsole am Mac lesbar.
    private func observeCloudKitEvents() {
        cloudEventObserver = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.endDate != nil else { return }

            let kind: String
            switch event.type {
            case .setup:  kind = "Einrichtung"
            case .import: kind = "Empfangen"
            case .export: kind = "Senden"
            @unknown default: kind = "Unbekannt"
            }
            if let error = event.error {
                Self.logger.error("CloudKit \(kind, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                Self.logger.info("CloudKit \(kind, privacy: .public) erfolgreich.")
            }
        }
    }

    /// Alle Flaschen, die aktuell trinkbereit im Keller liegen. Auch vom Siri-Intent genutzt.
    @MainActor
    func availableWines() -> [Wine] {
        let request = Wine.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "isArchived == NO AND quantity > 0")
        return (try? viewContext.fetch(request)) ?? []
    }

    /// Gemeinsame Einstellungen beider Speicher.
    private static func configure(
        _ description: NSPersistentStoreDescription,
        scope: CKDatabase.Scope,
        useCloudKit: Bool
    ) {
        // Beides ist für CloudKit Pflicht.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        // Nach jeder Modelländerung muss der bestehende Speicher mitwandern. Das ist zwar
        // die Voreinstellung, steht hier aber ausdrücklich: Scheitert die Wanderung beim
        // geteilten Speicher, verschwindet die Freigabe spurlos.
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        guard useCloudKit else {
            description.cloudKitContainerOptions = nil
            return
        }
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainerIdentifier)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
    }

    // MARK: Freigabe

    enum SharingError: LocalizedError {
        case notReady
        var errorDescription: String? {
            "Die Freigabe ist gerade nicht möglich. Prüfe, ob du in iCloud angemeldet bist."
        }
    }

    /// Erzeugt (oder holt) die Freigabe für den Keller. Das Ergebnis wird direkt an
    /// Apples Freigabe-Dialog übergeben.
    @MainActor
    func share(_ cellar: Cellar) async throws -> (CKShare, CKContainer) {
        let (share, cloudContainer) = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(CKShare, CKContainer), Error>) in
            container.share([cellar], to: nil) { _, share, cloudContainer, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let share, let cloudContainer {
                    continuation.resume(returning: (share, cloudContainer))
                } else {
                    continuation.resume(throwing: SharingError.notReady)
                }
            }
        }
        return (try await titled(share), cloudContainer)
    }

    /// Setzt den Titel auch bei einer Freigabe, die schon vor dieser Korrektur entstanden ist.
    /// Ohne das behält eine bestehende Einladung für immer den internen Namen.
    @MainActor
    func ensuringTitle(on share: CKShare) async -> CKShare {
        (try? await titled(share)) ?? share
    }

    /// Setzt den Titel der Einladung **und speichert ihn**.
    ///
    /// `container.share(...)` legt die Freigabe bereits auf dem Server ab. Ein danach
    /// gesetzter Titel bleibt eine rein lokale Änderung; auf dem Server steht dann kein
    /// Titel, und iOS zeigt der eingeladenen Person ersatzweise den internen Namen des
    /// Datensatzes an – bei Core Data ist das „cloudkit.zoneshare“. Deshalb muss der
    /// Titel mit `persistUpdatedShare` zurückgeschrieben werden, bevor die Einladung
    /// verschickt wird.
    private func titled(_ share: CKShare) async throws -> CKShare {
        guard share[CKShare.SystemFieldKey.title] == nil, let store = privateStore else {
            return share
        }
        share[CKShare.SystemFieldKey.title] = "Weinkeller" as CKRecordValue
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<CKShare, Error>) in
            container.persistUpdatedShare(share, in: store) { updated, error in
                if let error {
                    Self.logger.error("Titel der Freigabe nicht gespeichert: \(error.localizedDescription)")
                    // Ohne Titel ist die Einladung hässlich, aber brauchbar – nicht abbrechen.
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(returning: updated ?? share)
                }
            }
        }
    }

    /// Bereits bestehende Freigabe zu einem Keller, falls vorhanden.
    func existingShare(for cellar: Cellar) -> CKShare? {
        try? container.fetchShares(matching: [cellar.objectID])[cellar.objectID]
    }

    /// Nimmt eine Einladung an, die über den Freigabe-Link geöffnet wurde.
    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let sharedStore else {
            // Startet die Einladung die App, ist der Speicher noch nicht geladen.
            // Merken und nachholen, sobald er bereitsteht.
            Self.logger.info("Einladung vorgemerkt, Speicher lädt noch.")
            pendingShareMetadata.append(metadata)
            return
        }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error {
                Self.logger.error("Einladung konnte nicht angenommen werden: \(error.localizedDescription)")
            } else {
                Self.logger.info("Einladung angenommen.")
            }
        }
    }

    /// Holt vorgemerkte Einladungen nach, sobald der geteilte Speicher da ist.
    private func drainPendingShares() {
        guard sharedStore != nil, !pendingShareMetadata.isEmpty else { return }
        let pending = pendingShareMetadata
        pendingShareMetadata = []
        Self.logger.info("Hole \(pending.count) vorgemerkte Einladung(en) nach.")
        for metadata in pending {
            acceptShare(metadata)
        }
    }

    /// Speichert Änderungen aus dem Freigabe-Dialog (Teilnehmer, Rechte).
    func persist(_ share: CKShare) {
        guard let store = privateStore else { return }
        container.persistUpdatedShare(share, in: store) { _, error in
            if let error {
                Self.logger.error("Freigabe konnte nicht gespeichert werden: \(error.localizedDescription)")
            }
        }
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
            binaryAttribute("backLabelImageData"),
            attribute("drinkFrom", .integer64AttributeType, default: 0),
            attribute("drinkTo", .integer64AttributeType, default: 0),
            attribute("drinkWindowFromLabel", .booleanAttributeType, default: false),
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
