internal import SwiftUI

struct BookGridView: View {
    @EnvironmentObject var shelfStore: ShelfStore
    @EnvironmentObject var sourceStore: SourceStore
    
    private let columns = [
        GridItem(.adaptive(minimum: 120), spacing: 20)
    ]
    
    var body: some View {
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
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(shelfStore.books) { book in
                        // Find the source for this book
                        if let source = sourceStore.sources.first(where: { $0.bookSourceUrl == book.origin }) {
                            NavigationLink(destination: ShelfBookDestination(book: book, source: source)) {
                                BookGridItem(book: book)
                            }
                            .buttonStyle(.plain) // Remove default link styling
                            .contextMenu {
                                Button {
                                    shelfStore.deleteBook(book)
                                } label: {
                                    Label("移出书架", systemImage: "trash")
                                }
                            }
                        } else {
                            // Source missing
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

struct BookGridItem: View {
    let book: Book
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover - Fixed Ratio roughly 3:4
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
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .clipped()
            .cornerRadius(8)
            .shadow(radius: 2)
            
            VStack(alignment: .leading, spacing: 2) {
                // Title - Fixed height for exactly 2 lines
                Text(book.name)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .foregroundColor(.primary)
                    .frame(height: 36, alignment: .topLeading)
                
                // Progress or Author - Fixed height for 1 line
                Group {
                    if let title = book.durChapterTitle, !title.isEmpty {
                        Text(title)
                    } else {
                        Text(book.author)
                    }
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(height: 16, alignment: .leading)
            }
        }
        .padding(.bottom, 4)
    }
}
