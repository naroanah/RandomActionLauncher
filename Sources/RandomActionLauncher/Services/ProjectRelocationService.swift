import Foundation

enum ProjectRelocationError: LocalizedError, Equatable {
    case projectNotFound(UUID)
    case resourceUnavailable(path: String)
    case unsupportedResource(path: String, reason: String)
    case duplicateCheckFailed(reason: String)
    case bookmarkCreationFailed(path: String, reason: String)
    case persistenceFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "找不到项目记录：\(id.uuidString)。"
        case .resourceUnavailable(let path):
            return "资源不存在或无法读取：\(path)"
        case .unsupportedResource(let path, let reason):
            return "不支持的资源（\(reason)）：\(path)"
        case .duplicateCheckFailed(let reason):
            return "无法检查重复项目：\(reason)"
        case .bookmarkCreationFailed(let path, let reason):
            return "无法保存访问授权：\(reason)（\(path)）"
        case .persistenceFailed(let reason):
            return "保存重新定位结果失败：\(reason)"
        }
    }
}

enum ProjectRelocationOutcome: Equatable {
    case updated(Project)
    case duplicate(Project)
}

@MainActor
final class ProjectRelocationService {
    private let store: any ProjectManaging
    private let inspector: any ResourceInspecting
    private let bookmarks: any BookmarkHandling
    private let resourceMatcher: ProjectResourceMatcher

    init(
        store: any ProjectManaging,
        inspector: any ResourceInspecting = LiveResourceInspector(),
        bookmarks: any BookmarkHandling = SecurityBookmarkService()
    ) {
        self.store = store
        self.inspector = inspector
        self.bookmarks = bookmarks
        self.resourceMatcher = ProjectResourceMatcher(
            store: store,
            inspector: inspector,
            bookmarks: bookmarks
        )
    }

    func relocate(id: UUID, to url: URL) throws -> ProjectRelocationOutcome {
        guard try store.fetch(id: id) != nil else {
            throw ProjectRelocationError.projectNotFound(id)
        }

        let resource: InspectedResource
        do {
            resource = try inspector.inspect(url: url)
        } catch let error as ResourceInspectionError {
            switch error {
            case .missingOrUnreadable(let path):
                throw ProjectRelocationError.resourceUnavailable(path: path)
            case .unsupportedResource(let path, let detail):
                throw ProjectRelocationError.unsupportedResource(path: path, reason: detail)
            }
        } catch {
            throw ProjectRelocationError.resourceUnavailable(path: url.path)
        }

        do {
            if let existing = try resourceMatcher.findExistingProject(
                matching: resource.identity,
                excluding: id
            ) {
                return .duplicate(existing)
            }
        } catch {
            throw ProjectRelocationError.duplicateCheckFailed(reason: error.localizedDescription)
        }

        let bookmarkData: Data
        do {
            bookmarkData = try bookmarks.createBookmark(for: resource.presentationURL)
        } catch {
            throw ProjectRelocationError.bookmarkCreationFailed(
                path: resource.presentationURL.path,
                reason: error.localizedDescription
            )
        }

        do {
            let updated = try store.update(id: id) { project in
                project.resourceType = resource.resourceType
                project.originalPath = resource.presentationURL.path
                project.bookmarkData = bookmarkData
                project.availability = .available
            }
            return .updated(updated)
        } catch {
            throw ProjectRelocationError.persistenceFailed(reason: error.localizedDescription)
        }
    }
}
