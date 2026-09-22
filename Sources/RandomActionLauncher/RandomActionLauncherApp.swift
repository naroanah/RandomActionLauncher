import CoreData
import SwiftUI

@main
struct RandomActionLauncherApp: App {
    @State private var storageState: StorageState

    init() {
        do {
            let container = try PersistenceContainerFactory.makeApplicationContainer()
            let repository = ProjectRepository(container: container)
            let model = ProjectManagerModel(
                store: repository,
                importService: ProjectImportService(store: repository)
            )
            _storageState = State(initialValue: .ready(model))
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
            let container = try PersistenceContainerFactory.makeApplicationContainer()
            let repository = ProjectRepository(container: container)
            storageState = .ready(
                ProjectManagerModel(
                    store: repository,
                    importService: ProjectImportService(store: repository)
                )
            )
        } catch {
            storageState = .failed(error.localizedDescription)
        }
    }
}

private enum StorageState {
    case ready(ProjectManagerModel)
    case failed(String)
}

private struct StorageWindowContent: View {
    let state: StorageState
    let retry: () -> Void

    var body: some View {
        switch state {
        case .ready(let container):
            ProjectManagerView(model: container)
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
        case .ready:
            MenuBarPanelView()
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
