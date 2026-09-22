import CoreData
import Foundation

@objc(ProjectRecord)
final class ProjectRecord: NSManagedObject {
    static let entityName = "ProjectRecord"

    @NSManaged var id: UUID
    @NSManaged var displayName: String
    @NSManaged var note: String
    @NSManaged var resourceType: String
    @NSManaged var originalPath: String
    @NSManaged var bookmarkData: Data
    @NSManaged var status: String
    @NSManaged var weight: Int16
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var lastDrawnAt: Date?
    @NSManaged var cooldownUntil: Date?
    @NSManaged var availability: String

    @nonobjc class func fetchRequest() -> NSFetchRequest<ProjectRecord> {
        NSFetchRequest<ProjectRecord>(entityName: entityName)
    }
}
