import Foundation
import SwiftSoup
import CoreFoundation

class SearchModel {
    
    // MARK: - API
    
    /// Searches for books across multiple sources concurrently.
    /// Returns an async stream of results as they become available.
    func search(keyword: String, sources: [BookSource]) async -> AsyncStream<[Book]> {
        print("DEBUG: 搜索流程已启动，关键字: \(keyword), 书源数: \(sources.count)")
        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: [Book].self) { group in
                    for source in sources {
                        print("DEBUG: 正在搜索源: \(source.bookSourceName)")
                        group.addTask {
                            return await self.searchSingleSource(keyword: keyword, source: source)
                        }
                    }
                    
                    for await books in group {
                        if !books.isEmpty {
                            continuation.yield(books)
                        }
                    }
                    continuation.finish()
                }
            }
        }
    }
    
    // MARK: - Single Source Processing
    
    private func searchSingleSource(keyword: String, source: BookSource) async -> [Book] {
        guard source.enabled, let searchRule = source.ruleSearch, let searchUrlRaw = source.searchUrl else {
            return []
        }
        
        // 1. Prepare Request
        // Detect charset from options for response decoding
        let (_, options) = UrlAnalyzer.splitUrlAndOptions(searchUrlRaw)
        let charset = options?.charset ?? "utf-8"
        let requestCharset = getEncoding(charset: charset)
        
        // TODO: Handle page replacement {{page}} -> 1 for search
        // Note: {{key}} replacement is now handled by UrlAnalyzer
        let finalUrlStr = searchUrlRaw.replacingOccurrences(of: "{{page}}", with: "1")
        
        do {
            // Pass keyword to UrlAnalyzer for encoding and replacement
            let request = try await UrlAnalyzer.getRequest(urlStr: finalUrlStr, keyword: keyword, source: source)
            
            // 2. Fetch Data
            // Use custom session configuration for timeout
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10 // 10s timeout
            let session = URLSession(configuration: config)
            
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return [] }
            
            // 3. Decode Data
            // Strategy: 
            // 1. Try specified charset from rule.
            // 2. If failed (or default utf-8 failed), try GBK (common for Chinese sites).
            // 3. Fallback to UTF-8 (if not already tried) or ISO-8859-1.
            
            var content: String? = nil
            
            // Try specified
            content = String(data: data, encoding: requestCharset)
            
            // If failed, try GBK (if not already tried)
            if content == nil && requestCharset != getEncoding(charset: "gbk") {
                content = String(data: data, encoding: getEncoding(charset: "gbk"))
            }
            
            // If still nil, try UTF-8 (if not already tried)
            if content == nil && requestCharset != .utf8 {
                content = String(data: data, encoding: .utf8)
            }
            
            // Fallback
            if content == nil {
                content = String(data: data, encoding: .isoLatin1)
            }
            
            guard let finalContent = content, !finalContent.isEmpty else {
                print("DEBUG: Failed to decode content for \(source.bookSourceName)")
                return []
            }
            
            // 4. Parse Data
            let ruleEngine = RuleEngine(source: source)
            
            // Book List Rule
            let listRule = searchRule.bookList ?? ""
            guard !listRule.isEmpty else { return [] }
            
            let elements = ruleEngine.elements(content: finalContent, ruleStr: listRule)
            
            var books: [Book] = []
            
            for element in elements {
                // Extract fields
                let name = ruleEngine.text(element: element, ruleStr: searchRule.name ?? "")
                let author = ruleEngine.text(element: element, ruleStr: searchRule.author ?? "")
                let bookUrl = ruleEngine.text(element: element, ruleStr: searchRule.bookUrl ?? "")
                
                // Validate essential fields
                if name.isEmpty || bookUrl.isEmpty { continue }
                
                // Extract optional fields
                var coverUrl = ruleEngine.text(element: element, ruleStr: searchRule.coverUrl ?? "")
                if !coverUrl.isEmpty {
                    // Normalize URL if relative
                    coverUrl = normalizeUrl(coverUrl, baseUrl: source.bookSourceUrl)
                }
                
                var fullBookUrl = normalizeUrl(bookUrl, baseUrl: source.bookSourceUrl)

                let intro = ruleEngine.text(element: element, ruleStr: searchRule.intro ?? "")
                let kind = ruleEngine.text(element: element, ruleStr: searchRule.kind ?? "")
                let lastChapter = ruleEngine.text(element: element, ruleStr: searchRule.lastChapter ?? "")
                
                let book = Book(
                    name: name,
                    author: author,
                    coverUrl: coverUrl.isEmpty ? nil : coverUrl,
                    bookUrl: fullBookUrl,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName,
                    intro: intro.isEmpty ? nil : intro,
                    kind: kind.isEmpty ? nil : kind,
                    latestChapterTitle: lastChapter.isEmpty ? nil : lastChapter
                )
                books.append(book)
            }
            
            return books
            
        } catch {
            print("Search error for \(source.bookSourceName): \(error)")
            return []
        }
    }
    
    private func normalizeUrl(_ url: String, baseUrl: String) -> String {
        if url.lowercased().hasPrefix("http") { return url }
        
        // Simple join
        // Real implementation should use URL(string:relativeTo:)
        if let base = URL(string: baseUrl), let full = URL(string: url, relativeTo: base) {
            return full.absoluteString
        }
        return baseUrl + url
    }
    
    private func getEncoding(charset: String) -> String.Encoding {
        if charset.lowercased().contains("gb") { // gbk, gb2312, gb18030
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        return .utf8
    }
}
