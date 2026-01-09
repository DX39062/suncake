internal import SwiftUI

struct BookGridView: View {
    @EnvironmentObject var shelfStore: ShelfStore
    @EnvironmentObject var sourceStore: SourceStore
    
    private let columns = [
        GridItem(.adaptive(minimum: 100), spacing: 16)
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                if shelfStore.books.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("书架空空如也")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("去发现页找点书看吧")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 100)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(shelfStore.books) { book in
                            // Find the source for this book
                            if let source = sourceStore.sources.first(where: { $0.bookSourceUrl == book.origin }) {
                                NavigationLink(destination: BookDetailView(book: book, source: source)) {
                                    BookGridItem(book: book)
                                }
                            } else {
                                // Source missing? Still show but maybe warn?
                                // For now, just show item, but clicking might be an issue.
                                // We can't open BookDetailView without source.
                                BookGridItem(book: book)
                                    .opacity(0.5)
                                    .overlay(
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.yellow)
                                            .padding(4)
                                            .background(Color.black.opacity(0.6))
                                            .cornerRadius(4)
                                            .padding(4),
                                        alignment: .topTrailing
                                    )
                                    .onTapGesture {
                                        // Maybe alert: Source missing
                                        print("Source missing for book: \(book.name)")
                                    }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("书架")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Action for search or more options
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        // Action for search or more options
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                }
                #endif
            }
        }
    }
}

struct BookGridItem: View {
    let book: Book
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover
            AsyncImage(url: URL(string: book.displayCover)) { phase in
                switch phase {
                case .empty:
                    Color.gray.opacity(0.2)
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    Color.gray.opacity(0.3)
                        .overlay(
                            Image(systemName: "book.closed")
                                .foregroundColor(.white)
                        )
                @unknown default:
                    Color.gray.opacity(0.2)
                }
            }
            .frame(height: 140)
            .cornerRadius(8)
            .shadow(radius: 2)
            
            // Title
            Text(book.name)
                .font(.headline)
                .lineLimit(2)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Progress or Author
            if book.durChapterTitle != nil {
                Text(book.durChapterTitle!)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text(book.author)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
