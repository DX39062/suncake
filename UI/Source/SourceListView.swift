internal import SwiftUI

struct SourceListView: View {
    @EnvironmentObject var sourceStore: SourceStore
    
    var body: some View {
        VStack {
            HStack {
                Text("书源管理")
                    .font(.headline)
                Spacer()
                Button("导入剪贴板书源") {
                    importFromClipboard()
                }
            }
            .padding()
            
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
