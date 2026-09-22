import CoreData
import Foundation

@objc(DrawSessionRecord)
final class DrawSessionRecord: NSManagedObject {
    static let entityName = "DrawSessionRecord"

    @NSManaged var id: UUID
    @NSManaged var startedAt: Date
    @NSManaged var rerollCount: Int32
    @NSManaged var didClickOpen: Bool
    @NSManaged var openedProjectId: UUID?
    @NSManaged var openedAt: Date?
    @NSManaged var timeToOpenMs: NSNumber?
    @NSManaged var endedAt: Date?

    @nonobjc class func fetchRequest() -> NSFetchRequest<DrawSessionRecord> {
        NSFetchRequest<DrawSessionRecord>(entityName: entityName)
    }
}

@objc(SessionProjectRecord)
final class SessionProjectRecord: NSManagedObject {
    static let entityName = "SessionProjectRecord"

    @NSManaged var sessionID: UUID
    @NSManaged var projectID: UUID

    @nonobjc class func fetchRequest() -> NSFetchRequest<SessionProjectRecord> {
        NSFetchRequest<SessionProjectRecord>(entityName: entityName)
    }
}
