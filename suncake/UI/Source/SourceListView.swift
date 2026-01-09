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
    @State private var searchText = ""
    @State private var isSearching = false
    
    var displayedSources: [BookSource] {
        if searchText.isEmpty {
            return sourceStore.sources
        } else {
            return sourceStore.search(keyword: searchText)
        }
    }
    
    var body: some View {
        VStack {
            // Custom Toolbar Area
            HStack(spacing: 12) {
                if !isSearching {
                    Text("书源管理")
                        .font(.headline)
                }
                
                if isSearching {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("搜索书源...", text: $searchText)
                            .textFieldStyle(.plain)
                            .frame(maxWidth: 180)
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Button("取消") {
                            isSearching = false
                            searchText = ""
                        }
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    if editMode == .active {
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
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Button("完成") {
                            editMode = .inactive
                            selection.removeAll()
                        }
                        .fontWeight(.bold)
                    } else {
                        if !isSearching {
                            Button {
                                isSearching = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        
                        Button("导入") {
                            importFromClipboard()
                        }
                        
                        Button("校验") {
                            editMode = .active
                            sourceStore.checkSources(displayedSources) { id, isValid in
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
                            Image(systemName: isSearching ? "trash.slash" : "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .padding()
            .alert(isSearching ? "确定删除搜索到的 \(displayedSources.count) 个书源吗？" : "确定删除所有书源吗？", isPresented: $showingDeleteAlert) {
                Button("取消", role: .cancel) { }
                Button("删除", role: .destructive) {
                    if isSearching {
                        let ids = Set(displayedSources.map { $0.id })
                        sourceStore.deleteSources(ids: ids)
                    } else {
                        sourceStore.deleteAll()
                    }
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
        ForEach(displayedSources) { source in
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
            let idsToDelete = indexSet.map { displayedSources[$0].id }
            sourceStore.deleteSources(ids: Set(idsToDelete))
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