import Foundation
import Testing
@testable import RandomActionLauncher

@MainActor
private final class SessionClock: ProjectClock {
    var now: Date
    init(now: Date) { self.now = now }
}

@MainActor
struct DrawSessionTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRepository() throws -> DrawSessionRepository {
        DrawSessionRepository(
            container: try PersistenceContainerFactory.makeInMemoryContainer()
        )
    }

    private func makeService(
        repository: DrawSessionRepository,
        now: Date
    ) -> DrawSessionService {
        DrawSessionService(store: repository, clock: SessionClock(now: now))
    }

    @Test func newSessionHasCorrectDefaults() throws {
        let repository = try makeRepository()
        let service = makeService(repository: repository, now: start)

        let session = try service.startIfNeeded()

        #expect(session.rerollCount == 0)
        #expect(session.didClickOpen == false)
        #expect(session.openedProjectId == nil)
        #expect(session.openedAt == nil)
        #expect(session.timeToOpenMs == nil)
        #expect(session.endedAt == nil)
        #expect(try repository.fetch(id: session.id) == session)
    }

    @Test func rerollIncrementsCount() throws {
        let repository = try makeRepository()
        let service = makeService(repository: repository, now: start)
        _ = try service.startIfNeeded()

        try service.recordReroll()
        try service.recordReroll()
        try service.recordReroll()

        let session = try #require(service.activeSession)
        #expect(session.rerollCount == 3)
        #expect(try repository.fetch(id: session.id)?.rerollCount == 3)
    }

    @Test func successfulOpenComputesNonNegativeElapsedAndEndsSession() throws {
        let repository = try makeRepository()
        let clock = SessionClock(now: start)
        let service = DrawSessionService(store: repository, clock: clock)
        _ = try service.startIfNeeded()

        let projectID = UUID()
        clock.now = start.addingTimeInterval(2.5)
        try service.recordOpenClick(projectID: projectID)
        try service.recordSuccessfulOpen(projectID: projectID)

        #expect(service.activeSession == nil)
        let session = try #require(try repository.fetchAll().first)
        #expect(session.didClickOpen == true)
        #expect(session.openedProjectId == projectID)
        #expect(session.openedAt == start.addingTimeInterval(2.5))
        #expect(session.timeToOpenMs == 2500)
        #expect(session.endedAt == start.addingTimeInterval(2.5))
    }

    @Test func failedOpenKeepsResultFieldsAndAllowsRetry() throws {
        let repository = try makeRepository()
        let clock = SessionClock(now: start)
        let service = DrawSessionService(store: repository, clock: clock)
        _ = try service.startIfNeeded()
        let projectID = UUID()

        try service.recordOpenClick(projectID: projectID)

        let session = try #require(service.activeSession)
        #expect(session.didClickOpen == true)
        #expect(session.openedProjectId == nil)
        #expect(session.timeToOpenMs == nil)

        clock.now = start.addingTimeInterval(4)
        try service.recordSuccessfulOpen(projectID: projectID)
        let saved = try #require(try repository.fetch(id: session.id))
        #expect(saved.timeToOpenMs == 4000)
    }

    @Test func clockBackwardsStillProducesNonNegativeDuration() throws {
        let repository = try makeRepository()
        let clock = SessionClock(now: start)
        let service = DrawSessionService(store: repository, clock: clock)
        _ = try service.startIfNeeded()

        clock.now = start.addingTimeInterval(-100)
        try service.recordSuccessfulOpen(projectID: UUID())

        let session = try #require(try repository.fetchAll().first)
        #expect(session.timeToOpenMs == 0)
    }

    @Test func endRecordsTimeAndClearsActiveState() throws {
        let repository = try makeRepository()
        let clock = SessionClock(now: start)
        let service = DrawSessionService(store: repository, clock: clock)
        _ = try service.startIfNeeded()

        clock.now = start.addingTimeInterval(10)
        try service.end()

        #expect(service.activeSession == nil)
        let session = try #require(try repository.fetchAll().first)
        #expect(session.endedAt == start.addingTimeInterval(10))
        #expect(session.didClickOpen == false)
    }

    @Test func secondDrawAfterResetCreatesNewSession() throws {
        let repository = try makeRepository()
        let clock = SessionClock(now: start)
        let service = DrawSessionService(store: repository, clock: clock)
        _ = try service.startIfNeeded()
        try service.end()

        clock.now = start.addingTimeInterval(30)
        let second = try service.startIfNeeded()

        #expect(second.startedAt == start.addingTimeInterval(30))
        #expect(try repository.fetchAll().count == 2)
    }

    @Test func deletingProjectRemovesAssociatedSessionsOnly() throws {
        let container = try PersistenceContainerFactory.makeInMemoryContainer()
        let projectStore = ProjectRepository(container: container)
        let sessionStore = DrawSessionRepository(container: container)

        let targetID = UUID()
        let otherID = UUID()
        let target = try Project(
            displayName: "目标",
            resourceType: .document,
            originalPath: "/tmp/target.pdf",
            id: targetID
        )
        let other = try Project(
            displayName: "其他",
            resourceType: .document,
            originalPath: "/tmp/other.pdf",
            id: otherID
        )
        try projectStore.create(target)
        try projectStore.create(other)

        let session1 = DrawSession(startedAt: start)
        _ = try sessionStore.create(session1)
        try sessionStore.recordDisplayedProject(sessionID: session1.id, projectID: targetID)
        try sessionStore.recordDisplayedProject(sessionID: session1.id, projectID: otherID)

        let session2 = DrawSession(startedAt: start.addingTimeInterval(10))
        _ = try sessionStore.create(session2)
        try sessionStore.recordDisplayedProject(sessionID: session2.id, projectID: otherID)

        try sessionStore.deleteSessions(associatedWith: targetID)

        #expect(try sessionStore.fetch(id: session1.id) == nil)
        #expect(try sessionStore.fetch(id: session2.id) != nil)
        #expect(try projectStore.fetch(id: otherID) != nil)
    }

    @Test func sessionPersistsAfterRepositoryRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DrawSessionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("sessions.sqlite")

        let sessionID: UUID
        do {
            let repository = DrawSessionRepository(
                container: try PersistenceContainerFactory.makeDiskContainer(at: storeURL)
            )
            let session = try repository.create(DrawSession(startedAt: start))
            sessionID = session.id
            try repository.recordDisplayedProject(sessionID: session.id, projectID: UUID())
        }

        let recreated = DrawSessionRepository(
            container: try PersistenceContainerFactory.makeDiskContainer(at: storeURL)
        )
        let loaded = try #require(try recreated.fetch(id: sessionID))
        #expect(loaded.startedAt == start)
        #expect(loaded.rerollCount == 0)
    }
}
