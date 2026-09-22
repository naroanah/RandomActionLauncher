import CoreData
import Foundation

enum ProjectRepositoryError: LocalizedError, Equatable {
    case projectNotFound(UUID)
    case invalidStoredValue(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "找不到项目记录：\(id.uuidString)。"
        case .invalidStoredValue(let field, let value):
            return "项目记录中的 \(field) 值无效：\(value)。"
        }
    }
}

@MainActor
final class ProjectRepository {
    private let context: NSManagedObjectContext

    convenience init(container: NSPersistentContainer) {
        self.init(context: container.viewContext)
    }

    init(context: NSManagedObjectContext) {
        self.context = context
        context.automaticallyMergesChangesFromParent = true
    }

    func fetchAll() throws -> [Project] {
        let request = ProjectRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request).map(makeProject)
    }

    func fetch(id: UUID) throws -> Project? {
        guard let record = try fetchRecord(id: id) else {
            return nil
        }
        return try makeProject(from: record)
    }

    @discardableResult
    func create(_ project: Project) throws -> Project {
        do {
            var normalized = project
            try normalized.normalizeDisplayName()
            let record = NSEntityDescription.insertNewObject(
                forEntityName: ProjectRecord.entityName,
                into: context
            ) as! ProjectRecord
            apply(normalized, to: record)
            try save()
            return normalized
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    func update(id: UUID, changes: (inout Project) throws -> Void) throws -> Project {
        guard let record = try fetchRecord(id: id) else {
            throw ProjectRepositoryError.projectNotFound(id)
        }

        do {
            var project = try makeProject(from: record)
            try changes(&project)
            try project.normalizeDisplayName()
            project.updatedAt = .now
            apply(project, to: record)
            try save()
            return project
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(id: UUID) throws {
        guard let record = try fetchRecord(id: id) else {
            throw ProjectRepositoryError.projectNotFound(id)
        }

        do {
            context.delete(record)
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    private func fetchRecord(id: UUID) throws -> ProjectRecord? {
        let request = ProjectRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func apply(_ project: Project, to record: ProjectRecord) {
        record.id = project.id
        record.displayName = project.displayName
        record.note = project.note
        record.resourceType = project.resourceType.rawValue
        record.originalPath = project.originalPath
        record.bookmarkData = project.bookmarkData
        record.status = project.status.rawValue
        record.weight = Int16(project.weight.rawValue)
        record.createdAt = project.createdAt
        record.updatedAt = project.updatedAt
        record.lastDrawnAt = project.lastDrawnAt
        record.cooldownUntil = project.cooldownUntil
        record.availability = project.availability.rawValue
    }

    private func makeProject(from record: ProjectRecord) throws -> Project {
        guard let resourceType = ProjectResourceType(rawValue: record.resourceType) else {
            throw ProjectRepositoryError.invalidStoredValue(field: "resourceType", value: record.resourceType)
        }
        guard let status = ProjectStatus(rawValue: record.status) else {
            throw ProjectRepositoryError.invalidStoredValue(field: "status", value: record.status)
        }
        guard let weight = ProjectWeight(rawValue: Int(record.weight)) else {
            throw ProjectRepositoryError.invalidStoredValue(field: "weight", value: String(record.weight))
        }
        guard let availability = ProjectAvailability(rawValue: record.availability) else {
            throw ProjectRepositoryError.invalidStoredValue(field: "availability", value: record.availability)
        }

        return try Project(
            displayName: record.displayName,
            note: record.note,
            resourceType: resourceType,
            originalPath: record.originalPath,
            bookmarkData: record.bookmarkData,
            status: status,
            weight: weight,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt,
            lastDrawnAt: record.lastDrawnAt,
            cooldownUntil: record.cooldownUntil,
            availability: availability,
            id: record.id
        )
    }
}
