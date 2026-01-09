import Foundation
import SwiftSoup

class BookDetailModel: ObservableObject {
    @Published var book: Book
    @Published var intro: String = ""
    @Published var chapters: [Book.Chapter] = []
    @Published var isLoading = false
    
    private let ruleEngine: RuleEngine
    private let source: BookSource
    
    init(book: Book, source: BookSource) {
        self.book = book
        self.source = source
        self.ruleEngine = RuleEngine(source: source)
    }
    
    func loadDetails() async {
        await MainActor.run { isLoading = true }
        
        do {
            // 1. 获取详情页 HTML
            let html = try await UrlAnalyzer.shared.fetchHtml(url: book.bookUrl, source: source)
            
            // 2. 解析详情信息 (简介、分类等)
            let infoRule = source.ruleBookInfo
            let extractedIntro = ruleEngine.text(element: html, ruleStr: infoRule?.intro ?? "")
            
            // 尝试更新书籍基本信息
            let updatedName = ruleEngine.text(element: html, ruleStr: infoRule?.name ?? "")
            let updatedAuthor = ruleEngine.text(element: html, ruleStr: infoRule?.author ?? "")
            let updatedCover = ruleEngine.text(element: html, ruleStr: infoRule?.coverUrl ?? "")
            let updatedKind = ruleEngine.text(element: html, ruleStr: infoRule?.kind ?? "")
            
            await MainActor.run {
                if !updatedName.isEmpty { self.book.name = updatedName }
                if !updatedAuthor.isEmpty { self.book.author = updatedAuthor }
                if !updatedCover.isEmpty { self.book.coverUrl = updatedCover }
                if !updatedKind.isEmpty { self.book.kind = updatedKind }
                self.intro = extractedIntro
            }
            
            // 3. 解析目录列表
            var tocHtml = html
            let tocUrlRule = infoRule?.tocUrl ?? ""
            if !tocUrlRule.isEmpty {
                let realTocUrl = ruleEngine.text(element: html, ruleStr: tocUrlRule)
                if !realTocUrl.isEmpty && realTocUrl != book.bookUrl {
                    if let nextHtml = try? await UrlAnalyzer.shared.fetchHtml(url: realTocUrl, source: source) {
                        tocHtml = nextHtml
                    }
                }
            }
            
            let tocRule = source.ruleToc
            let chapterElements = ruleEngine.elements(content: tocHtml, ruleStr: tocRule?.chapterList ?? "")
            
            var parsedChapters: [Book.Chapter] = []
            for (index, element) in chapterElements.enumerated() {
                let title = ruleEngine.text(element: element, ruleStr: tocRule?.chapterName ?? "")
                let url = ruleEngine.text(element: element, ruleStr: tocRule?.chapterUrl ?? "")
                
                // 检查是否是卷名
                var isVolume = false
                if let isVolumeRule = tocRule?.isVolume, !isVolumeRule.isEmpty {
                    let isVolumeRes = ruleEngine.text(element: element, ruleStr: isVolumeRule)
                    isVolume = (isVolumeRes == "true" || isVolumeRes == "1")
                }
                
                parsedChapters.append(Book.Chapter(title: title, url: url, index: index, isVolume: isVolume))
            }
            
            await MainActor.run {
                self.chapters = parsedChapters
                self.isLoading = false
            }
        } catch {
            print("Error loading details: \(error)")
            await MainActor.run { isLoading = false }
        }
    }
}