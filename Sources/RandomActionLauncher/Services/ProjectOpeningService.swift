import AppKit
import Foundation

enum ProjectOpeningError: LocalizedError, Equatable {
    case systemRejected(path: String)

    var errorDescription: String? {
        switch self {
        case .systemRejected(let path):
            return "系统未能打开该资源：\(path)"
        }
    }
}

@MainActor
protocol ProjectOpening: AnyObject {
    /// 调用方保证该 URL 已解析，并在调用期间持有安全作用域访问。
    func open(_ url: URL) throws
}

@MainActor
final class NSWorkspaceProjectOpener: ProjectOpening {
    func open(_ url: URL) throws {
        guard NSWorkspace.shared.open(url) else {
            throw ProjectOpeningError.systemRejected(path: url.path)
        }
    }
}
