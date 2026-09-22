import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    let model: MenuBarCoordinatorModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("随机行动启动器", systemImage: "dice")
                .font(.headline)

            Divider()

            content

            Button("打开管理窗口") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: AppSceneID.projectManager)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("打开项目管理窗口")
        }
        .padding(16)
        .frame(width: 320)
        .onAppear {
            model.refresh()
        }
        .onDisappear {
            model.reset()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            Button {
                model.draw()
            } label: {
                Text("抽一个")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(model.isOperationInProgress)
            .accessibilityLabel("抽一个项目")

        case .result(let project):
            resultCard(project, errorMessage: nil)

        case .empty(let reason):
            emptyState(reason)

        case .error(let message, let result):
            if let result {
                resultCard(result, errorMessage: message)
            } else {
                errorState(message)
            }

        case .operationInProgress:
            VStack(spacing: 10) {
                ProgressView()
                Text("正在处理…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在处理")
        }
    }

    private func resultCard(_ project: Project, errorMessage: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(project.displayName)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(project.originalPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if let note = MenuBarCoordinatorModel.visibleNote(from: project.note) {
                Text(note)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button("打开") {
                    model.openCurrentResult()
                }
                .accessibilityLabel("打开项目")

                Button("重抽") {
                    model.reroll()
                }
                .accessibilityLabel("重新抽取项目")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(model.isOperationInProgress)
        }
    }

    private func emptyState(_ reason: ProjectEmptyReason) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("暂时没有可抽取项目", systemImage: "tray")
                .font(.headline)
            Text(reason.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("暂时没有可抽取项目。\(reason.message)")
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("操作失败", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(message)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试") {
                model.draw()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("重试抽取")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
