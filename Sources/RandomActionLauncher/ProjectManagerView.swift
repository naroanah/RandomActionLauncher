import SwiftUI

struct ProjectManagerView: View {
    var body: some View {
        ContentUnavailableView {
            Label("还没有项目", systemImage: "tray")
        } description: {
            Text("项目管理将在后续阶段实现。")
        }
        .frame(minWidth: 560, minHeight: 360)
        .navigationTitle("项目管理")
    }
}
