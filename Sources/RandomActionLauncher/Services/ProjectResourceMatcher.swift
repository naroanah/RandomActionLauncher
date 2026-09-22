import Foundation

/// 导入与重新定位共用的规范资源重复匹配。
@MainActor
final class ProjectResourceMatcher {
    private let store: any ProjectStoring
    private let inspector: any ResourceInspecting
    private let bookmarks: any BookmarkHandling

    init(
        store: any ProjectStoring,
        inspector: any ResourceInspecting,
        bookmarks: any BookmarkHandling
    ) {
        self.store = store
        self.inspector = inspector
        self.bookmarks = bookmarks
    }

    func findExistingProject(
        matching identity: ResourceIdentity,
        excluding excludedID: UUID? = nil
    ) throws -> Project? {
        for project in try store.fetchAll() where project.id != excludedID {
            if let bookmark = bookmarks.resolveBookmark(project.bookmarkData) {
                let resolvedIdentity = withResourceAccess(to: bookmark.url) {
                    inspector.identity(url: bookmark.url)
                }
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
