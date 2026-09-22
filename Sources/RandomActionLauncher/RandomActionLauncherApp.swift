import SwiftUI

@main
struct RandomActionLauncherApp: App {
    var body: some Scene {
        Window("项目管理", id: AppSceneID.projectManager) {
            ProjectManagerView()
        }
        .defaultSize(width: 760, height: 520)
        .windowResizability(.contentMinSize)

        MenuBarExtra("随机行动启动器", systemImage: "dice") {
            MenuBarPanelView()
        }
        .menuBarExtraStyle(.window)
    }
}

enum AppSceneID {
    static let projectManager = "project-manager"
}
