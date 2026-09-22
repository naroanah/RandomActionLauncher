import AppKit
import Foundation

enum ProjectOpeningError: LocalizedError, Equatable {
    case bookmarkUnavailable
    case systemRejected

    var errorDescription: String? {
        switch self {
        case .bookmarkUnavailable:
            return "项目引用已不可用。"
        case .systemRejected:
            return "系统未能打开该项目。"
        }
    }
}

@MainActor
protocol ProjectOpening: AnyObject {
    func open(_ project: Project) throws
}

@MainActor
final class NSWorkspaceProjectOpener: ProjectOpening {
    private let bookmarks: any BookmarkHandling

    init(bookmarks: any BookmarkHandling = SecurityBookmarkService()) {
        self.bookmarks = bookmarks
    }

    func open(_ project: Project) throws {
        guard let resolved = bookmarks.resolveBookmark(project.bookmarkData) else {
            throw ProjectOpeningError.bookmarkUnavailable
        }

        try withResourceAccess(to: resolved.url) {
            guard NSWorkspace.shared.open(resolved.url) else {
                throw ProjectOpeningError.systemRejected
            }
        }
    }
}
