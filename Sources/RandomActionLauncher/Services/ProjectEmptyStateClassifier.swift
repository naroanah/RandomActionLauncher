import Foundation

enum ProjectEmptyReason: Equatable {
    case noProjects
    case noActiveProjects
    case allActiveProjectsCooling
    case allActiveProjectsUnavailable
    case activeProjectsCoolingAndUnavailable
    case projectsChanged

    var message: String {
        switch self {
        case .noProjects:
            return "尚未添加任何项目。"
        case .noActiveProjects:
            return "所有项目均已暂停或完成。"
        case .allActiveProjectsCooling:
            return "所有进行中项目仍在 24 小时冷却中。"
        case .allActiveProjectsUnavailable:
            return "所有进行中项目的路径均不可用。"
        case .activeProjectsCoolingAndUnavailable:
            return "进行中项目同时存在冷却和不可用路径。"
        case .projectsChanged:
            return "项目状态刚刚发生变化，请重新抽取。"
        }
    }
}

@MainActor
protocol ProjectEmptyStateClassifying: AnyObject {
    func classify() throws -> ProjectEmptyReason
}

@MainActor
final class ProjectEmptyStateClassifier: ProjectEmptyStateClassifying {
    private let store: any ProjectStoring
    private let clock: any ProjectClock
    private let resourceChecker: any ProjectResourceChecking

    init(
        store: any ProjectStoring,
        clock: any ProjectClock,
        resourceChecker: any ProjectResourceChecking
    ) {
        self.store = store
        self.clock = clock
        self.resourceChecker = resourceChecker
    }

    func classify() throws -> ProjectEmptyReason {
        let projects = try store.fetchAll()
        guard !projects.isEmpty else {
            return .noProjects
        }

        let activeProjects = projects.filter { $0.status == .active }
        guard !activeProjects.isEmpty else {
            return .noActiveProjects
        }

        let now = clock.now
        let coolingProjects = activeProjects.filter { project in
            guard let cooldownUntil = project.cooldownUntil else {
                return false
            }
            return now < cooldownUntil
        }
        let unavailableProjects = activeProjects.filter {
            !resourceChecker.isResourceAvailable(for: $0)
        }

        let allCooling = coolingProjects.count == activeProjects.count
        let allUnavailable = unavailableProjects.count == activeProjects.count
        if (allCooling && allUnavailable)
            || (!coolingProjects.isEmpty && !unavailableProjects.isEmpty)
        {
            return .activeProjectsCoolingAndUnavailable
        }
        if allCooling {
            return .allActiveProjectsCooling
        }
        if allUnavailable {
            return .allActiveProjectsUnavailable
        }

        // 抽取与诊断之间数据可能发生变化，不猜测一个并不存在的空状态原因。
        return .projectsChanged
    }
}
