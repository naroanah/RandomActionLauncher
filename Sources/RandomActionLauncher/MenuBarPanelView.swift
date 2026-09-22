import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @Environment(\.openWindow) private var openWindow
    @State private var isPlaceholderVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("随机行动启动器", systemImage: "dice")
                .font(.headline)

            Divider()

            Button {
                isPlaceholderVisible = true
            } label: {
                Text("抽一个")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("抽一个")

            if isPlaceholderVisible {
                Text("项目抽取功能将在后续阶段实现。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("打开管理窗口") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AppSceneID.projectManager)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("打开项目管理窗口")
        }
        .padding(16)
        .frame(width: 300)
    }
}
