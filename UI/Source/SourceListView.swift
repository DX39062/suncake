internal import SwiftUI

struct SourceListView: View {
    @EnvironmentObject var sourceStore: SourceStore
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack {
            HStack {
                Text("书源管理")
                    .font(.headline)
                Spacer()
                
                Menu("操作") {
                    Button("导入剪贴板书源") {
                        importFromClipboard()
                    }
                    
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Text("删除所有书源")
                    }
                }
            }
            .padding()
            .alert("确定删除所有书源吗？", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    sourceStore.deleteAll()
                }
            } message: {
                Text("此操作不可恢复。")
            }
            
            List {
                ForEach(sourceStore.sources) { source in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(source.bookSourceName)
                                .font(.headline)
                            Text(source.bookSourceUrl)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { source.enabled },
                            set: { _ in sourceStore.toggleSource(source) }
                        ))
                    }
                }
                .onDelete { indexSet in
                    sourceStore.deleteSource(at: indexSet)
                }
            }
        }
    }
    
    private func importFromClipboard() {
        // macOS Clipboard access
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            sourceStore.importSource(from: string)
        }
    }
}
