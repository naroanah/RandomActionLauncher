import AppKit
import SwiftUI

struct ProjectManagerView: View {
    let model: ProjectManagerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            projectList
            if let feedback = model.feedback {
                Divider()
                feedbackBanner(feedback)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .navigationTitle("项目管理")
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            model.importURLs(urls)
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label("项目（\(model.projects.count)）", systemImage: "tray.full")
                .font(.headline)
            Text("支持文件、视频和文件夹；文件夹只创建一条记录")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                presentOpenPanel()
            } label: {
                Label("添加项目…", systemImage: "plus")
            }
            .accessibilityLabel("添加项目")
            .accessibilityHint("打开系统文件选择器，可选择文件或文件夹")
        }
        .padding(16)
    }

    @ViewBuilder
    private var projectList: some View {
        if model.projects.isEmpty {
            ContentUnavailableView {
                Label("还没有项目", systemImage: "tray")
            } description: {
                Text("点击“添加项目…”选择文件、视频或文件夹，也可以直接拖到这个窗口。")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                List(model.projects) { project in
                    ProjectRow(project: project)
                        .id(project.id)
                        .listRowBackground(
                            model.highlightedProjectID == project.id
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                }
                .accessibilityLabel("项目列表")
                .onChange(of: model.highlightedProjectID) { _, projectID in
                    guard let projectID else { return }
                    withAnimation {
                        proxy.scrollTo(projectID, anchor: .center)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func feedbackBanner(_ feedback: ProjectManagerModel.Feedback) -> some View {
        switch feedback {
        case .created(let name):
            Label("已添加「\(name)」。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("已添加项目\(name)")
        case .duplicate(let name):
            Label("「\(name)」已在列表中，未重复添加；已在列表中定位。", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityLabel("\(name)已存在于列表，未重复添加")
        case .failed(let name, let reason):
            Label("添加「\(name)」失败：\(reason)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("添加\(name)失败，\(reason)")
                .fixedSize(horizontal: false, vertical: true)
        case .reloadFailed(let reason):
            Label("读取项目列表失败：\(reason)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("读取项目列表失败，\(reason)")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "添加项目"
        panel.message = "选择要添加的文件、视频或文件夹"
        panel.prompt = "添加"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        model.importURLs(panel.urls)
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(project.displayName)
                    .font(.body.weight(.semibold))
                Text(project.originalPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            Text(typeLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var typeLabel: String {
        switch project.resourceType {
        case .folder: "文件夹"
        case .video: "视频"
        case .document: "文档"
        }
    }
}
