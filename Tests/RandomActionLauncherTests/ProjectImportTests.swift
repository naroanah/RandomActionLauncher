import Foundation
import Testing
@testable import RandomActionLauncher

private struct StubError: LocalizedError, Error {
    var message: String
    var errorDescription: String? { message }
}

private final class FailureBookmarkService: BookmarkHandling {
    func createBookmark(for url: URL) throws -> Data {
        throw StubError(message: "授权创建被拒绝")
    }

    func resolveBookmark(_ data: Data) -> ResolvedBookmark? {
        nil
    }
}

@MainActor
private final class StubFailureStore: ProjectStoring {
    var fetchError: Error?
    var createError: Error?

    func fetchAll() throws -> [Project] {
        if let fetchError {
            throw fetchError
        }
        return []
    }

    func create(_ project: Project) throws -> Project {
        if let createError {
            throw createError
        }
        return project
    }
}

@MainActor
struct ProjectImportTests {
    private func makeRepository() throws -> ProjectRepository {
        ProjectRepository(container: try PersistenceContainerFactory.makeInMemoryContainer())
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("resource-content".utf8).write(to: url)
        return url
    }

    @Test func importFolderCreatesSingleProjectWithDefaults() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        _ = try makeFile(named: "lecture.mp4", in: directory)
        _ = try makeFile(named: "assignment.pdf", in: directory)
        let repository = try makeRepository()
        let service = ProjectImportService(store: repository)

        let outcome = try service.importResource(at: directory)

