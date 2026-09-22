import Foundation
import Observation

@Observable
@MainActor
final class ProjectManagerModel {
    enum Feedback: Equatable {
        case created(name: String)
        case duplicate(name: String)
        case failed(name: String, reason: String)
        case reloadFailed(reason: String)
    }

    private(set) var projects: [Project] = []
    private(set) var feedback: Feedback?
    private(set) var highlightedProjectID: UUID?

    private let store: any ProjectStoring
    private let importService: ProjectImportService

    init(store: any ProjectStoring, importService: ProjectImportService) {
        self.store = store
        self.importService = importService
        reload()
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
}
