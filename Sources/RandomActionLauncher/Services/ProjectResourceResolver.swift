import Foundation

struct ResolvedProjectResource: Equatable {
    let project: Project
    let url: URL
}

enum ProjectResourceResolution: Equatable {
    case available(ResolvedProjectResource)
    case unavailable(Project)
}

enum ProjectResourceResolutionError: LocalizedError, Equatable {
    case bookmarkRefreshFailed(path: String, reason: String)
    case persistenceFailed(projectID: UUID, reason: String)

    var errorDescription: String? {
        switch self {
        case .bookmarkRefreshFailed(let path, let reason):
            return "刷新资源访问授权失败：\(reason)（\(path)）"
        case .persistenceFailed(_, let reason):
            return "保存资源状态失败：\(reason)"
        }
    }
}

@MainActor
protocol ProjectResourceResolving: AnyObject {
    /// `operation` 只在资源已验证并完成必要持久化后执行，执行期间安全作用域保持开启。
    func resolve(
        _ project: Project,
        whileAccessing operation: (ResolvedProjectResource) throws -> Void
    ) throws -> ProjectResourceResolution
}

extension ProjectResourceResolving {
    func resolve(_ project: Project) throws -> ProjectResourceResolution {
        try resolve(project) { _ in }
    }
}

/// 解析、验证并修复项目资源。普通资源失效返回 unavailable；持久化失败则抛错。
@MainActor
final class ProjectResourceResolver: ProjectResourceResolving {
    private let store: any ProjectManaging
    private let inspector: any ResourceInspecting
    private let bookmarks: any BookmarkHandling

    init(
        store: any ProjectManaging,
        inspector: any ResourceInspecting = LiveResourceInspector(),
        bookmarks: any BookmarkHandling = SecurityBookmarkService()
    ) {
        self.store = store
        self.inspector = inspector
        self.bookmarks = bookmarks
    }

    func resolve(
        _ project: Project,
        whileAccessing operation: (ResolvedProjectResource) throws -> Void
    ) throws -> ProjectResourceResolution {
        guard let bookmark = bookmarks.resolveBookmark(project.bookmarkData) else {
            return try markUnavailable(project)
        }

        return try withResourceAccess(to: bookmark.url) {
            let inspected: InspectedResource
            do {
                inspected = try inspector.inspect(url: bookmark.url)
            } catch {
                return try markUnavailable(project)
            }

            let refreshedBookmarkData: Data
            if bookmark.isStale {
                do {
                    refreshedBookmarkData = try bookmarks.createBookmark(for: inspected.presentationURL)
                } catch {
                    throw ProjectResourceResolutionError.bookmarkRefreshFailed(
                        path: inspected.presentationURL.path,
                        reason: error.localizedDescription
                    )
                }
            } else {
                refreshedBookmarkData = project.bookmarkData
            }

            let resolvedProject = try persistAvailableResource(
                project,
                resource: inspected,
                bookmarkData: refreshedBookmarkData,
                forceSave: bookmark.isStale
            )
            let resolved = ResolvedProjectResource(
                project: resolvedProject,
                url: inspected.presentationURL
            )
            try operation(resolved)
            return .available(resolved)
        }
    }

    private func persistAvailableResource(
        _ project: Project,
        resource: InspectedResource,
        bookmarkData: Data,
        forceSave: Bool
    ) throws -> Project {
        let path = resource.presentationURL.path
        let needsSave = forceSave
            || project.originalPath != path
            || project.bookmarkData != bookmarkData
            || project.resourceType != resource.resourceType
            || project.availability != .available

        guard needsSave else {
            return project
        }

        return try persist(projectID: project.id) { stored in
            stored.originalPath = path
            stored.bookmarkData = bookmarkData
            stored.resourceType = resource.resourceType
            stored.availability = .available
        }
    }

    private func markUnavailable(_ project: Project) throws -> ProjectResourceResolution {
        guard project.availability != .unavailable else {
            return .unavailable(project)
        }
        let updated = try persist(projectID: project.id) { stored in
            stored.availability = .unavailable
        }
        return .unavailable(updated)
    }

    private func persist(
        projectID: UUID,
        changes: (inout Project) throws -> Void
    ) throws -> Project {
        do {
            return try store.update(id: projectID, changes: changes)
        } catch {
            throw ProjectResourceResolutionError.persistenceFailed(
                projectID: projectID,
                reason: error.localizedDescription
            )
        }
    }
}

/// 仅为既有 S4/S5 单元测试和简单替身保留的适配器；生产依赖使用 ProjectResourceResolver。
@MainActor
final class CheckedProjectResourceResolver: ProjectResourceResolving {
    private let checker: any ProjectResourceChecking

    init(checker: any ProjectResourceChecking) {
        self.checker = checker
    }

    func resolve(
        _ project: Project,
        whileAccessing operation: (ResolvedProjectResource) throws -> Void
    ) throws -> ProjectResourceResolution {
        guard checker.isResourceAvailable(for: project) else {
            return .unavailable(project)
        }
        let resolved = ResolvedProjectResource(
            project: project,
            url: URL(fileURLWithPath: project.originalPath)
        )
        try operation(resolved)
        return .available(resolved)
    }
}
