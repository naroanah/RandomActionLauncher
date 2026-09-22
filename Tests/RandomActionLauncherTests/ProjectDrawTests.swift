import Foundation
import Testing
@testable import RandomActionLauncher

private struct DrawStoreError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
private final class DrawStore: ProjectManaging {
    var values: [Project]
    var updateError: Error?
    private(set) var updateCallCount = 0

    init(values: [Project]) {
        self.values = values
    }

    func fetchAll() throws -> [Project] {
        values
    }

    @discardableResult
    func create(_ project: Project) throws -> Project {
        values.append(project)
        return project
    }

    func fetch(id: UUID) throws -> Project? {
        values.first { $0.id == id }
    }

    @discardableResult
    func update(id: UUID, changes: (inout Project) throws -> Void) throws -> Project {
        updateCallCount += 1
        if let updateError {
            throw updateError
        }
        guard let index = values.firstIndex(where: { $0.id == id }) else {
            throw ProjectManagementError.projectNotFound(id)
        }

        var updated = values[index]
        try changes(&updated)
        updated.updatedAt = .now
        values[index] = updated
        return updated
    }

    func delete(id: UUID) throws {
        values.removeAll { $0.id == id }
    }
}

@MainActor
private final class FixedProjectClock: ProjectClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class FixedTicketSource: ProjectTicketSource {
    let ticket: Int
    private(set) var requestedRanges: [Range<Int>] = []

    init(ticket: Int) {
        self.ticket = ticket
    }

    func nextTicket(in range: Range<Int>) -> Int {
        requestedRanges.append(range)
        return ticket
    }
}

@MainActor
private final class StubResourceChecker: ProjectResourceChecking {
    var availability: [UUID: Bool]
    private(set) var checkedIDs: [UUID] = []

    init(availability: [UUID: Bool] = [:]) {
        self.availability = availability
    }

    func isResourceAvailable(for project: Project) -> Bool {
        checkedIDs.append(project.id)
        return availability[project.id] ?? true
    }
}

@MainActor
private final class ReentrantResourceChecker: ProjectResourceChecking {
    var reentrantDraw: (() throws -> ProjectDrawResult)?
    private(set) var nestedResult: ProjectDrawResult?
    private var didReenter = false

    func isResourceAvailable(for project: Project) -> Bool {
        if !didReenter, let reentrantDraw {
            didReenter = true
            nestedResult = try? reentrantDraw()
        }
        return true
    }
}

