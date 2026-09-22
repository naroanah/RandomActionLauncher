import Foundation
import Testing
@testable import RandomActionLauncher

@MainActor
struct ProjectPersistenceTests {
    private func makeProject(
        name: String = "学习项目",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws -> Project {
        try Project(
            displayName: name,
            note: "备注",
            resourceType: .document,
            originalPath: "/tmp/example.pdf",
            bookmarkData: Data([1, 2, 3]),
            createdAt: date
        )
    }

    @Test func defaultValuesAndEnumWeights() throws {
        let project = try makeProject(name: "  学习项目  ")

        #expect(project.displayName == "学习项目")
        #expect(project.status == .active)
        #expect(project.weight == .medium)
        #expect(ProjectWeight.low.numericValue == 1)
        #expect(ProjectWeight.medium.numericValue == 2)
        #expect(ProjectWeight.high.numericValue == 3)
        #expect(project.lastDrawnAt == nil)
        #expect(project.cooldownUntil == nil)
        #expect(project.availability == .available)
    }

    @Test func cooldownStatusTextReflectsCurrentTime() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let noCooldown = try makeProject(name: "未抽取", date: now)

        #expect(noCooldown.cooldownStatusText(now: now) == "无冷却")

        // 即将结束（不到 1 分钟）
        var soon = noCooldown
        soon.cooldownUntil = now.addingTimeInterval(30)
        #expect(soon.cooldownStatusText(now: now) == "即将结束")

        // 分钟级
        var minutes = noCooldown
        minutes.cooldownUntil = now.addingTimeInterval(5 * 60)
        #expect(minutes.cooldownStatusText(now: now) == "剩余 5 分钟")

        // 小时 + 分钟
        var hours = noCooldown
        hours.cooldownUntil = now.addingTimeInterval(2 * 3600 + 30 * 60)
        #expect(hours.cooldownStatusText(now: now) == "剩余 2 小时 30 分钟")

        // 已结束（等于边界）
        var expired = noCooldown
        expired.cooldownUntil = now
        #expect(expired.cooldownStatusText(now: now) == "已结束")

        // 已过期
        var past = noCooldown
        past.cooldownUntil = now.addingTimeInterval(-1)
        #expect(past.cooldownStatusText(now: now) == "已结束")
    }

    @Test func emptyDisplayNameThrows() {
        #expect(throws: ProjectValidationError.emptyDisplayName) {
            try Project(
                displayName: " \n\t ",
                resourceType: .folder,
                originalPath: "/tmp/folder"
            )
        }
    }

    @Test func allFieldsRoundTripThroughMemoryContainer() throws {
        let repository = ProjectRepository(
            container: try PersistenceContainerFactory.makeInMemoryContainer()
        )
        var created = try makeProject()
        created.status = .paused
        created.weight = .high
        created.availability = .unavailable
        created.lastDrawnAt = Date(timeIntervalSince1970: 1_700_000_100)
        created.cooldownUntil = Date(timeIntervalSince1970: 1_700_086_500)

        try repository.create(created)
        let loaded = try #require(try repository.fetch(id: created.id))

        #expect(loaded == created)
    }

    @Test func updateNormalizesAndPersistsChanges() throws {
        let repository = ProjectRepository(
            container: try PersistenceContainerFactory.makeInMemoryContainer()
        )
        let project = try repository.create(makeProject())

        let updated = try repository.update(id: project.id) { project in
            project.displayName = "  新名称  "
            project.note = "新备注"
            project.weight = .low
        }

        #expect(updated.displayName == "新名称")
        #expect(updated.note == "新备注")
        #expect(updated.weight == .low)
        #expect(try repository.fetch(id: project.id) == updated)
    }

    @Test func invalidUpdateRollsBack() throws {
        let repository = ProjectRepository(
            container: try PersistenceContainerFactory.makeInMemoryContainer()
        )
        let project = try repository.create(makeProject())

        #expect(throws: ProjectValidationError.emptyDisplayName) {
            try repository.update(id: project.id) { project in
                project.displayName = "   "
            }
        }
        #expect(try repository.fetch(id: project.id)?.displayName == "学习项目")
    }

    @Test func deleteRemovesProjectRecord() throws {
        let repository = ProjectRepository(
            container: try PersistenceContainerFactory.makeInMemoryContainer()
        )
        let project = try repository.create(makeProject())

        try repository.delete(id: project.id)

        #expect(try repository.fetch(id: project.id) == nil)
    }

    @Test func diskContainerPersistsAfterRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RandomActionLauncherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("store.sqlite")
        let project = try makeProject()

        do {
            let repository = ProjectRepository(
                container: try PersistenceContainerFactory.makeDiskContainer(at: storeURL)
            )
            try repository.create(project)
        }

        let repository = ProjectRepository(
            container: try PersistenceContainerFactory.makeDiskContainer(at: storeURL)
        )
        #expect(try repository.fetch(id: project.id) == project)
    }
}
