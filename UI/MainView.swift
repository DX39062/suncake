//
//  MainView.swift
//  suncake
//
//  Created by yangxin on 2026/1/8.
//

internal import SwiftUI

enum MainTab: Hashable, CaseIterable {
    case shelf
    case search
    case source
    case settings
    
    var title: String {
        switch self {
        case .shelf: return "书架"
        case .search: return "搜索"
        case .source: return "书源"
        case .settings: return "设置"
        }
    }
    
    var icon: String {
        switch self {
        case .shelf: return "books.vertical"
        case .search: return "magnifyingglass"
        case .source: return "network"
        case .settings: return "gear"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var sourceStore: SourceStore
    @State private var selectedTab: MainTab? = .shelf
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(MainTab.allCases, id: \.self) { tab in
                    NavigationLink(value: tab) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("阅读")
        } detail: {
            if let tab = selectedTab {
                switch tab {
                case .shelf:
                    ShelfPlaceholderView()
                case .search:
                    SearchView()
                case .source:
                    SourceListView()
                case .settings:
                    SettingsPlaceholderView()
                }
            } else {
                Text("请选择一个菜单")
            }
        }
    }
}

// MARK: - Placeholder Views

struct ShelfPlaceholderView: View {
    var body: some View {
        Text("书架 - 开发中")
            .font(.title)
            .foregroundColor(.secondary)
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        Text("设置 - 开发中")
            .font(.title)
            .foregroundColor(.secondary)
    }
}

// MARK: - Search View (Restored due to project file missing reference)

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
                    print("DEBUG UI: 开始执行搜索点击事件")
                    print("DEBUG UI: 启用的书源数量为: \(sourceStore.sources.filter { $0.enabled }.count)")
                    Task {
                        performSearch()
                    }
                }
                .disabled(searchText.isEmpty || isSearching)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor)) 
            
            Divider()
            
            // Progress Bar
            if isSearching {
                ProgressView()
                    .progressViewStyle(.linear)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }
            
            // Content
            if searchResults.isEmpty {
                if isSearching {
                    // While searching but empty results so far, show nothing or loading state
                    Spacer()
                } else {
                    // Not searching, empty results
                    VStack {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.5))
                            .padding(.bottom)
                        Text("搜搜看吧")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            } else {
                List(searchResults) { book in
                    BookRowView(book: book)
                        .contextMenu {
                            Button {
                                // Action to add to shelf
                                print("Add \(book.name) to shelf")
                            } label: {
                                Label("加入书架", systemImage: "plus.circle")
                            }
                        }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("网络搜索")
    }
    
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        // Reset state
        isSearching = true
        searchResults = []
        
        // Get enabled sources
        let enabledSources = sourceStore.sources.filter { $0.enabled }
        
        // Start search stream
        Task {
            let stream = await searchModel.search(keyword: searchText, sources: enabledSources)
            
            for await books in stream {
                await MainActor.run {
                    self.searchResults.append(contentsOf: books)
                }
            }
            
            await MainActor.run {
                self.isSearching = false
            }
        }
    }
}

struct BookRowView: View {
    let book: Book
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Cover Image
            AsyncImage(url: URL(string: book.coverUrl ?? "")) { phase in
                switch phase {
                case .empty:
                    Color.secondary.opacity(0.2)
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Color.secondary.opacity(0.2)
                        .overlay(
                            Image(systemName: "book.closed")
                                .foregroundColor(.secondary)
                        )
                @unknown default:
                    Color.secondary.opacity(0.2)
                }
            }
            .frame(width: 50, height: 70)
            .cornerRadius(4)
            .clipped()
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(book.author)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                HStack {
                    Text(book.originName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    
                    if let kind = book.kind {
                        Text(kind)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    MainView()
        .environmentObject(SourceStore())
}
