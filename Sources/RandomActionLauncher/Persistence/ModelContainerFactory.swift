import CoreData
import Foundation

enum PersistenceContainerFactory {
    private static let storeName = "RandomActionLauncher"

    static func makeApplicationContainer() throws -> NSPersistentContainer {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport.appendingPathComponent(storeName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try makeDiskContainer(at: directory.appendingPathComponent("projects.sqlite"))
    }

    static func makeInMemoryContainer() throws -> NSPersistentContainer {
        try makeContainer(storeType: NSInMemoryStoreType, url: URL(fileURLWithPath: "/dev/null"))
    }

    static func makeDiskContainer(at url: URL) throws -> NSPersistentContainer {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        return try makeContainer(storeType: NSSQLiteStoreType, url: url)
    }

    private static func makeContainer(storeType: String, url: URL) throws -> NSPersistentContainer {
        let container = NSPersistentContainer(
            name: storeName,
            managedObjectModel: makeManagedObjectModel()
        )
        let description = NSPersistentStoreDescription(url: url)
        description.type = storeType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]

        let result = StoreLoadResult()
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in
            result.error = error
            semaphore.signal()
        }
        semaphore.wait()

        if let error = result.error {
            throw error
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy(merge: .errorMergePolicyType)
        return container
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = ProjectRecord.entityName
        entity.managedObjectClassName = NSStringFromClass(ProjectRecord.self)
        entity.properties = [
            attribute("id", type: .UUIDAttributeType, optional: false),
            attribute("displayName", type: .stringAttributeType, optional: false),
            attribute("note", type: .stringAttributeType, optional: false),
            attribute("resourceType", type: .stringAttributeType, optional: false),
            attribute("originalPath", type: .stringAttributeType, optional: false),
            attribute("bookmarkData", type: .binaryDataAttributeType, optional: false),
            attribute("status", type: .stringAttributeType, optional: false),
            attribute("weight", type: .integer16AttributeType, optional: false),
            attribute("createdAt", type: .dateAttributeType, optional: false),
            attribute("updatedAt", type: .dateAttributeType, optional: false),
            attribute("lastDrawnAt", type: .dateAttributeType, optional: true),
            attribute("cooldownUntil", type: .dateAttributeType, optional: true),
            attribute("availability", type: .stringAttributeType, optional: false)
        ]
        entity.uniquenessConstraints = [["id"]]

        let sessionEntity = NSEntityDescription()
        sessionEntity.name = DrawSessionRecord.entityName
        sessionEntity.managedObjectClassName = NSStringFromClass(DrawSessionRecord.self)
        sessionEntity.properties = [
            attribute("id", type: .UUIDAttributeType, optional: false),
            attribute("startedAt", type: .dateAttributeType, optional: false),
            attribute("rerollCount", type: .integer32AttributeType, optional: false),
            attribute("didClickOpen", type: .booleanAttributeType, optional: false),
            attribute("openedProjectId", type: .UUIDAttributeType, optional: true),
            attribute("openedAt", type: .dateAttributeType, optional: true),
            attribute("timeToOpenMs", type: .integer64AttributeType, optional: true),
            attribute("endedAt", type: .dateAttributeType, optional: true),
        ]
        sessionEntity.uniquenessConstraints = [["id"]]

        let associationEntity = NSEntityDescription()
        associationEntity.name = SessionProjectRecord.entityName
        associationEntity.managedObjectClassName = NSStringFromClass(SessionProjectRecord.self)
        associationEntity.properties = [
            attribute("sessionID", type: .UUIDAttributeType, optional: false),
            attribute("projectID", type: .UUIDAttributeType, optional: false),
        ]
        associationEntity.uniquenessConstraints = [["sessionID", "projectID"]]

        model.entities = [entity, sessionEntity, associationEntity]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        optional: Bool
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

private final class StoreLoadResult: @unchecked Sendable {
    var error: Error?
}
