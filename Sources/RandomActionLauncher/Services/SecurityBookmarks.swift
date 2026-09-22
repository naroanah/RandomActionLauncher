import Foundation

struct ResolvedBookmark: Equatable, Sendable {
    let url: URL
    let isStale: Bool
}

protocol BookmarkHandling: AnyObject {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) -> ResolvedBookmark?
}

/// 安全作用域书签服务：在用户授权访问期间创建书签，解析时报告过期状态。
final class SecurityBookmarkService: BookmarkHandling {
    func createBookmark(for url: URL) throws -> Data {
        try withResourceAccess(to: url) {
            try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }

    func resolveBookmark(_ data: Data) -> ResolvedBookmark? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        return ResolvedBookmark(url: url, isStale: isStale)
    }
}
