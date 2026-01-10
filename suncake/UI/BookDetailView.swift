internal import SwiftUI

struct BookDetailView: View {
    let initialBook: Book
    let source: BookSource
    @StateObject private var viewModel: BookDetailModel
    @EnvironmentObject var shelfStore: ShelfStore
    
    init(book: Book, source: BookSource) {
        self.initialBook = book
        self.source = source
        _viewModel = StateObject(wrappedValue: BookDetailModel(book: book, source: source))
    }
    
    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("正在解析目录...")
            } else {
                List {
                    Section(header: Text("书籍简介")) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 15) {
                                // 封面
                                AsyncImage(url: URL(string: viewModel.book.coverUrl ?? "")) { image in
                                    image.resizable()
                                        .aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 90, height: 120)
                                .cornerRadius(4)
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(viewModel.book.name)
                                        .font(.headline)
                                    Text(viewModel.book.author)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if let kind = viewModel.book.kind, !kind.isEmpty {
                                        Text(kind)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            
                            Text(viewModel.intro ?? "")
                                .font(.body)
                                .padding(.vertical, 8)
                        }
                    }
                    
                    // Continue Reading Button
                    if shelfStore.inShelf(viewModel.book.bookUrl) && !viewModel.chapters.isEmpty {
                        Section {
                            NavigationLink(destination: ReaderView(bookId: viewModel.book.bookUrl, source: source, chapters: viewModel.chapters, initialIndex: viewModel.book.durChapterIndex)) {
                                HStack {
                                    Image(systemName: "book.fill")
                                        .foregroundColor(.accentColor)
                                    VStack(alignment: .leading) {
                                        Text("继续阅读")
                                            .font(.headline)
                                        if let title = viewModel.book.durChapterTitle {
                                            Text("上次读到: \(title)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("开始阅读")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    Section(header: Text("目录 (共 \(viewModel.chapters.count) 章)")) {
                        ForEach(viewModel.chapters) { chapter in
                            if chapter.isVolume {
                                Text(chapter.title)
                                    .font(.headline)
                                    .padding(.vertical, 4)
                                    .listRowBackground(Color.gray.opacity(0.1))
                            } else {
                                NavigationLink(destination: ReaderView(bookId: viewModel.book.bookUrl, source: source, chapters: viewModel.chapters, initialIndex: chapter.index)) {
                                    Text(chapter.title)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.book.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if shelfStore.inShelf(viewModel.book.bookUrl) {
                    Button("移除书架") {
                        shelfStore.deleteBook(viewModel.book)
                    }
                    .foregroundColor(.red)
                } else {
                    Button("加入书架") {
                        var bookToAdd = viewModel.book
                        // Ensure essential fields are set
                        if bookToAdd.origin.isEmpty { bookToAdd.origin = source.bookSourceUrl }
                        if bookToAdd.originName.isEmpty { bookToAdd.originName = source.bookSourceName }
                        shelfStore.addBook(bookToAdd)
                    }
                }
            }
        }
        .task {
            // Check if book is in shelf to get latest progress/info
            if let cachedBook = shelfStore.getBook(initialBook.bookUrl) {
                // Update viewModel with cached info first
                viewModel.book = cachedBook
                if let intro = cachedBook.intro { viewModel.intro = intro }
            }
            
            await viewModel.loadDetails(shelfStore: shelfStore)
            
            // If in shelf, update shelf with latest details
            if shelfStore.inShelf(viewModel.book.bookUrl) {
                shelfStore.updateBookInfo(viewModel.book)
            }
        }
    }
}
