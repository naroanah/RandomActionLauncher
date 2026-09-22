import Foundation
import UniformTypeIdentifiers

/// 资源的稳定标识：优先使用文件系统资源标识，缺失时退化为规范路径比较。
struct ResourceIdentity: Equatable, Sendable {
    let fileIdentifier: Data?
    let volumeIdentifier: Data?
    let canonicalPath: String

    static func == (lhs: ResourceIdentity, rhs: ResourceIdentity) -> Bool {
        switch (lhs.fileIdentifier, rhs.fileIdentifier) {
        case let (lhsIdentifier?, rhsIdentifier?):
            if let lhsVolume = lhs.volumeIdentifier, let rhsVolume = rhs.volumeIdentifier {
                return lhsIdentifier == rhsIdentifier && lhsVolume == rhsVolume
            }
            return lhsIdentifier == rhsIdentifier
        default:
            return lhs.canonicalPath == rhs.canonicalPath
        }
    }
}

/// 检查后的资源信息，包含展示、分类和去重所需的数据。
struct InspectedResource: Equatable, Sendable {
    let presentationURL: URL
    let canonicalURL: URL
    let displayName: String
    let resourceType: ProjectResourceType
    let identity: ResourceIdentity
}

enum ResourceInspectionError: LocalizedError, Equatable {
    case missingOrUnreadable(path: String)
    case unsupportedResource(path: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .missingOrUnreadable(let path):
            return "资源不存在或当前无法读取：\(path)"
        case .unsupportedResource(let path, let detail):
            return "不支持的资源（\(detail)）：\(path)"
        }
    }
}

/// 在安全作用域访问窗口内执行操作，保证开始和结束访问成对出现。
func withResourceAccess<R>(to url: URL, _ body: () throws -> R) rethrows -> R {
    let didBeginAccess = url.startAccessingSecurityScopedResource()
    defer {
        if didBeginAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
    return try body()
}

protocol ResourceInspecting: AnyObject {
    /// 完整检查资源：存在性、可读性、类型分类、展示名称和稳定标识。
    func inspect(url: URL) throws -> InspectedResource
    /// 尽力提取稳定标识；资源不可访问时退化为规范路径标识。
    func identity(url: URL) -> ResourceIdentity
}

final class LiveResourceInspector: ResourceInspecting {
    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isReadableKey,
        .typeIdentifierKey,
        .fileResourceIdentifierKey,
        .volumeIdentifierKey,
    ]

    func inspect(url: URL) throws -> InspectedResource {
        let presentationURL = url.standardizedFileURL
        // 符号链接本身不是常规文件或文件夹，先解析到真实资源再读取元数据。
        let canonicalURL = presentationURL.resolvingSymlinksInPath()

        let values: URLResourceValues
        do {
            values = try resourceValues(for: canonicalURL)
        } catch {
            throw ResourceInspectionError.missingOrUnreadable(path: url.path)
        }

        guard values.isReadable == true else {
            throw ResourceInspectionError.missingOrUnreadable(path: url.path)
        }

        let resourceType: ProjectResourceType
        if values.isDirectory == true {
            resourceType = .folder
        } else if values.isRegularFile == true {
            resourceType = try classifyFile(values: values, path: url.path)
        } else {
            throw ResourceInspectionError.unsupportedResource(
                path: url.path,
                detail: "既不是常规文件也不是文件夹"
            )
        }

        return InspectedResource(
            presentationURL: presentationURL,
            canonicalURL: canonicalURL,
            displayName: preferredName(for: presentationURL),
            resourceType: resourceType,
            identity: makeIdentity(values: values, canonicalURL: canonicalURL)
        )
    }

    func identity(url: URL) -> ResourceIdentity {
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try? resourceValues(for: canonicalURL)
        return makeIdentity(values: values, canonicalURL: canonicalURL)
    }

    private func resourceValues(for url: URL) throws -> URLResourceValues {
        try withResourceAccess(to: url) {
            try url.resourceValues(forKeys: Self.resourceKeys)
        }
    }

    private func classifyFile(values: URLResourceValues, path: String) throws -> ProjectResourceType {
        guard let identifier = values.typeIdentifier, let type = UTType(identifier) else {
            throw ResourceInspectionError.unsupportedResource(
                path: path,
                detail: "无法识别文件类型"
            )
        }

        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return .video
        }
        if type.conforms(to: .audio) {
            throw ResourceInspectionError.unsupportedResource(
                path: path,
                detail: "音频文件不在支持范围内"
            )
        }
        guard type.conforms(to: .content) else {
            throw ResourceInspectionError.unsupportedResource(
                path: path,
                detail: "不是可添加的文档或视频"
            )
        }
        return .document
    }

    private func preferredName(for url: URL) -> String {
        let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名资源" : name
    }

    private func makeIdentity(values: URLResourceValues?, canonicalURL: URL) -> ResourceIdentity {
        ResourceIdentity(
            fileIdentifier: identifierData(values?.fileResourceIdentifier),
            volumeIdentifier: identifierData(values?.volumeIdentifier),
            canonicalPath: canonicalURL.path
        )
    }

    private func identifierData(_ identifier: (any NSCopying & NSSecureCoding & NSObjectProtocol)?) -> Data? {
        if let data = identifier as? Data {
            return data
        }
        guard let identifier else { return nil }
        return try? NSKeyedArchiver.archivedData(
            withRootObject: identifier,
            requiringSecureCoding: true
        )
    }
}
