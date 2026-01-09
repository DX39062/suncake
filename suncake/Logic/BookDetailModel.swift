import Foundation
import Combine
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
            print("DEBUG TOC: Starting loadDetails for \(book.name), url: \(book.bookUrl)")
            // 1. 获取详情页 HTML
            let html = try await UrlAnalyzer.shared.fetchHtml(url: book.bookUrl, source: source)
            
            // 应用详情页的 init 规则（如果存在）
            var detailRoot: Any = html
            if let initRule = source.ruleBookInfo?.`init`, !initRule.isEmpty {
                let elements = ruleEngine.elements(content: html, ruleStr: initRule)
                if let first = elements.first {
                    detailRoot = first
                    print("DEBUG TOC: Applied init rule, root is now Element")
                }
            }
            
            // 2. 解析详情信息 (简介、分类等)
            let infoRule = source.ruleBookInfo
            let extractedIntro = ruleEngine.text(element: detailRoot, ruleStr: infoRule?.intro ?? "")
            
            // 尝试更新书籍基本信息
            let updatedName = ruleEngine.text(element: detailRoot, ruleStr: infoRule?.name ?? "")
            let updatedAuthor = ruleEngine.text(element: detailRoot, ruleStr: infoRule?.author ?? "")
            let updatedCover = ruleEngine.text(element: detailRoot, ruleStr: infoRule?.coverUrl ?? "")
            let updatedKind = ruleEngine.text(element: detailRoot, ruleStr: infoRule?.kind ?? "")
            
            await MainActor.run {
                if !updatedName.isEmpty { self.book.name = updatedName }
                if !updatedAuthor.isEmpty { self.book.author = updatedAuthor }
                if !updatedCover.isEmpty { self.book.coverUrl = updatedCover }
                if !updatedKind.isEmpty { self.book.kind = updatedKind }
                self.intro = extractedIntro
            }
            
            // 3. 解析目录列表
            var tocHtml = html
            var currentBaseUrl = book.bookUrl
            let tocUrlRule = infoRule?.tocUrl ?? ""
            if !tocUrlRule.isEmpty {
                let realTocUrl = ruleEngine.text(element: detailRoot, ruleStr: tocUrlRule)
                print("DEBUG TOC: Found tocUrl from rule: \(realTocUrl)")
                if !realTocUrl.isEmpty && realTocUrl != book.bookUrl {
                    currentBaseUrl = realTocUrl
                    if let nextHtml = try? await UrlAnalyzer.shared.fetchHtml(url: realTocUrl, source: source) {
                        tocHtml = nextHtml
                        print("DEBUG TOC: Fetched separate TOC page, length: \(tocHtml.count)")
                    }
                }
            }
            
            let tocRule = source.ruleToc
            let chapterListRule = tocRule?.chapterList ?? ""
            print("DEBUG TOC: Applying chapterList rule: \(chapterListRule)")
            let chapterElements = ruleEngine.elements(content: tocHtml, ruleStr: chapterListRule)
            print("DEBUG TOC: Found \(chapterElements.count) chapter elements")
            
            var parsedChapters: [Book.Chapter] = []
            for (index, element) in chapterElements.enumerated() {
                let title = ruleEngine.text(element: element, ruleStr: tocRule?.chapterName ?? "")
                var url = ruleEngine.text(element: element, ruleStr: tocRule?.chapterUrl ?? "")
                
                // 手动补全 URL（如果 RuleEngine 没补全）
                if !url.isEmpty && !url.hasPrefix("http") {
                    if let base = URL(string: currentBaseUrl) {
                        url = URL(string: url, relativeTo: base)?.absoluteString ?? url
                    }
                }
                
                // 检查是否是卷名
                var isVolume = false
                if let isVolumeRule = tocRule?.isVolume, !isVolumeRule.isEmpty {
                    let isVolumeRes = ruleEngine.text(element: element, ruleStr: isVolumeRule)
                    isVolume = (isVolumeRes == "true" || isVolumeRes == "1")
                }
                
                parsedChapters.append(Book.Chapter(title: title, url: url, index: index, isVolume: isVolume))
            }
            
            if parsedChapters.isEmpty && !chapterListRule.isEmpty {
                print("DEBUG TOC: WARNING! Parsed chapters is empty but rule was not empty.")
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