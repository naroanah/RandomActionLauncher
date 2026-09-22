import Foundation
import Observation

enum MenuBarPanelState: Equatable {
    case idle
    case result(Project)
    case empty(ProjectEmptyReason)
    case error(message: String, result: Project?)
    case operationInProgress

    var resultProject: Project? {
        switch self {
        case .result(let project):
            return project
        case .error(_, let project):
            return project
        case .idle, .empty, .operationInProgress:
            return nil
        }
    }
}

@MainActor
protocol ProjectDrawing: AnyObject {
    func draw() throws -> ProjectDrawResult
}

extension ProjectDrawService: ProjectDrawing {}

@Observable
@MainActor
final class MenuBarCoordinatorModel {
    private let drawService: any ProjectDrawing
    private let store: any ProjectManaging
    private let resourceResolver: any ProjectResourceResolving
    private let emptyStateClassifier: any ProjectEmptyStateClassifying
    private let projectOpener: any ProjectOpening

    private(set) var state: MenuBarPanelState = .idle
    private var isBusy = false

    init(
        drawService: any ProjectDrawing,
        store: any ProjectManaging,
        resourceResolver: any ProjectResourceResolving,
        emptyStateClassifier: any ProjectEmptyStateClassifying,
        projectOpener: any ProjectOpening
    ) {
        self.drawService = drawService
        self.store = store
        self.resourceResolver = resourceResolver
        self.emptyStateClassifier = emptyStateClassifier
        self.projectOpener = projectOpener
    }

    convenience init(
        drawService: any ProjectDrawing,
        store: any ProjectManaging,
        resourceChecker: any ProjectResourceChecking,
        emptyStateClassifier: any ProjectEmptyStateClassifying,
        projectOpener: any ProjectOpening
    ) {
        self.init(
            drawService: drawService,
            store: store,
            resourceResolver: CheckedProjectResourceResolver(checker: resourceChecker),
            emptyStateClassifier: emptyStateClassifier,
            projectOpener: projectOpener
        )
    }

    var isOperationInProgress: Bool {
        isBusy || state == .operationInProgress
    }

    var currentResult: Project? {
        state.resultProject
    }

    func draw() {
        performDraw()
    }

    func reroll() {
        performDraw()
    }

    func refresh() {
        guard !isBusy, let displayedProject = currentResult else {
            return
        }

        do {
            guard let latestProject = try store.fetch(id: displayedProject.id) else {
                invalidateResult(message: "当前结果已被删除，请重新抽取。")
                return
            }
            guard latestProject.status == .active else {
                invalidateResult(message: statusInvalidationMessage(for: latestProject.status))
                return
            }
            guard case .available(let resource) = try resourceResolver.resolve(latestProject) else {
                invalidateResult(message: "当前结果资源不可用，请重新抽取。")
                return
            }
            state = .result(resource.project)
        } catch {
            state = .error(
                message: "无法刷新当前结果：\(errorMessage(for: error))",
                result: displayedProject
            )
        }
    }

    func openCurrentResult() {
        guard !isBusy else {
            state = .operationInProgress
            return
        }
        guard let displayedProject = currentResult else {
            return
        }

        isBusy = true
        state = .operationInProgress
        defer { isBusy = false }

        let latestProject: Project
        do {
            guard let project = try store.fetch(id: displayedProject.id) else {
                invalidateResult(message: "当前结果已被删除，请重新抽取。")
                return
            }
            latestProject = project
        } catch {
            state = .error(
                message: "无法确认当前结果：\(errorMessage(for: error))",
                result: displayedProject
            )
            return
        }

        guard latestProject.status == .active else {
            invalidateResult(message: statusInvalidationMessage(for: latestProject.status))
            return
        }
        var openedProject = latestProject
        do {
            let resolution = try resourceResolver.resolve(latestProject) { resource in
                openedProject = resource.project
                try projectOpener.open(resource.url)
            }
            guard case .available(let resource) = resolution else {
                invalidateResult(message: "当前结果资源不可用，请重新抽取。")
                return
            }
            state = .result(resource.project)
        } catch let error as ProjectResourceResolutionError {
            state = .error(
                message: "无法确认当前结果：\(errorMessage(for: error))",
                result: displayedProject
            )
        } catch {
            state = .error(
                message: "打开失败：\(errorMessage(for: error))",
                result: openedProject
            )
        }
    }

    func reset() {
        isBusy = false
        state = .idle
    }

    static func visibleNote(from note: String) -> String? {
        guard !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return note
    }

    private func performDraw() {
        guard !isBusy else {
            state = .operationInProgress
            return
        }

        let previousResult = currentResult
        isBusy = true
        state = .operationInProgress
        defer { isBusy = false }

        do {
            switch try drawService.draw() {
            case .selected(let project):
                state = .result(project)
            case .noEligibleProjects:
                state = .empty(try emptyStateClassifier.classify())
            case .operationInProgress:
                state = .error(
                    message: "抽取操作仍在进行，请稍后重试。",
                    result: previousResult
                )
            }
        } catch {
            state = .error(message: errorMessage(for: error), result: nil)
        }
    }

    private func invalidateResult(message: String) {
        state = .error(message: message, result: nil)
    }

    private func statusInvalidationMessage(for status: ProjectStatus) -> String {
        switch status {
        case .active:
            return "当前结果已失效，请重新抽取。"
        case .paused:
            return "当前结果已暂停，请重新抽取。"
        case .completed:
            return "当前结果已完成，请重新抽取。"
        }
    }

    private func errorMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription
        {
            return description
        }
        return error.localizedDescription
    }
}