        guard case .created(let project) = outcome else {
            Issue.record("应当创建一个项目")
            return
        }
        #expect(project.displayName == directory.lastPathComponent)
        #expect(project.resourceType == .folder)
        #expect(project.originalPath == directory.standardizedFileURL.path)
        #expect(project.status == .active)
        #expect(project.weight == .medium)
        #expect(project.availability == .available)
        #expect(project.bookmarkData.isEmpty == false)
        #expect(try repository.fetchAll().count == 1)
    }

    @Test func importClassifiesVideoAndDocument() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let videoURL = try makeFile(named: "lecture.mp4", in: directory)
        let documentURL = try makeFile(named: "report.pdf", in: directory)
        let repository = try makeRepository()
        let service = ProjectImportService(store: repository)

        guard case .created(let video) = try service.importResource(at: videoURL) else {
            Issue.record("视频应当创建项目")
            return
        }
        guard case .created(let document) = try service.importResource(at: documentURL) else {
            Issue.record("文档应当创建项目")
            return
        }

        #expect(video.resourceType == .video)
        #expect(document.resourceType == .document)
        #expect(try repository.fetchAll().count == 2)
    }

    @Test func importingSameResourceTwiceReturnsExistingProject() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "course.mp4", in: directory)
        let repository = try makeRepository()
        let service = ProjectImportService(store: repository)

        guard case .created(let first) = try service.importResource(at: url) else {
            Issue.record("首次导入应当创建项目")
            return
        }
        let secondOutcome = try service.importResource(at: url)

        guard case .duplicate(let existing) = secondOutcome else {
            Issue.record("重复导入应当返回已有项目")
            return
        }
        #expect(existing.id == first.id)
        #expect(try repository.fetchAll().count == 1)
    }

    @Test func duplicateDetectedThroughSymlink() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try makeFile(named: "target.pdf", in: directory)
        let link = directory.appendingPathComponent("alias.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let repository = try makeRepository()
        let service = ProjectImportService(store: repository)

        guard case .created(let first) = try service.importResource(at: target) else {
            Issue.record("首次导入应当创建项目")
            return
        }

        guard case .duplicate(let existing) = try service.importResource(at: link) else {
            Issue.record("符号链接应识别为重复资源")
            return
        }
        #expect(existing.id == first.id)
        #expect(try repository.fetchAll().count == 1)
    }

    @Test func sameDisplayNameDifferentResourcesAreBothImported() throws {
        let firstDirectory = try makeTemporaryDirectory()
        let secondDirectory = try makeTemporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstDirectory)
            try? FileManager.default.removeItem(at: secondDirectory)
        }
        let first = try makeFile(named: "同名项目.pdf", in: firstDirectory)
        let second = try makeFile(named: "同名项目.pdf", in: secondDirectory)
        let repository = try makeRepository()
        let service = ProjectImportService(store: repository)

        _ = try service.importResource(at: first)
        let secondOutcome = try service.importResource(at: second)

        guard case .created = secondOutcome else {
            Issue.record("不同资源不应被识别为重复")
            return
        }
        #expect(try repository.fetchAll().count == 2)
    }

    @Test func duplicateFallsBackToStoredPathWhenBookmarkUnresolvable() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "fallback.pdf", in: directory)
        let repository = try makeRepository()
        let stored = try Project(
            displayName: "既有项目",
            resourceType: .document,
            originalPath: url.standardizedFileURL.path,
            bookmarkData: Data([9, 9, 9])
        )
        try repository.create(stored)
        let service = ProjectImportService(store: repository)

        let outcome = try service.importResource(at: url)

        guard case .duplicate(let existing) = outcome else {
            Issue.record("书签不可解析时应按规范路径识别重复")
            return
        }
        #expect(existing.id == stored.id)
        #expect(try repository.fetchAll().count == 1)
    }

    @Test func missingResourceIsRejected() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.pdf")
        let service = ProjectImportService(store: try makeRepository())

        #expect(throws: ImportError.resourceUnavailable(path: missing.path)) {
            try service.importResource(at: missing)
        }
    }

    @Test func bookmarkFailureReportsAuthorizationError() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "authorized.pdf", in: directory)
        let service = ProjectImportService(
            store: try makeRepository(),
            bookmarks: FailureBookmarkService()
        )

        do {
            _ = try service.importResource(at: url)
            Issue.record("书签创建失败应当抛出错误")
        } catch let error as ImportError {
            guard case .bookmarkCreationFailed = error else {
                Issue.record("应当报告书签创建失败：\(error)")
                return
            }
        }
    }

    @Test func persistenceFailureReportsStorageError() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "persist.pdf", in: directory)
        let store = StubFailureStore()
        store.createError = StubError(message: "存储不可用")
        let service = ProjectImportService(store: store)

        do {
            _ = try service.importResource(at: url)
            Issue.record("存储失败应当抛出错误")
        } catch let error as ImportError {
            guard case .persistenceFailed = error else {
                Issue.record("应当报告存储失败：\(error)")
                return
            }
        }
    }

    @Test func fetchFailureReportsDuplicateCheckError() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "check.pdf", in: directory)
        let store = StubFailureStore()
        store.fetchError = StubError(message: "读取失败")
        let service = ProjectImportService(store: store)

        do {
            _ = try service.importResource(at: url)
            Issue.record("读取失败应当抛出错误")
        } catch let error as ImportError {
            guard case .duplicateCheckFailed = error else {
                Issue.record("应当报告重复检查失败：\(error)")
                return
            }
        }
    }

    @Test func modelImportsURLsAndReportsFeedback() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "managed.pdf", in: directory)
        let repository = try makeRepository()
        let model = ProjectManagerModel(
            store: repository,
            importService: ProjectImportService(store: repository)
        )

        #expect(model.projects.isEmpty)

        model.importURLs([url])

        #expect(model.projects.count == 1)
        #expect(model.feedback == .created(name: "managed.pdf"))

        model.importURLs([])
        #expect(model.projects.count == 1)
        #expect(model.feedback == .created(name: "managed.pdf"))

        model.importURLs([url])

        #expect(model.projects.count == 1)
        #expect(model.feedback == .duplicate(name: "managed.pdf"))
        #expect(model.highlightedProjectID == model.projects.first?.id)
    }
}
