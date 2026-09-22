import Foundation
import Observation

@Observable
@MainActor
final class ProjectManagerModel {
    enum Feedback: Equatable {
        case created(name: String)
        case duplicate(name: String)
        case failed(name: String, reason: String)
        case relocated(name: String)
        case relocationDuplicate(name: String)
        case updated(name: String)
        case statusChanged(name: String, status: ProjectStatus)
        case deleted(name: String)
        case operationFailed(action: String, name: String, reason: String)
        case reloadFailed(reason: String)
    }

    private(set) var projects: [Project] = []
    private(set) var feedback: Feedback?
    private(set) var highlightedProjectID: UUID?

    private let store: any ProjectManaging
    private let importService: ProjectImportService
    private let managementService: ProjectManagementService
    private let relocationService: ProjectRelocationService

    init(
        store: any ProjectManaging,
        importService: ProjectImportService,
        relocationService: ProjectRelocationService
    ) {
        self.store = store
        self.importService = importService
        self.managementService = ProjectManagementService(store: store)
        self.relocationService = relocationService
        reload()
    }

    func projects(in status: ProjectStatus) -> [Project] {
        projects
            .filter { $0.status == status }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func reload() {
        do {
            projects = try store.fetchAll()
        } catch {
            feedback = .reloadFailed(reason: error.localizedDescription)
        }
    }

    func importURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        for url in urls {
            importSingle(url)
        }
        reload()
    }

    @discardableResult
    func relocateProject(id: UUID, to url: URL) -> Bool {
        let name = projectName(for: id)
        do {
            switch try relocationService.relocate(id: id, to: url) {
            case .updated(let updated):
                replaceProject(updated)
                feedback = .relocated(name: updated.displayName)
                return true
            case .duplicate(let existing):
                highlightedProjectID = existing.id
                feedback = .relocationDuplicate(name: existing.displayName)
                return false
            }
        } catch {
            return reportOperationFailure(action: "重新定位", name: name, error: error)
        }
    }

    @discardableResult
    func updateProject(
        id: UUID,
        displayName: String,
        note: String,
        weight: ProjectWeight
    ) -> Bool {
        let name = projectName(for: id)
        do {
            let updated = try managementService.updateDetails(
                id: id,
                displayName: displayName,
                note: note,
                weight: weight
            )
            replaceProject(updated)
            feedback = .updated(name: updated.displayName)
            return true
        } catch {
            return reportOperationFailure(action: "更新项目", name: name, error: error)
        }
    }

    @discardableResult
    func changeStatus(id: UUID, to status: ProjectStatus) -> Bool {
        let name = projectName(for: id)
        do {
            let updated = try managementService.changeStatus(id: id, to: status)
            replaceProject(updated)
            feedback = .statusChanged(name: updated.displayName, status: updated.status)
            return true
        } catch {
            return reportOperationFailure(action: "切换状态", name: name, error: error)
        }
    }

    @discardableResult
    func deleteProject(id: UUID) -> Bool {
        let name = projectName(for: id)
        do {
            try managementService.delete(id: id)
            projects.removeAll { $0.id == id }
            if highlightedProjectID == id {
                highlightedProjectID = nil
            }
            feedback = .deleted(name: name)
            return true
        } catch {
            return reportOperationFailure(action: "删除项目", name: name, error: error)
        }
    }

    private func importSingle(_ url: URL) {
        do {
            switch try importService.importResource(at: url) {
            case .created(let project):
                feedback = .created(name: project.displayName)
                highlightedProjectID = nil
            case .duplicate(let project):
                feedback = .duplicate(name: project.displayName)
                highlightedProjectID = project.id
            }
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            feedback = .failed(name: url.lastPathComponent, reason: reason)
        }
    }

    private func replaceProject(_ updated: Project) {
        guard let index = projects.firstIndex(where: { $0.id == updated.id }) else {
            projects.append(updated)
            return
        }
        projects[index] = updated
    }

    private func projectName(for id: UUID) -> String {
        projects.first(where: { $0.id == id })?.displayName ?? "项目"
    }

    private func reportOperationFailure(action: String, name: String, error: Error) -> Bool {
        restoreSavedProjects()
        let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        feedback = .operationFailed(action: action, name: name, reason: reason)
        return false
    }

    private func restoreSavedProjects() {
        do {
            projects = try store.fetchAll()
        } catch {
            // 保留当前列表，避免恢复读取失败时把已经显示的状态清空。
        }
    }
}
