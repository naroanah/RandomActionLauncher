import Foundation

@MainActor
protocol DrawSessionStoring: AnyObject {
    @discardableResult
    func create(_ session: DrawSession) throws -> DrawSession
    func fetch(id: UUID) throws -> DrawSession?
    @discardableResult
    func update(id: UUID, changes: (inout DrawSession) throws -> Void) throws -> DrawSession
    func recordDisplayedProject(sessionID: UUID, projectID: UUID) throws
    func deleteSessions(associatedWith projectID: UUID) throws
}

extension DrawSessionRepository: DrawSessionStoring {}

@MainActor
final class DrawSessionService {
    private let store: any DrawSessionStoring
    private let clock: any ProjectClock
    private(set) var activeSession: DrawSession?

    init(store: any DrawSessionStoring, clock: any ProjectClock) {
        self.store = store
        self.clock = clock
    }

    @discardableResult
    func startIfNeeded() throws -> DrawSession {
        if let activeSession {
            return activeSession
        }
        let session = try store.create(DrawSession(startedAt: clock.now))
        activeSession = session
        return session
    }

    func recordDisplayed(projectID: UUID) throws {
        guard let session = activeSession else { return }
        try store.recordDisplayedProject(sessionID: session.id, projectID: projectID)
    }

    func recordReroll() throws {
        guard let session = activeSession else { return }
        let updated = try store.update(id: session.id) { session in
            session.rerollCount += 1
        }
        activeSession = updated
    }

    func recordOpenClick(projectID: UUID) throws {
        guard let session = activeSession else { return }
        let updated = try store.update(id: session.id) { session in
            session.didClickOpen = true
        }
        activeSession = updated
    }

    func recordSuccessfulOpen(projectID: UUID) throws {
        guard let session = activeSession else { return }
        let clickTime = clock.now
        let elapsedMs = max(0, Int(clickTime.timeIntervalSince(session.startedAt) * 1000))
        _ = try store.update(id: session.id) { session in
            session.didClickOpen = true
            session.openedProjectId = projectID
            session.openedAt = clickTime
            session.timeToOpenMs = elapsedMs
            session.endedAt = clickTime
        }
        activeSession = nil
    }

    func end() throws {
        guard let session = activeSession else { return }
        _ = try store.update(id: session.id) { session in
            session.endedAt = clock.now
        }
        activeSession = nil
    }

    func resetInMemoryState() {
        activeSession = nil
    }
}
