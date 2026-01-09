internal import SwiftUI
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

class ReaderViewModel: ObservableObject {
    @Published var content: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var currentChapterIndex: Int
    @Published var title: String = ""
    
    let bookId: String
    let source: BookSource
    let chapters: [Book.Chapter]
    
    init(bookId: String, source: BookSource, chapters: [Book.Chapter], initialIndex: Int) {
        self.bookId = bookId
        self.source = source
        self.chapters = chapters
        self.currentChapterIndex = initialIndex
        if initialIndex >= 0 && initialIndex < chapters.count {
            self.title = chapters[initialIndex].title
        }
    }
    
    func loadContent() {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return }
        let chapter = chapters[currentChapterIndex]
        
        // Calculate next chapter URL for multi-page detection
        var nextChapterUrl: String?
        if currentChapterIndex + 1 < chapters.count {
            nextChapterUrl = chapters[currentChapterIndex + 1].url
        }
        
        self.title = chapter.title
        self.isLoading = true
        self.errorMessage = nil
        self.content = "" 
        
        Task {
            do {
                print("DEBUG READER: Loading content for \(chapter.title), url: \(chapter.url)")
                let rawContent = try await WebBook.getContent(source: source, chapterUrl: chapter.url, nextChapterUrl: nextChapterUrl)
                print("DEBUG READER: Raw content length: \(rawContent.count)")
                if rawContent.isEmpty {
                     print("DEBUG READER: Raw content is empty!")
                }
                
                let processedContent = ContentProcessor.shared.process(content: rawContent, source: source)
                print("DEBUG READER: Processed content length: \(processedContent.count)")
                
                await MainActor.run {
                    self.content = processedContent
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "加载失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func nextChapter() {
        if currentChapterIndex < chapters.count - 1 {
            currentChapterIndex += 1
            loadContent()
        }
    }
    
    func previousChapter() {
        if currentChapterIndex > 0 {
            currentChapterIndex -= 1
            loadContent()
        }
    }
}

struct ReaderView: View {
    @StateObject var viewModel: ReaderViewModel
    @EnvironmentObject var shelfStore: ShelfStore
    @Environment(\.dismiss) var dismiss
    
    @State private var fontSize: CGFloat = 18
    
    init(bookId: String, source: BookSource, chapters: [Book.Chapter], initialIndex: Int) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(bookId: bookId, source: source, chapters: chapters, initialIndex: initialIndex))
    }
    
    var body: some View {
        ZStack {
            #if os(macOS)
            Color(NSColor.textBackgroundColor).ignoresSafeArea()
            #else
            Color(UIColor.systemBackground).ignoresSafeArea()
            #endif
            
            if viewModel.isLoading {
                ProgressView("正在加载...")
            } else if let error = viewModel.errorMessage {
                VStack {
                    Text(error)
                        .foregroundColor(.red)
                    Button("重试") {
                        viewModel.loadContent()
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Text(viewModel.title)
                                .font(.title2)
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.bottom, 10)
                            
                            Text(viewModel.content)
                                .font(.system(size: fontSize))
                                .lineSpacing(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding()
                        .id("top") 
                    }
                    .onChange(of: viewModel.content) { _ in
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .automatic) {
                HStack {
                    Button(action: { viewModel.previousChapter() }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentChapterIndex <= 0)
                    
                    Button(action: { viewModel.nextChapter() }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentChapterIndex >= viewModel.chapters.count - 1)
                }
            }
            #else
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { viewModel.previousChapter() }) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(viewModel.currentChapterIndex <= 0)
                    
                    Button(action: { viewModel.nextChapter() }) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(viewModel.currentChapterIndex >= viewModel.chapters.count - 1)
                }
            }
            #endif
        }
        .onAppear {
            viewModel.loadContent()
        }
        .onChange(of: viewModel.currentChapterIndex) { newIndex in
            shelfStore.updateProgress(bookUrl: viewModel.bookId, index: newIndex, pos: 0, title: viewModel.title)
        }
        .onChange(of: viewModel.title) { newTitle in
             shelfStore.updateProgress(bookUrl: viewModel.bookId, index: viewModel.currentChapterIndex, pos: 0, title: newTitle)
        }
    }
}
