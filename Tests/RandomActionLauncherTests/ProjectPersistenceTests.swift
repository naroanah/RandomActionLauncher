import Foundation
import Testing
@testable import RandomActionLauncher

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