@MainActor
struct ProjectDrawTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func id(_ suffix: String) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000\(suffix)"))
    }

    private func makeProject(
        _ name: String,
        id: UUID,
        status: ProjectStatus = .active,
        weight: ProjectWeight = .medium,
        availability: ProjectAvailability = .available,
        lastDrawnAt: Date? = nil,
        cooldownUntil: Date? = nil
    ) throws -> Project {
        try Project(
            displayName: name,
            resourceType: .document,
            originalPath: "/tmp/\(name).pdf",
            bookmarkData: Data([1, 2, 3]),
            status: status,
            weight: weight,
            createdAt: baseDate,
            updatedAt: baseDate,
            lastDrawnAt: lastDrawnAt,
            cooldownUntil: cooldownUntil,
            availability: availability,
            id: id
        )
    }

    private func makeService(
        store: DrawStore,
        clock: FixedProjectClock,
        ticketSource: ProjectTicketSource,
        resourceChecker: ProjectResourceChecking
    ) -> ProjectDrawService {
        ProjectDrawService(
            store: store,
            clock: clock,
            ticketSource: ticketSource,
            resourceChecker: resourceChecker
        )
    }

    @Test func filtersStatusCooldownAndRealtimeAvailability() throws {
        let now = baseDate.addingTimeInterval(100)
        let eligible = try makeProject("可抽取", id: id("01"))
        let paused = try makeProject("暂停", id: id("02"), status: .paused)
        let completed = try makeProject("完成", id: id("03"), status: .completed)
        let cooldownNotExpired = try makeProject(
            "冷却中",
            id: id("04"),
            cooldownUntil: now.addingTimeInterval(1)
        )
        let cooldownAtBoundary = try makeProject(
            "边界可抽取",
            id: id("05"),
            cooldownUntil: now
        )
        let unavailableCacheButRecovered = try makeProject(
            "缓存不可用但已恢复",
            id: id("06"),
            availability: .unavailable
        )
        let unavailableNow = try makeProject("实时不可用", id: id("07"))
        let store = DrawStore(values: [
            paused,
            unavailableNow,
            cooldownNotExpired,
            eligible,
            completed,
            unavailableCacheButRecovered,
            cooldownAtBoundary,
        ])
        let clock = FixedProjectClock(now: now)
        let tickets = FixedTicketSource(ticket: 0)
        let checker = StubResourceChecker(availability: [unavailableNow.id: false])
        let service = makeService(
            store: store,
            clock: clock,
            ticketSource: tickets,
            resourceChecker: checker
        )

        let result = try service.draw()

        guard case .selected(let selected) = result else {
            Issue.record("应从实时可访问候选中抽取项目")
            return
        }
        #expect(selected.id == eligible.id)
        #expect(Set(checker.checkedIDs) == Set([
            eligible.id,
            cooldownAtBoundary.id,
            unavailableCacheButRecovered.id,
            unavailableNow.id,
        ]))
        #expect(!checker.checkedIDs.contains(paused.id))
        #expect(!checker.checkedIDs.contains(completed.id))
        #expect(!checker.checkedIDs.contains(cooldownNotExpired.id))
        #expect(selected.id == eligible.id)
    }

    @Test func returnsExplicitNoEligibleResultWithoutWriting() throws {
        let now = baseDate.addingTimeInterval(100)
        let paused = try makeProject("暂停", id: id("11"), status: .paused)
        let completed = try makeProject("完成", id: id("12"), status: .completed)
        let cooldown = try makeProject(
            "冷却中",
            id: id("13"),
            cooldownUntil: now.addingTimeInterval(1)
        )
        let unavailable = try makeProject("不可用", id: id("14"))
        let store = DrawStore(values: [paused, completed, cooldown, unavailable])
        let checker = StubResourceChecker(availability: [unavailable.id: false])
        let service = makeService(
            store: store,
            clock: FixedProjectClock(now: now),
            ticketSource: FixedTicketSource(ticket: 0),
            resourceChecker: checker
        )

        #expect(try service.draw() == .noEligibleProjects)
        #expect(store.updateCallCount == 0)
    }

    @Test func mapsWeightIntervalsToExpectedTicketBoundaries() throws {
        let lowID = try id("21")
        let mediumID = try id("22")
        let highID = try id("23")
        let low = try makeProject("低", id: lowID, weight: .low)
        let medium = try makeProject("中", id: mediumID, weight: .medium)
        let high = try makeProject("高", id: highID, weight: .high)
        let expectedIDs = [lowID, mediumID, mediumID, highID, highID, highID]

        for (ticket, expectedID) in expectedIDs.enumerated() {
            let store = DrawStore(values: [high, low, medium])
            let ticketSource = FixedTicketSource(ticket: ticket)
            let service = makeService(
                store: store,
                clock: FixedProjectClock(now: baseDate),
                ticketSource: ticketSource,
                resourceChecker: StubResourceChecker()
            )

            guard case .selected(let selected) = try service.draw() else {
                Issue.record("票号 \(ticket) 应选中项目")
                continue
            }
            #expect(selected.id == expectedID)
            #expect(ticketSource.requestedRanges == [0..<6])
        }
    }

    @Test func fixedTicketIsIndependentOfRepositoryOrder() throws {
        let firstID = try id("31")
        let secondID = try id("32")
        let first = try makeProject("第一个", id: firstID, weight: .low)
        let second = try makeProject("第二个", id: secondID, weight: .high)
        let firstStore = DrawStore(values: [second, first])
        let secondStore = DrawStore(values: [first, second])

        let firstService = makeService(
            store: firstStore,
            clock: FixedProjectClock(now: baseDate),
            ticketSource: FixedTicketSource(ticket: 1),
            resourceChecker: StubResourceChecker()
        )
        let secondService = makeService(
            store: secondStore,
            clock: FixedProjectClock(now: baseDate),
            ticketSource: FixedTicketSource(ticket: 1),
            resourceChecker: StubResourceChecker()
        )

        guard case .selected(let firstResult) = try firstService.draw(),
              case .selected(let secondResult) = try secondService.draw() else {
            Issue.record("相同项目集合应都能抽取")
            return
        }
        #expect(firstResult.id == secondResult.id)
        #expect(firstResult.id == secondID)
    }

    @Test func selectedProjectPersistsExactDrawAndCooldownTimes() throws {
        let now = Date(timeIntervalSince1970: 1_700_123_456)
        let project = try makeProject("时间项目", id: id("41"))
        let store = DrawStore(values: [project])
        let service = makeService(
            store: store,
            clock: FixedProjectClock(now: now),
            ticketSource: FixedTicketSource(ticket: 0),
            resourceChecker: StubResourceChecker()
        )

        guard case .selected(let selected) = try service.draw() else {
            Issue.record("应交付已保存的抽取结果")
            return
        }
        let saved = try #require(try store.fetch(id: project.id))
        #expect(selected == saved)
        #expect(saved.lastDrawnAt == now)
        #expect(saved.cooldownUntil == now.addingTimeInterval(86_400))
        #expect(saved.cooldownUntil!.timeIntervalSince(saved.lastDrawnAt!) == 86_400)
        #expect(store.updateCallCount == 1)
    }

    @Test func saveFailureDoesNotDeliverResultOrChangeStoredProject() throws {
        let project = try makeProject("保存失败", id: id("51"))
        let store = DrawStore(values: [project])
        let savedBefore = store.values
        store.updateError = DrawStoreError(message: "模拟保存失败")
        let service = makeService(
            store: store,
            clock: FixedProjectClock(now: baseDate),
            ticketSource: FixedTicketSource(ticket: 0),
            resourceChecker: StubResourceChecker()
        )

        #expect(throws: ProjectDrawError.saveFailed(reason: "模拟保存失败")) {
            try service.draw()
        }
        #expect(store.values == savedBefore)
        #expect(store.updateCallCount == 1)
    }

    @Test func cooldownUsesAbsoluteDateWhenClockMovesBackward() throws {
        let lastDrawnAt = baseDate.addingTimeInterval(200)
        let cooldownUntil = baseDate.addingTimeInterval(300)
        let project = try makeProject(
            "绝对时间",
            id: id("61"),
            lastDrawnAt: lastDrawnAt,
            cooldownUntil: cooldownUntil
        )
        let store = DrawStore(values: [project])
        let clock = FixedProjectClock(now: baseDate.addingTimeInterval(150))
        let service = makeService(
            store: store,
            clock: clock,
            ticketSource: FixedTicketSource(ticket: 0),
            resourceChecker: StubResourceChecker()
        )

        #expect(try service.draw() == .noEligibleProjects)
        clock.now = cooldownUntil
        guard case .selected(let selected) = try service.draw() else {
            Issue.record("now 等于 cooldownUntil 时应恢复候选资格")
            return
        }
        #expect(selected.id == project.id)
    }

    @Test func reentrantDrawIsRejectedBeforeAnySecondWrite() throws {
        let project = try makeProject("重入保护", id: id("71"))
        let store = DrawStore(values: [project])
        let checker = ReentrantResourceChecker()
        let service = makeService(
            store: store,
            clock: FixedProjectClock(now: baseDate),
            ticketSource: FixedTicketSource(ticket: 0),
            resourceChecker: checker
        )
        checker.reentrantDraw = { try service.draw() }

        guard case .selected(let selected) = try service.draw() else {
            Issue.record("外层抽取应正常完成")
            return
        }
        #expect(selected.id == project.id)
        #expect(checker.nestedResult == .operationInProgress)
        #expect(store.updateCallCount == 1)
    }
}
