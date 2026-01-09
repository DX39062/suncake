internal import SwiftUI

#if os(macOS)
enum EditMode {
    case active
    case inactive
}
#endif

struct SourceListView: View {
    @EnvironmentObject var sourceStore: SourceStore
    @State private var showingDeleteAlert = false
    @State private var selection = Set<String>() // Stores BookSource IDs
    @State private var editMode: EditMode = .inactive
    
    var body: some View {
        VStack {
            // Custom Toolbar Area
            HStack {
                Text("书源管理")
                    .font(.headline)
                
                Spacer()
                
                if editMode == .active {
                    HStack(spacing: 12) {
                        if !selection.isEmpty {
                            Button("启用") {
                                for id in selection {
                                    if let index = sourceStore.sources.firstIndex(where: { $0.id == id }) {
                                        sourceStore.sources[index].enabled = true
                                    }
                                }
                                sourceStore.saveSources()
                            }
                            
                            Button("禁用") {
                                for id in selection {
                                    if let index = sourceStore.sources.firstIndex(where: { $0.id == id }) {
                                        sourceStore.sources[index].enabled = false
                                    }
                                }
                                sourceStore.saveSources()
                            }
                            
                            Button(role: .destructive) {
                                sourceStore.deleteSources(ids: selection)
                                selection.removeAll()
                                // Optional: exit edit mode after delete?
                                // editMode = .inactive 
                            } label: {
                                Text("删除 (\(selection.count))")
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Button("完成") {
                            editMode = .inactive
                            selection.removeAll()
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Button("导入") {
                            importFromClipboard()
                        }
                        
                        Button("校验") {
                            editMode = .active
                            sourceStore.checkAllSources { id, isValid in
                                if !isValid {
                                    selection.insert(id)
                                }
                            }
                        }
                        
                        Button("多选") {
                            editMode = .active
                        }
                        
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Text("清空")
                                .foregroundColor(.red)
                        }
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
            
            #if os(iOS)
            List(selection: $selection) {
                listContent
            }
            .environment(\.editMode, $editMode)
            #else
            List {
                listContent
            }
            #endif
        }
    }
    
    @ViewBuilder
    private var listContent: some View {
        ForEach(sourceStore.sources) { source in
            HStack {
                #if os(macOS)
                if editMode == .active {
                    Image(systemName: selection.contains(source.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(selection.contains(source.id) ? .blue : .gray)
                        .onTapGesture {
                            toggleSelection(for: source)
                        }
                }
                #endif
                
                VStack(alignment: .leading) {
                    Text(source.bookSourceName)
                        .font(.headline)
                    Text(source.bookSourceUrl)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                
                if let status = sourceStore.validationStatuses[source.id] {
                    switch status {
                    case .checking:
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 20)
                    case .valid:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .invalid:
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                    case .unknown:
                        EmptyView()
                    }
                }
                
                if editMode == .inactive {
                    Toggle("", isOn: Binding(
                        get: { source.enabled },
                        set: { _ in sourceStore.toggleSource(source) }
                    ))
                    .labelsHidden()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                #if os(macOS)
                if editMode == .active {
                    toggleSelection(for: source)
                }
                #endif
            }
            .tag(source.id)
        }
        .onDelete { indexSet in
            sourceStore.deleteSource(at: indexSet)
        }
    }
    
    #if os(macOS)
    private func toggleSelection(for source: BookSource) {
        if selection.contains(source.id) {
            selection.remove(source.id)
        } else {
            selection.insert(source.id)
        }
    }
    #endif
    
    private func importFromClipboard() {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        if let string = pasteboard.string(forType: .string) {
            sourceStore.importSource(from: string)
        }
        #endif
    }
}