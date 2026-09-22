import Foundation

enum ProjectManagementError: LocalizedError, Equatable {
    case projectNotFound(UUID)
    case invalidStatusTransition(from: ProjectStatus, to: ProjectStatus)

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let id):
            return "找不到项目记录：\(id.uuidString)。"
        case .invalidStatusTransition(let from, let to):
            return "不允许将项目从“\(from.localizedName)”切换为“\(to.localizedName)”。"
        }
    }
}

/// 项目管理服务只修改应用内的项目记录，不接触项目关联的原始资源。
@MainActor
final class ProjectManagementService {
    private let store: any ProjectManaging

    init(store: any ProjectManaging) {
        self.store = store
    }

    @discardableResult
    func updateDetails(
        id: UUID,
        displayName: String,
        note: String,
        weight: ProjectWeight
    ) throws -> Project {
        let normalizedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProjectValidationError.emptyDisplayName
        }

        return try store.update(id: id) { project in
            project.displayName = normalizedName
            project.note = note
            project.weight = weight
        }
    }

    @discardableResult
    func changeStatus(id: UUID, to newStatus: ProjectStatus) throws -> Project {
        guard let current = try store.fetch(id: id) else {
            throw ProjectManagementError.projectNotFound(id)
        }
        guard isValidTransition(from: current.status, to: newStatus) else {
            throw ProjectManagementError.invalidStatusTransition(
                from: current.status,
                to: newStatus
            )
        }

        return try store.update(id: id) { project in
            project.status = newStatus
        }
    }

    func delete(id: UUID) throws {
        try store.delete(id: id)
    }

    private func isValidTransition(from: ProjectStatus, to: ProjectStatus) -> Bool {
        switch (from, to) {
        case (.active, .paused),
            (.active, .completed),
            (.paused, .active),
            (.paused, .completed),
            (.completed, .active):
            return true
        default:
            return false
        }
    }
}
