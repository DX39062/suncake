import SwiftUI

struct SearchView: View {
    @EnvironmentObject var sourceStore: SourceStore
    
    @State private var searchText: String = ""
    @State private var searchResults: [Book] = []
    @State private var isSearching: Bool = false
    
    private let searchModel = SearchModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Search Bar
            HStack {
                TextField("搜索书名或作者...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        performSearch()
                    }
                
                Button("搜索") {
                    // 必须在 Task 外打印，确保 UI 响应第一时间可见
                    print("DEBUG UI: 搜索按钮点击响应")
                    print("DEBUG UI: 当前可用书源数: \(sourceStore.sources.filter { $0.enabled }.count)")
                    performSearch()
                }
                .disabled(searchText.isEmpty || isSearching)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if isSearching {
                ProgressView().progressViewStyle(.linear).padding()
            }
            
            if searchResults.isEmpty && !isSearching {
                VStack {
                    Spacer()
                    Image(systemName: "magnifyingglass").font(.system(size: 48)).foregroundColor(.secondary.opacity(0.5))
                    Text("搜搜看吧").font(.title2).foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List(searchResults) { book in
                    BookRowView(book: book)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("网络搜索")
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        let enabledSources = sourceStore.sources.filter { $0.enabled }
        
        Task {
            print("DEBUG UI: 进入 Task，准备调用 searchModel")
            let stream = await searchModel.search(keyword: searchText, sources: enabledSources)
            
            print("DEBUG UI: 开始迭代 AsyncStream")
            for await books in stream {
                print("DEBUG UI: 收到 \(books.count) 本书籍更新")
                await MainActor.run {
                    self.searchResults.append(contentsOf: books)
                }
            }
            
            await MainActor.run {
                self.isSearching = false
                print("DEBUG UI: 搜索彻底完成")
            }
        }
    }
}