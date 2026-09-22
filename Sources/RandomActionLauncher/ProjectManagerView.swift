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
                List {
                    ForEach(ProjectStatus.managementOrder, id: \.rawValue) { status in
                        let statusProjects = model.projects(in: status)
                        if !statusProjects.isEmpty {
                            Section {
                                ForEach(statusProjects) { project in
                                    ProjectRow(project: project, model: model)
                                        .id(project.id)
                                        .listRowBackground(
                                            model.highlightedProjectID == project.id
                                                ? Color.accentColor.opacity(0.18)
                                                : Color.clear
                                        )
                                }
                            } header: {
                                Text(status.localizedName)
                                    .font(.headline)
                            }
                        }
                    }
                }
                .listStyle(.inset)
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
        case .updated(let name):
            Label("已更新「\(name)」。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("已更新项目\(name)")
        case .statusChanged(let name, let status):
            Label("「\(name)」已切换为“\(status.localizedName)”。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("项目\(name)已切换为\(status.localizedName)")
        case .deleted(let name):
            Label("已移除「\(name)」的应用记录；本地文件未删除。", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel("已删除项目记录\(name)，本地文件未删除")
        case .operationFailed(let action, let name, let reason):
            Label("\(action)「\(name)」失败：\(reason)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("\(action)\(name)失败，\(reason)")
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
    let model: ProjectManagerModel

    @State private var isEditing = false
    @State private var draftName: String
    @State private var draftNote: String
    @State private var draftWeight: ProjectWeight
    @State private var isDeleteConfirmationPresented = false

    init(project: Project, model: ProjectManagerModel) {
        self.project = project
        self.model = model
        _draftName = State(initialValue: project.displayName)
        _draftNote = State(initialValue: project.note)
        _draftWeight = State(initialValue: project.weight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing {
                editor
            } else {
                details
            }

            Divider()
            actions
        }
        .padding(.vertical, 6)
        .onChange(of: project.updatedAt) { _, _ in
            draftName = project.displayName
            draftNote = project.note
            draftWeight = project.weight
        }
        .confirmationDialog(
            "删除“\(project.displayName)”？",
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                _ = model.deleteProject(id: project.id)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会移除应用中的记录，不会删除本地文件")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(project.displayName)
                .font(.body.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Text(project.originalPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Text("备注：\(project.note.isEmpty ? "无" : project.note)")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Text("类型：\(resourceTypeName)")
                Text("权重：\(project.weight.localizedName)")
                Text("状态：\(project.status.localizedName)")
                Text("可用性：\(project.availability.localizedName)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("项目名称", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("项目名称")

            TextEditor(text: $draftNote)
                .frame(minHeight: 56, maxHeight: 96)
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondary.opacity(0.25))
                }
                .accessibilityLabel("项目备注")

            Picker("权重", selection: $draftWeight) {
                ForEach(ProjectWeight.allCases, id: \.rawValue) { weight in
                    Text(weight.localizedName).tag(weight)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("项目权重")

            HStack(spacing: 8) {
                Button("保存") {
                    saveEdits()
                }
                .keyboardShortcut(.defaultAction)

                Button("取消") {
                    cancelEditing()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            Button("编辑") {
                beginEditing()
            }
            .disabled(isEditing)

            switch project.status {
            case .active:
                Button("暂停") {
                    _ = model.changeStatus(id: project.id, to: .paused)
                }
                Button("完成") {
                    _ = model.changeStatus(id: project.id, to: .completed)
                }
            case .paused:
                Button("恢复") {
                    _ = model.changeStatus(id: project.id, to: .active)
                }
                Button("完成") {
                    _ = model.changeStatus(id: project.id, to: .completed)
                }
            case .completed:
                Button("重新激活") {
                    _ = model.changeStatus(id: project.id, to: .active)
                }
            }

            Spacer(minLength: 8)

            Button("删除", role: .destructive) {
                isDeleteConfirmationPresented = true
            }
            .accessibilityHint("只会移除应用中的记录，不会删除本地文件")
        }
        .buttonStyle(.borderless)
    }

    private var resourceTypeName: String {
        switch project.resourceType {
        case .folder: "文件夹"
        case .video: "视频"
        case .document: "文档"
        }
    }

    private func beginEditing() {
        draftName = project.displayName
        draftNote = project.note
        draftWeight = project.weight
        isEditing = true
    }

    private func saveEdits() {
        if model.updateProject(
            id: project.id,
            displayName: draftName,
            note: draftNote,
            weight: draftWeight
        ) {
            isEditing = false
        }
    }

    private func cancelEditing() {
        draftName = project.displayName
        draftNote = project.note
        draftWeight = project.weight
        isEditing = false
    }
}
