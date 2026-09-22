import CoreData
import SwiftUI

@main
struct RandomActionLauncherApp: App {
    @State private var storageState: StorageState

    init() {
        do {
            _storageState = State(initialValue: try Self.makeReadyStorageState())
        } catch {
            _storageState = State(initialValue: .failed(error.localizedDescription))
        }
    }

    var body: some Scene {
        Window("项目管理", id: AppSceneID.projectManager) {
            StorageWindowContent(state: storageState) {
                retryStorageInitialization()
            }
        }
        .defaultSize(width: 760, height: 520)
        .windowResizability(.contentMinSize)

        MenuBarExtra("随机行动启动器", systemImage: "dice") {
            StorageMenuBarContent(state: storageState) {
                retryStorageInitialization()
            }
        }
        .menuBarExtraStyle(.window)
    }

    private func retryStorageInitialization() {
        do {
            storageState = try Self.makeReadyStorageState()
        } catch {
            storageState = .failed(error.localizedDescription)
        }
    }

    private static func makeReadyStorageState() throws -> StorageState {
        let container = try PersistenceContainerFactory.makeApplicationContainer()
        let repository = ProjectRepository(container: container)
        let clock = SystemProjectClock()
        let bookmarks = SecurityBookmarkService()
        let resourceResolver = ProjectResourceResolver(
            store: repository,
            bookmarks: bookmarks
        )
        let sessionRepository = DrawSessionRepository(container: container)
        let sessionService = DrawSessionService(
            store: sessionRepository,
            clock: clock
        )
        let projectManager = ProjectManagerModel(
            store: repository,
            importService: ProjectImportService(store: repository),
            relocationService: ProjectRelocationService(store: repository, bookmarks: bookmarks),
            sessionRepository: sessionRepository
        )
        let drawService = ProjectDrawService(
            store: repository,
            clock: clock,
            resourceResolver: resourceResolver
        )
        let emptyStateClassifier = ProjectEmptyStateClassifier(
            store: repository,
            clock: clock,
            resourceResolver: resourceResolver
        )
        let menuBar = MenuBarCoordinatorModel(
            drawService: drawService,
            store: repository,
            resourceResolver: resourceResolver,
            emptyStateClassifier: emptyStateClassifier,
            projectOpener: NSWorkspaceProjectOpener(),
            sessionService: sessionService
        )

        return .ready(projectManager: projectManager, menuBar: menuBar)
    }
}

private enum StorageState {
    case ready(projectManager: ProjectManagerModel, menuBar: MenuBarCoordinatorModel)
    case failed(String)
}

private struct StorageWindowContent: View {
    let state: StorageState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .ready(let projectManager, _):
            ProjectManagerView(model: projectManager)
        case .failed(let message):
            StorageFailureView(message: message, retry: retry)
        }
    }
}

private struct StorageMenuBarContent: View {
    let state: StorageState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .ready(_, let menuBar):
            MenuBarPanelView(model: menuBar)
        case .failed(let message):
            StorageFailureView(message: message, retry: retry)
                .frame(width: 360, height: 240)
        }
    }
}

private struct StorageFailureView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("本地存储无法初始化", systemImage: "externaldrive.badge.exclamationmark")
                .font(.title3.weight(.semibold))
            Text("应用没有清空或覆盖已有数据。请检查磁盘权限或存储位置后重试。")
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("重试", action: retry)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

enum AppSceneID {
    static let projectManager = "project-manager"
}
