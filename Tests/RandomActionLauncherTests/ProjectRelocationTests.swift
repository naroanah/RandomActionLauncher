import Foundation
import Testing
@testable import RandomActionLauncher

private final class RelocationStubBookmarks: BookmarkHandling {
    var stored: [UUID: Data] = [:]
    var urls: [UUID: URL] = [:]
    var staleIDs: Set<UUID> = []

    func createBookmark(for url: URL) throws -> Data {
        Data("bookmark-\(url.path)".utf8)
    }

    func resolveBookmark(_ data: Data) -> ResolvedBookmark? {
        guard let entry = stored.first(where: { $0.value == data }) else {
            return nil
        }
        guard let url = urls[entry.key] else { return nil }
        return ResolvedBookmark(url: url, isStale: staleIDs.contains(entry.key))
    }
}

@MainActor
private final class RelocationClock: ProjectClock {
    let now: Date
    init(now: Date) { self.now = now }
}

@MainActor
private final class ZeroTicket: ProjectTicketSource {
    func nextTicket(in range: Range<Int>) -> Int { range.lowerBound }
}

@MainActor
struct ProjectRelocationTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRepository() throws -> ProjectRepository {
        ProjectRepository(container: try PersistenceContainerFactory.makeInMemoryContainer())
    }

    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectRelocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeProject(
        id: UUID,
        name: String = "测试项目",
        status: ProjectStatus = .active,
        availability: ProjectAvailability = .available,
        cooldownUntil: Date? = nil
    ) throws -> Project {
        try Project(
            displayName: name,
            note: "保留备注",
            resourceType: .document,
            originalPath: "/tmp/original-\(id.uuidString).pdf",
            bookmarkData: Data("bookmark-\(id.uuidString)".utf8),
            status: status,
            weight: .high,
            createdAt: baseDate,
            updatedAt: baseDate,
            lastDrawnAt: cooldownUntil.map { $0.addingTimeInterval(-86_400) },
            cooldownUntil: cooldownUntil,
            availability: availability,
            id: id
        )
    }

    @Test func resolverUpdatesMovedPathAndStaleBookmark() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let movedURL = directory.appendingPathComponent("moved.pdf")
        try Data("content".utf8).write(to: movedURL)

        let projectID = UUID()
        let repository = try makeRepository()
        let bookmarks = RelocationStubBookmarks()
        let original = try makeProject(id: projectID)
        try repository.create(original)
        bookmarks.stored[projectID] = original.bookmarkData
        bookmarks.urls[projectID] = movedURL
        bookmarks.staleIDs.insert(projectID)

        let resolver = ProjectResourceResolver(store: repository, bookmarks: bookmarks)
        let result = try resolver.resolve(original)

        guard case .available(let resource) = result else {
            Issue.record("移动后的资源应解析为可用")
            return
        }
        #expect(resource.project.originalPath == movedURL.standardizedFileURL.path)
        #expect(resource.project.availability == .available)
        #expect(resource.project.bookmarkData != original.bookmarkData)
    }

    @Test func resolverMarksUnresolvableProjectUnavailableAndKeepsFields() throws {
        let projectID = UUID()
        let repository = try makeRepository()
        let bookmarks = RelocationStubBookmarks()
        let cooldown = baseDate.addingTimeInterval(3600)
        let original = try makeProject(
            id: projectID,
            status: .paused,
            cooldownUntil: cooldown
        )
        try repository.create(original)
        bookmarks.stored[projectID] = original.bookmarkData
        bookmarks.urls[projectID] = URL(fileURLWithPath: "/nonexistent/missing.pdf")

        let resolver = ProjectResourceResolver(store: repository, bookmarks: bookmarks)
        let result = try resolver.resolve(original)

        guard case .unavailable = result else {
            Issue.record("不可解析资源应返回 unavailable")
            return
        }
        let saved = try #require(try repository.fetch(id: projectID))
        #expect(saved.availability == .unavailable)
        #expect(saved.status == .paused)
        #expect(saved.cooldownUntil == cooldown)
        #expect(saved.note == "保留备注")
    }

    @Test func resolverRecoversPreviouslyUnavailableProject() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recovered.pdf")
        try Data("content".utf8).write(to: url)

        let projectID = UUID()
        let repository = try makeRepository()
        let bookmarks = RelocationStubBookmarks()
        let original = try makeProject(id: projectID, availability: .unavailable)
        try repository.create(original)
        bookmarks.stored[projectID] = original.bookmarkData
        bookmarks.urls[projectID] = url

        let resolver = ProjectResourceResolver(store: repository, bookmarks: bookmarks)
        let result = try resolver.resolve(original)

        guard case .available(let resource) = result else {
            Issue.record("磁盘恢复后应重新可用")
            return
        }
        #expect(resource.project.availability == .available)
        #expect(try repository.fetch(id: projectID)?.availability == .available)
    }

    @Test func drawSkipsInvalidAndSelectsOtherCandidate() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let validURL = directory.appendingPathComponent("valid.pdf")
        try Data("content".utf8).write(to: validURL)

        let invalidID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let validID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let repository = try makeRepository()
        let bookmarks = RelocationStubBookmarks()
        let invalid = try makeProject(id: invalidID)
        let valid = try makeProject(id: validID)
        try repository.create(invalid)
        try repository.create(valid)
        bookmarks.stored[invalidID] = invalid.bookmarkData
        bookmarks.urls[invalidID] = URL(fileURLWithPath: "/missing.pdf")
        bookmarks.stored[validID] = valid.bookmarkData
        bookmarks.urls[validID] = validURL

        let resolver = ProjectResourceResolver(store: repository, bookmarks: bookmarks)
        let service = ProjectDrawService(
            store: repository,
            clock: RelocationClock(now: baseDate),
            ticketSource: ZeroTicket(),
            resourceResolver: resolver
        )

        guard case .selected(let selected) = try service.draw() else {
            Issue.record("失效项目应被跳过并选中其他候选")
            return
        }
        #expect(selected.id == validID)
        #expect(try repository.fetch(id: invalidID)?.availability == .unavailable)
    }

    @Test func relocationUpdatesResourceAndKeepsProjectFields() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let newURL = directory.appendingPathComponent("new-home.pdf")
        try Data("new".utf8).write(to: newURL)

        let projectID = UUID()
        let repository = try makeRepository()
        let bookmarks = RelocationStubBookmarks()
        let cooldown = baseDate.addingTimeInterval(7200)
        let original = try makeProject(id: projectID, status: .paused, cooldownUntil: cooldown)
        try repository.create(original)

        let service = ProjectRelocationService(store: repository, bookmarks: bookmarks)
        guard case .updated(let updated) = try service.relocate(id: projectID, to: newURL) else {
            Issue.record("重新定位应更新项目")
            return
        }

        #expect(updated.id == projectID)
        #expect(updated.status == .paused)
        #expect(updated.cooldownUntil == cooldown)
        #expect(updated.displayName == original.displayName)
        #expect(updated.note == original.note)
        #expect(updated.weight == original.weight)
        #expect(updated.originalPath == newURL.standardizedFileURL.path)
        #expect(updated.availability == .available)
        #expect(updated.bookmarkData != original.bookmarkData)
    }

    @Test func relocationRejectsDuplicateAndPreservesOriginal() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("duplicate.pdf")
        try Data("dup".utf8).write(to: url)

        let projectID = UUID()
        let otherID = UUID()
        let repository = try makeRepository()
        let bookmarks = RelocationStubBookmarks()
        let project = try makeProject(id: projectID)
        let other = try makeProject(id: otherID, name: "其他项目")
        try repository.create(project)
        try repository.create(other)
        bookmarks.stored[otherID] = other.bookmarkData
        bookmarks.urls[otherID] = url

        let service = ProjectRelocationService(store: repository, bookmarks: bookmarks)
        let outcome = try service.relocate(id: projectID, to: url)

        guard case .duplicate(let existing) = outcome else {
            Issue.record("重复资源应返回已有项目")
            return
        }
        #expect(existing.id == otherID)
        let saved = try #require(try repository.fetch(id: projectID))
        #expect(saved.originalPath == project.originalPath)
        #expect(saved.bookmarkData == project.bookmarkData)
    }

    @Test func relocationFailurePreservesOriginal() throws {
        let projectID = UUID()
        let repository = try makeRepository()
        let bookmarks = RelocationStubBookmarks()
        let original = try makeProject(id: projectID, availability: .unavailable)
        try repository.create(original)

        let service = ProjectRelocationService(store: repository, bookmarks: bookmarks)
        let missingURL = URL(fileURLWithPath: "/definitely/missing/file.pdf")
        #expect(throws: ProjectRelocationError.self) {
            _ = try service.relocate(id: projectID, to: missingURL)
        }

        let saved = try #require(try repository.fetch(id: projectID))
        #expect(saved == original)
    }
}
