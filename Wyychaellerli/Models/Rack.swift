import CoreData
import Foundation

/// Ein Weinregal als Raster aus Zeilen und Spalten.
///
/// Ein Fach ist genau eine Flasche tief. Regale mit mehreren Flaschen hintereinander
/// gäbe es zwar, dafür bräuchte es eine dritte Achse – das Raster ist bewusst so
/// aufgebaut, dass sich das später ergänzen liesse, ohne die Zuordnung zu verlieren.
///
/// Mehrere Regale sind vorgesehen, auch wenn hier zunächst nur eines gebraucht wird.
@objc(RackEntity)
final class Rack: NSManagedObject, Identifiable {

    @nonobjc class func fetchRequest() -> NSFetchRequest<Rack> {
        NSFetchRequest<Rack>(entityName: "Rack")
    }

    @NSManaged var uuid: UUID?
    @NSManaged var name: String
    @NSManaged var rows: Int64
    @NSManaged var columns: Int64
    @NSManaged var createdAt: Date?
    @NSManaged var cellar: Cellar?
    /// Nur die **belegten** Fächer. Freie Fächer haben kein Objekt.
    @NSManaged var slots: NSSet?

    var id: NSManagedObjectID { objectID }

    /// Sinnvolle Grenzen für die Einrichtung. Grösser wird auf dem Bildschirm unlesbar.
    static let rowRange = 1...12
    static let columnRange = 1...20

    var rowCount: Int { max(1, Int(rows)) }
    var columnCount: Int { max(1, Int(columns)) }
    var capacity: Int { rowCount * columnCount }

    var placedSlots: [Slot] {
        ((slots as? Set<Slot>) ?? []).filter { $0.wine != nil }
    }

    var usedCount: Int { placedSlots.count }
    var freeCount: Int { max(0, capacity - usedCount) }

    /// Belegung als Nachschlagewerk, damit die Ansicht nicht je Fach suchen muss.
    func occupancy() -> [Position: Slot] {
        Dictionary(placedSlots.map { (Position(row: Int($0.row), column: Int($0.column)), $0) }) { first, _ in first }
    }

    /// Erstes freies Fach, zeilenweise von oben links – für „einfach irgendwo hin“.
    func firstFreePosition() -> Position? {
        let taken = Set(placedSlots.map { Position(row: Int($0.row), column: Int($0.column)) })
        for row in 0..<rowCount {
            for column in 0..<columnCount where !taken.contains(Position(row: row, column: column)) {
                return Position(row: row, column: column)
            }
        }
        return nil
    }

    /// Fächer, die durch Verkleinern ausserhalb des Rasters liegen würden.
    func slotsOutsideGrid(rows newRows: Int, columns newColumns: Int) -> [Slot] {
        placedSlots.filter { Int($0.row) >= newRows || Int($0.column) >= newColumns }
    }

    /// Das Regal des Kellers, angelegt falls noch keines da ist.
    @discardableResult
    static func findOrCreate(in context: NSManagedObjectContext, cellar: Cellar) -> Rack {
        if let existing = all(in: context).first { return existing }
        let rack = Rack(context: context)
        // Muss in denselben Speicher wie der Keller, sonst sieht die andere Seite es nie.
        if let store = cellar.objectID.persistentStore {
            context.assign(rack, to: store)
        }
        rack.uuid = UUID()
        rack.cellar = cellar
        rack.name = "Regal"
        rack.rows = 1
        rack.columns = 12
        rack.createdAt = .now
        context.saveChanges()
        return rack
    }

    static func all(in context: NSManagedObjectContext) -> [Rack] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }
}

/// Ein Fach im Raster. Zeile und Spalte zählen ab 0.
struct Position: Hashable {
    let row: Int
    let column: Int

    /// Für Menschen: Zeile als Buchstabe, Spalte als Zahl ab 1 – „B3“.
    var label: String {
        let letter = String(UnicodeScalar(UInt8(65 + min(row, 25))))
        return "\(letter)\(column + 1)"
    }
}
