import Foundation
import Testing
@testable import RandomActionLauncher

private struct CoordinatorTestError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
private final class CoordinatorStore: ProjectManaging {
    var values: [Project]
    var fetchError: Error?
    var updateError: Error?
    private(set) var updateCallCount = 0

    init(values: [Project]) {
        self.values = values
    }

    func fetchAll() throws -> [Project] {
        if let fetchError {
            throw fetchError
        }
        return values
    }

    @discardableResult
    func create(_ project: Project) throws -> Project {
        values.append(project)
        return project
    }

    func fetch(id: UUID) throws -> Project? {
        if let fetchError {
            throw fetchError
        }
        return values.first { $0.id == id }
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
private final class CoordinatorClock: ProjectClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class AlwaysFirstTicketSource: ProjectTicketSource {
    func nextTicket(in range: Range<Int>) -> Int {
        range.lowerBound
    }
}

@MainActor
private final class CoordinatorResourceChecker: ProjectResourceChecking {
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
private final class CoordinatorDrawStub: ProjectDrawing {
    var outcome: Result<ProjectDrawResult, Error>
    var onDraw: (() -> Void)?
    private(set) var drawCallCount = 0

    init(outcome: Result<ProjectDrawResult, Error>) {
        self.outcome = outcome
    }

    func draw() throws -> ProjectDrawResult {
        drawCallCount += 1
        onDraw?()
        return try outcome.get()
    }
}

@MainActor
private final class CoordinatorEmptyStateStub: ProjectEmptyStateClassifying {
    var outcome: Result<ProjectEmptyReason, Error>

    init(outcome: Result<ProjectEmptyReason, Error>) {
        self.outcome = outcome
    }

    func classify() throws -> ProjectEmptyReason {
        try outcome.get()
    }
}

@MainActor
private final class CoordinatorOpener: ProjectOpening {
    var error: Error?
    private(set) var openedProjects: [Project] = []

    func open(_ project: Project) throws {
        if let error {
            throw error
        }
        openedProjects.append(project)
    }
}

@MainActor
struct MenuBarCoordinatorTests {
    private let baseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func id(_ suffix: String) throws -> UUID {
        try #require(UUID(uuidString: "00000000-0000-0000-0000-0000000000\(suffix)"))
    }

    private func makeProject(
        _ name: String,
        id: UUID,
        status: ProjectStatus = .active,
        cooldownUntil: Date? = nil
    ) throws -> Project {
        try Project(
            displayName: name,
            note: "备注：\(name)",
            resourceType: .document,
            originalPath: "/tmp/\(name).pdf",
            bookmarkData: Data([1, 2, 3]),
            status: status,
            weight: .low,
            createdAt: baseDate,
            updatedAt: baseDate,
            cooldownUntil: cooldownUntil,
            id: id
        )
    }

    private func makeModel(
        drawOutcome: Result<ProjectDrawResult, Error>,
        store: CoordinatorStore,
        checker: CoordinatorResourceChecker,
        emptyOutcome: Result<ProjectEmptyReason, Error> = .success(.noProjects),
        opener: CoordinatorOpener = CoordinatorOpener()
    ) -> (MenuBarCoordinatorModel, CoordinatorOpener) {
        let model = MenuBarCoordinatorModel(
            drawService: CoordinatorDrawStub(outcome: drawOutcome),
            store: store,
            resourceChecker: checker,
            emptyStateClassifier: CoordinatorEmptyStateStub(outcome: emptyOutcome),
            projectOpener: opener
        )
        return (model, opener)
    }

    private func makeClassifiedModel(
        projects: [Project],
        now: Date,
        availability: [UUID: Bool] = [:]
    ) -> MenuBarCoordinatorModel {
        let store = CoordinatorStore(values: projects)
        let checker = CoordinatorResourceChecker(availability: availability)
        let clock = CoordinatorClock(now: now)
        let classifier = ProjectEmptyStateClassifier(
            store: store,
            clock: clock,
            resourceChecker: checker
        )
        return MenuBarCoordinatorModel(
            drawService: CoordinatorDrawStub(outcome: .success(.noEligibleProjects)),
            store: store,
            resourceChecker: checker,
            emptyStateClassifier: classifier,
            projectOpener: CoordinatorOpener()
        )
    }

    @Test func drawAndRerollUseLatestProjectsAndRespectCooldown() throws {
        let first = try makeProject("第一个", id: id("81"))
        let second = try makeProject("第二个", id: id("82"))
        let store = CoordinatorStore(values: [second, first])
        let clock = CoordinatorClock(now: baseDate)
        let checker = CoordinatorResourceChecker()
        let drawService = ProjectDrawService(
            store: store,
            clock: clock,
            ticketSource: AlwaysFirstTicketSource(),
            resourceChecker: checker
        )
        let classifier = ProjectEmptyStateClassifier(
            store: store,
            clock: clock,
            resourceChecker: checker
        )
        let model = MenuBarCoordinatorModel(
            drawService: drawService,
            store: store,
            resourceChecker: checker,
            emptyStateClassifier: classifier,
            projectOpener: CoordinatorOpener()
        )

        model.draw()
        #expect(model.currentResult?.id == first.id)

        model.reroll()
        #expect(model.currentResult?.id == second.id)
        #expect(store.updateCallCount == 2)

        model.reroll()
        #expect(model.state == .empty(.allActiveProjectsCooling))
    }

    @Test func busyProtectionRejectsReentrantDraw() throws {
        let project = try makeProject("重入项目", id: id("83"))
        let store = CoordinatorStore(values: [project])
        let checker = CoordinatorResourceChecker()
        let draw = CoordinatorDrawStub(outcome: .success(.selected(project)))
        let model = MenuBarCoordinatorModel(
            drawService: draw,
            store: store,
            resourceChecker: checker,
            emptyStateClassifier: CoordinatorEmptyStateStub(outcome: .success(.noProjects)),
            projectOpener: CoordinatorOpener()
        )
        var nestedState: MenuBarPanelState?
        draw.onDraw = {
            model.draw()
            nestedState = model.state
        }

        model.draw()

        #expect(nestedState == .operationInProgress)
        #expect(model.state == .result(project))
        #expect(draw.drawCallCount == 1)
    }

    @Test func drawErrorBecomesVisibleFeedback() throws {
        let store = CoordinatorStore(values: [])
        let checker = CoordinatorResourceChecker()
        let drawError = ProjectDrawError.saveFailed(reason: "模拟保存失败")
        let (model, _) = makeModel(
            drawOutcome: .failure(drawError),
            store: store,
            checker: checker
        )

        model.draw()

        guard case .error(let message, let result) = model.state else {
            Issue.record("抽取保存失败应显示错误状态")
            return
        }
        #expect(message.contains("模拟保存失败"))
        #expect(result == nil)
    }

    @Test func underlyingBusyResultDoesNotLeavePanelDisabled() throws {
        let store = CoordinatorStore(values: [])
        let checker = CoordinatorResourceChecker()
        let (model, _) = makeModel(
            drawOutcome: .success(.operationInProgress),
            store: store,
            checker: checker
        )

        model.draw()

        guard case .error(let message, let result) = model.state else {
            Issue.record("底层忙碌结果应转换为可恢复错误")
            return
        }
        #expect(message.contains("仍在进行"))
        #expect(result == nil)
        #expect(!model.isOperationInProgress)
    }

    @Test func distinguishesAllEmptyReasonsIncludingMixedCause() throws {
        let paused = try makeProject("暂停", id: id("91"), status: .paused)
        let completed = try makeProject("完成", id: id("92"), status: .completed)
        let cooling = try makeProject(
            "冷却",
            id: id("93"),
            cooldownUntil: baseDate.addingTimeInterval(10)
        )
        let unavailable = try makeProject("不可用", id: id("94"))

        let cases: [(ProjectEmptyReason, MenuBarCoordinatorModel)] = [
            (.noProjects, makeClassifiedModel(projects: [], now: baseDate)),
            (
                .noActiveProjects,
                makeClassifiedModel(projects: [paused, completed], now: baseDate)
            ),
            (
                .allActiveProjectsCooling,
                makeClassifiedModel(projects: [cooling], now: baseDate)
            ),
            (
                .allActiveProjectsUnavailable,
                makeClassifiedModel(
                    projects: [unavailable],
                    now: baseDate,
                    availability: [unavailable.id: false]
                )
            ),
            (
                .activeProjectsCoolingAndUnavailable,
                makeClassifiedModel(
                    projects: [cooling],
                    now: baseDate,
                    availability: [cooling.id: false]
                )
            ),
        ]

        for (expectedReason, model) in cases {
            model.draw()
            #expect(model.state == .empty(expectedReason))
        }
    }

    @Test func changedCandidateSetDoesNotMisreportUnavailablePaths() throws {
        let available = try makeProject("刚恢复的项目", id: id("95"))
        let model = makeClassifiedModel(projects: [available], now: baseDate)

        model.draw()

        #expect(model.state == .empty(.projectsChanged))
    }

    @Test func openSuccessDoesNotChangeProjectState() throws {
        let project = try makeProject("可打开项目", id: id("a1"))
        let store = CoordinatorStore(values: [project])
        let checker = CoordinatorResourceChecker()
        let (model, opener) = makeModel(
            drawOutcome: .success(.selected(project)),
            store: store,
            checker: checker
        )

        model.draw()
        model.openCurrentResult()

        #expect(model.state == .result(project))
        #expect(store.values == [project])
        #expect(opener.openedProjects.map(\.id) == [project.id])
    }

    @Test func openFailurePreservesResultForRetry() throws {
        let project = try makeProject("打开失败项目", id: id("a2"))
        let store = CoordinatorStore(values: [project])
        let opener = CoordinatorOpener()
        opener.error = CoordinatorTestError(message: "系统拒绝")
        let (model, _) = makeModel(
            drawOutcome: .success(.selected(project)),
            store: store,
            checker: CoordinatorResourceChecker(),
            opener: opener
        )

        model.draw()
        model.openCurrentResult()

        guard case .error(let message, let result) = model.state else {
            Issue.record("系统打开失败应保留结果卡片")
            return
        }
        #expect(message.contains("系统拒绝"))
        #expect(result == project)
    }

    @Test func invalidatedResultCannotBeOpened() throws {
        let project = try makeProject("结果项目", id: id("a3"))
        let scenarios: [([Project], [UUID: Bool])] = [
            ([], [:]),
            ([try makeProject("已暂停", id: project.id, status: .paused)], [:]),
            ([try makeProject("已完成", id: project.id, status: .completed)], [:]),
            ([project], [project.id: false]),
        ]

        for (savedProjects, availability) in scenarios {
            let store = CoordinatorStore(values: savedProjects)
            let opener = CoordinatorOpener()
            let (model, _) = makeModel(
                drawOutcome: .success(.selected(project)),
                store: store,
                checker: CoordinatorResourceChecker(availability: availability),
                opener: opener
            )
            model.draw()
            model.openCurrentResult()

            guard case .error(_, let result) = model.state else {
                Issue.record("失效结果必须显示反馈")
                continue
            }
            #expect(result == nil)
            #expect(opener.openedProjects.isEmpty)
        }
    }

    @Test func refreshInvalidatesResultAfterManagementChange() throws {
        let project = try makeProject("待管理项目", id: id("a4"))
        let store = CoordinatorStore(values: [project])
        let (model, _) = makeModel(
            drawOutcome: .success(.selected(project)),
            store: store,
            checker: CoordinatorResourceChecker()
        )

        model.draw()
        store.values[0].status = .paused
        model.refresh()

        guard case .error(_, let result) = model.state else {
            Issue.record("管理操作后的刷新应重新校验结果")
            return
        }
        #expect(result == nil)
    }

    @Test func resetReturnsToIdleAndEmptyNotesAreOmitted() throws {
        let project = try makeProject("复位项目", id: id("a5"))
        let store = CoordinatorStore(values: [project])
        let (model, _) = makeModel(
            drawOutcome: .success(.selected(project)),
            store: store,
            checker: CoordinatorResourceChecker()
        )

        model.draw()
        model.reset()

        #expect(model.state == .idle)
        #expect(MenuBarCoordinatorModel.visibleNote(from: "") == nil)
        #expect(MenuBarCoordinatorModel.visibleNote(from: " \n\t ") == nil)
        #expect(MenuBarCoordinatorModel.visibleNote(from: "有备注") == "有备注")
    }
}
