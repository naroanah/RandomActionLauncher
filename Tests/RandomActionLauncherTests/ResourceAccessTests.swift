import Foundation
import Testing
@testable import RandomActionLauncher

struct ResourceAccessTests {
    private let inspector = LiveResourceInspector()
    private let bookmarks = SecurityBookmarkService()

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ResourceAccessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("resource-content".utf8).write(to: url)
        return url
    }

    @Test func inspectsFolderAsSingleFolderResource() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let resource = try inspector.inspect(url: directory)

        #expect(resource.resourceType == .folder)
        #expect(resource.displayName == directory.lastPathComponent)
        #expect(resource.presentationURL == directory.standardizedFileURL)
    }

    @Test func classifiesVideoAndDocumentFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let videoURL = try makeFile(named: "clip.mp4", in: directory)
        let documentURL = try makeFile(named: "report.pdf", in: directory)
        let plainURL = try makeFile(named: "notes.txt", in: directory)

        #expect(try inspector.inspect(url: videoURL).resourceType == .video)
        #expect(try inspector.inspect(url: documentURL).resourceType == .document)
        #expect(try inspector.inspect(url: plainURL).resourceType == .document)
    }

    @Test func rejectsAudioAndNonContentFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let audioURL = try makeFile(named: "recording.mp3", in: directory)
        let diskImageURL = try makeFile(named: "archive.dmg", in: directory)

        #expect(throws: ResourceInspectionError.self) {
            try inspector.inspect(url: audioURL)
        }
        #expect(throws: ResourceInspectionError.self) {
            try inspector.inspect(url: diskImageURL)
        }
    }

    @Test func missingResourceThrowsMissingOrUnreadable() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("missing.pdf")

        #expect(throws: ResourceInspectionError.missingOrUnreadable(path: missing.path)) {
            try inspector.inspect(url: missing)
        }
    }

    @Test func unreadableFileThrowsMissingOrUnreadable() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "secret.txt", in: directory)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }

        #expect(throws: ResourceInspectionError.missingOrUnreadable(path: url.path)) {
            try inspector.inspect(url: url)
        }
    }

    @Test func symlinkResolvesToTargetIdentity() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = try makeFile(named: "target.pdf", in: directory)
        let link = directory.appendingPathComponent("alias.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let inspected = try inspector.inspect(url: link)
        let targetInspected = try inspector.inspect(url: target)

        #expect(inspected.canonicalURL == targetInspected.canonicalURL)
        #expect(inspected.identity == targetInspected.identity)
    }

    @Test func differentFilesHaveDifferentIdentities() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeFile(named: "first.pdf", in: directory)
        let second = try makeFile(named: "second.pdf", in: directory)

        #expect(inspector.identity(url: first) != inspector.identity(url: second))
    }

    @Test func bookmarkRoundTripResolvesOriginalResource() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeFile(named: "bookmark.txt", in: directory)

        let data = try bookmarks.createBookmark(for: url)
        let resolved = try #require(bookmarks.resolveBookmark(data))

        #expect(resolved.isStale == false)
        #expect(inspector.identity(url: resolved.url) == inspector.identity(url: url))
    }

    @Test func invalidBookmarkDataFailsToResolve() {
        #expect(bookmarks.resolveBookmark(Data([1, 2, 3])) == nil)
    }

    @Test func bookmarkResolutionFollowsMovedFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceDirectory = directory.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = directory.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let url = try makeFile(named: "moving.txt", in: sourceDirectory)
        let movedURL = destinationDirectory.appendingPathComponent("moving.txt")

        let data = try bookmarks.createBookmark(for: url)
        try FileManager.default.moveItem(at: url, to: movedURL)
        let resolved = try #require(bookmarks.resolveBookmark(data))

        let resolvedCanonical = resolved.url.standardizedFileURL.resolvingSymlinksInPath().path
        let expectedCanonical = movedURL.standardizedFileURL.resolvingSymlinksInPath().path
        #expect(resolvedCanonical == expectedCanonical)
    }
}
