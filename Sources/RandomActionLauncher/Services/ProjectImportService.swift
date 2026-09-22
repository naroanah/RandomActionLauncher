import Foundation

@MainActor
protocol ProjectStoring: AnyObject {
    func fetchAll() throws -> [Project]
    @discardableResult
    func create(_ project: Project) throws -> Project
}

@MainActor
protocol ProjectManaging: ProjectStoring {
    func fetch(id: UUID) throws -> Project?
    @discardableResult
    func update(id: UUID, changes: (inout Project) throws -> Void) throws -> Project
    func delete(id: UUID) throws
}

extension ProjectRepository: ProjectManaging {}

enum ImportError: LocalizedError, Equatable {
    case resourceUnavailable(path: String)
    case unsupportedResource(path: String, reason: String)
    case duplicateCheckFailed(reason: String)
    case bookmarkCreationFailed(path: String, reason: String)
    case persistenceFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .resourceUnavailable(let path):
            return "资源不存在或无法读取：\(path)"
        case .unsupportedResource(let path, let reason):
            return "已拒绝添加：\(reason)（\(path)）"
        case .duplicateCheckFailed(let reason):
            return "无法检查重复项目：\(reason)"
        case .bookmarkCreationFailed(let path, let reason):
            return "无法保存访问授权：\(reason)（\(path)）"
        case .persistenceFailed(let reason):
            return "保存项目失败：\(reason)"
        }
    }
}

enum ImportOutcome: Equatable {
    case created(Project)
    case duplicate(Project)
}

/// 导入服务：文件选择器与拖放共用的一条导入路径，
/// 负责资源校验、重复识别、安全作用域书签创建和持久化。
@MainActor
final class ProjectImportService {
    private let store: any ProjectStoring
    private let inspector: any ResourceInspecting
    private let bookmarks: any BookmarkHandling

    init(
        store: any ProjectStoring,
        inspector: (any ResourceInspecting)? = nil,
        bookmarks: (any BookmarkHandling)? = nil
    ) {
        self.store = store
        self.inspector = inspector ?? LiveResourceInspector()
        self.bookmarks = bookmarks ?? SecurityBookmarkService()
    }

    func importResource(at url: URL) throws -> ImportOutcome {
        let resource: InspectedResource
        do {
            resource = try inspector.inspect(url: url)
        } catch let error as ResourceInspectionError {
            switch error {
            case .missingOrUnreadable(let path):
                throw ImportError.resourceUnavailable(path: path)
            case .unsupportedResource(let path, let detail):
                throw ImportError.unsupportedResource(path: path, reason: detail)
            }
        }

        do {
            if let existing = try findExistingProject(matching: resource.identity) {
                return .duplicate(existing)
            }
        } catch {
            throw ImportError.duplicateCheckFailed(reason: error.localizedDescription)
        }

        let bookmarkData: Data
        do {
            bookmarkData = try bookmarks.createBookmark(for: url)
        } catch {
            throw ImportError.bookmarkCreationFailed(
                path: resource.presentationURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            let project = try Project(
                displayName: resource.displayName,
                resourceType: resource.resourceType,
                originalPath: resource.presentationURL.path,
                bookmarkData: bookmarkData
            )
            return .created(try store.create(project))
        } catch {
            throw ImportError.persistenceFailed(reason: error.localizedDescription)
        }
    }

    private func findExistingProject(matching identity: ResourceIdentity) throws -> Project? {
        for project in try store.fetchAll() {
            if let bookmark = bookmarks.resolveBookmark(project.bookmarkData) {
                let resolvedIdentity = inspector.identity(url: bookmark.url)
                if resolvedIdentity == identity {
                    return project
                }
            }
            if storedFallbackIdentity(for: project) == identity {
                return project
            }
        }
        return nil
    }

    private func storedFallbackIdentity(for project: Project) -> ResourceIdentity {
        let canonicalURL = URL(fileURLWithPath: project.originalPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        return ResourceIdentity(
            fileIdentifier: nil,
            volumeIdentifier: nil,
            canonicalPath: canonicalURL.path
        )
    }
}
