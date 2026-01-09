internal import SwiftUI

struct BookDetailView: View {
    let initialBook: Book
    let source: BookSource
    @StateObject private var viewModel: BookDetailModel
    
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
                            
                            Text(viewModel.intro)
                                .font(.body)
                                .padding(.vertical, 8)
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
                                NavigationLink(destination: ReaderView(source: source, chapters: viewModel.chapters, initialIndex: chapter.index)) {
                                    Text(chapter.title)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(viewModel.book.name)
        .task {
            await viewModel.loadDetails()
        }
    }
}