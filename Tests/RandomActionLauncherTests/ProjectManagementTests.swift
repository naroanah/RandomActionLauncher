import Foundation
import Testing
@testable import RandomActionLauncher

private struct ManagementStoreError: LocalizedError, Equatable {
    let message: String

    var errorDescription: String? { message }
}

@MainActor
private final class InMemoryManagementStore: ProjectManaging {
    var values: [Project]
    var updateError: Error?
    var deleteError: Error?

    init(values: [Project] = []) {
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
        if let deleteError {
            throw deleteError
        }
        guard values.contains(where: { $0.id == id }) else {
            throw ProjectManagementError.projectNotFound(id)
        }
        values.removeAll { $0.id == id }
    }
}

@MainActor
struct ProjectManagementTests {
    private func makeRepository() throws -> ProjectRepository {
        ProjectRepository(container: try PersistenceContainerFactory.makeInMemoryContainer())
    }

    private func makeProject(
        name: String,
        status: ProjectStatus = .active,
        updatedAt: Date,
        lastDrawnAt: Date? = nil,
        cooldownUntil: Date? = nil
    ) throws -> Project {
        try Project(
            displayName: name,
            note: "原始备注",
            resourceType: .document,
            originalPath: "/tmp/\(name).pdf",
            bookmarkData: Data([1, 2, 3]),
            status: status,
            weight: .medium,
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            lastDrawnAt: lastDrawnAt,
            cooldownUntil: cooldownUntil
        )
    }

    private func makeModel(store: any ProjectManaging) -> ProjectManagerModel {
        ProjectManagerModel(
            store: store,
            importService: ProjectImportService(store: store)
        )
    }

    @Test func groupsByStatusAndSortsUpdatedAtDescending() throws {
        let repository = try makeRepository()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let activeOld = try makeProject(name: "进行中旧", updatedAt: base)
        let activeNew = try makeProject(
            name: "进行中新",
            updatedAt: base.addingTimeInterval(20)
        )
        let paused = try makeProject(
            name: "暂停项目",
            status: .paused,
            updatedAt: base.addingTimeInterval(10)
        )
        let completed = try makeProject(
            name: "完成项目",
            status: .completed,
            updatedAt: base.addingTimeInterval(30)
        )

        for project in [activeOld, activeNew, paused, completed] {
            try repository.create(project)
        }

        let model = makeModel(store: repository)

        #expect(ProjectStatus.managementOrder == [.active, .paused, .completed])
        #expect(model.projects(in: .active).map(\.id) == [activeNew.id, activeOld.id])
        #expect(model.projects(in: .paused).map(\.id) == [paused.id])
        #expect(model.projects(in: .completed).map(\.id) == [completed.id])
    }

    @Test func editingPersistsFieldsAndPreservesCooldown() throws {
        let repository = try makeRepository()
        let drawnAt = Date(timeIntervalSince1970: 1_700_000_100)
        let cooldown = Date(timeIntervalSince1970: 1_700_086_500)
        let original = try makeProject(
            name: "旧名称",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastDrawnAt: drawnAt,
            cooldownUntil: cooldown
        )
        try repository.create(original)
        let model = makeModel(store: repository)

        #expect(model.updateProject(
            id: original.id,
            displayName: "  新名称  ",
            note: "新的行动备注",
            weight: .high
        ))

        let saved = try #require(try repository.fetch(id: original.id))
        #expect(saved.displayName == "新名称")
        #expect(saved.note == "新的行动备注")
        #expect(saved.weight == .high)
        #expect(saved.lastDrawnAt == drawnAt)
        #expect(saved.cooldownUntil == cooldown)
        #expect(model.projects.first(where: { $0.id == original.id }) == saved)
    }

    @Test func emptyDisplayNameFailsAndKeepsSavedProject() throws {
        let repository = try makeRepository()
        let original = try makeProject(
            name: "保留名称",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try repository.create(original)
        let model = makeModel(store: repository)

        #expect(!model.updateProject(
            id: original.id,
            displayName: " \n\t ",
            note: "不应保存",
            weight: .low
        ))
        #expect(try repository.fetch(id: original.id) == original)
        #expect(model.projects == [original])

        guard case .operationFailed(_, _, let reason) = model.feedback else {
            Issue.record("空名称失败应反馈项目管理错误")
            return
        }
        #expect(reason == "项目名称不能为空。")
    }

    @Test func supportsAllLegalStatusTransitionsAndPreservesCooldown() throws {
        let repository = try makeRepository()
        let drawnAt = Date(timeIntervalSince1970: 1_700_000_100)
        let cooldown = Date(timeIntervalSince1970: 1_700_086_500)
        let project = try makeProject(
            name: "状态项目",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastDrawnAt: drawnAt,
            cooldownUntil: cooldown
        )
        let pausedToCompleted = try makeProject(
            name: "暂停完成项目",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_001)
        )
        try repository.create(project)
        try repository.create(pausedToCompleted)
        let model = makeModel(store: repository)

        #expect(model.changeStatus(id: project.id, to: .paused))
        #expect(try repository.fetch(id: project.id)?.status == .paused)
        #expect(model.changeStatus(id: project.id, to: .active))
        #expect(try repository.fetch(id: project.id)?.status == .active)
        #expect(model.changeStatus(id: project.id, to: .completed))
        #expect(try repository.fetch(id: project.id)?.status == .completed)
        #expect(model.changeStatus(id: project.id, to: .active))

        #expect(model.changeStatus(id: pausedToCompleted.id, to: .paused))
        #expect(model.changeStatus(id: pausedToCompleted.id, to: .completed))

        let saved = try #require(try repository.fetch(id: project.id))
        #expect(saved.status == .active)
        #expect(saved.lastDrawnAt == drawnAt)
        #expect(saved.cooldownUntil == cooldown)
    }

    @Test func deletingProjectKeepsOriginalFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProjectManagementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("important.txt")
        let originalContents = Data("original-content".utf8)
        try originalContents.write(to: fileURL)

        let repository = try makeRepository()
        let project = try Project(
            displayName: "重要文件",
            resourceType: .document,
            originalPath: fileURL.path,
            bookmarkData: Data([9, 8, 7])
        )
        try repository.create(project)
        let model = makeModel(store: repository)

        #expect(model.deleteProject(id: project.id))
        #expect(try repository.fetch(id: project.id) == nil)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: fileURL) == originalContents)
    }

    @Test func storageFailureReportsErrorAndKeepsMemoryAndSavedState() throws {
        let original = try makeProject(
            name: "持久化失败项目",
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let store = InMemoryManagementStore(values: [original])
        let model = makeModel(store: store)
        let savedBefore = store.values

        store.updateError = ManagementStoreError(message: "模拟存储失败")

        #expect(!model.updateProject(
            id: original.id,
            displayName: "不应出现的新名称",
            note: "不应保存",
            weight: .high
        ))
        #expect(model.projects == [original])
        #expect(store.values == savedBefore)

        guard case .operationFailed(_, let name, let reason) = model.feedback else {
            Issue.record("存储失败应反馈项目管理错误")
            return
        }
        #expect(name == original.displayName)
        #expect(reason == "模拟存储失败")
    }
}
