import CoreData
import Foundation

@MainActor
final class DrawSessionRepository {
    private let context: NSManagedObjectContext

    convenience init(container: NSPersistentContainer) {
        self.init(context: container.viewContext)
    }

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func fetchAll() throws -> [DrawSession] {
        let request = DrawSessionRecord.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "startedAt", ascending: false)]
        return try context.fetch(request).map(makeSession)
    }

    func fetch(id: UUID) throws -> DrawSession? {
        try fetchRecord(id: id).map(makeSession)
    }

    @discardableResult
    func create(_ session: DrawSession) throws -> DrawSession {
        do {
            let record = NSEntityDescription.insertNewObject(
                forEntityName: DrawSessionRecord.entityName,
                into: context
            ) as! DrawSessionRecord
            apply(session, to: record)
            try save()
            return session
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    func update(id: UUID, changes: (inout DrawSession) throws -> Void) throws -> DrawSession {
        guard let record = try fetchRecord(id: id) else {
            throw DrawSessionRepositoryError.sessionNotFound(id)
        }
        do {
            var session = makeSession(from: record)
            try changes(&session)
            apply(session, to: record)
            try save()
            return session
        } catch {
            context.rollback()
            throw error
        }
    }

    func recordDisplayedProject(sessionID: UUID, projectID: UUID) throws {
        let request = SessionProjectRecord.fetchRequest()
        request.predicate = NSPredicate(
            format: "sessionID == %@ AND projectID == %@",
            sessionID as CVarArg,
            projectID as CVarArg
        )
        request.fetchLimit = 1
        if try context.fetch(request).first != nil { return }

        do {
            let record = NSEntityDescription.insertNewObject(
                forEntityName: SessionProjectRecord.entityName,
                into: context
            ) as! SessionProjectRecord
            record.sessionID = sessionID
            record.projectID = projectID
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteSessions(associatedWith projectID: UUID) throws {
        let request = SessionProjectRecord.fetchRequest()
        request.predicate = NSPredicate(format: "projectID == %@", projectID as CVarArg)

        do {
            let associations = try context.fetch(request)
            let sessionIDs = Set(associations.map(\.sessionID))
            for association in associations {
                context.delete(association)
            }

            for sessionID in sessionIDs {
                if let record = try fetchRecord(id: sessionID) {
                    context.delete(record)
                }
            }
            try save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func fetchRecord(id: UUID) throws -> DrawSessionRecord? {
        let request = DrawSessionRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func save() throws {
        guard context.hasChanges else { return }
        try context.save()
    }

    private func apply(_ session: DrawSession, to record: DrawSessionRecord) {
        record.id = session.id
        record.startedAt = session.startedAt
        record.rerollCount = Int32(session.rerollCount)
        record.didClickOpen = session.didClickOpen
        record.openedProjectId = session.openedProjectId
        record.openedAt = session.openedAt
        record.timeToOpenMs = session.timeToOpenMs.map { NSNumber(value: $0) }
        record.endedAt = session.endedAt
    }

    private func makeSession(from record: DrawSessionRecord) -> DrawSession {
        var session = DrawSession(startedAt: record.startedAt, id: record.id)
        session.rerollCount = Int(record.rerollCount)
        session.didClickOpen = record.didClickOpen
        session.openedProjectId = record.openedProjectId
        session.openedAt = record.openedAt
        session.timeToOpenMs = record.timeToOpenMs.map { $0.intValue }
        session.endedAt = record.endedAt
        return session
    }
}

enum DrawSessionRepositoryError: LocalizedError, Equatable {
    case sessionNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .sessionNotFound(let id):
            return "找不到抽取会话：\(id.uuidString)。"
        }
    }
}
