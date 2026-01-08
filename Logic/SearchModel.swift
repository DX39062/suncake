import Foundation
import SwiftSoup

class SearchModel {
    
    func search(keyword: String, sources: [BookSource]) async -> AsyncStream<[Book]> {
        // 这一行必须在返回 AsyncStream 之前执行
        print("DEBUG MODEL: search 函数被触发，关键字: \(keyword)")
        
        return AsyncStream { continuation in
            // 在流的内部启动一个独立的 Task 处理并发
            Task {
                print("DEBUG MODEL: AsyncStream 内部 Task 启动")
                await withTaskGroup(of: [Book].self) { group in
                    for source in sources {
                        group.addTask {
                            return await self.searchSingleSource(keyword: keyword, source: source)
                        }
                    }
                    
                    for await books in group {
                        if !books.isEmpty {
                            print("DEBUG MODEL: 产生结果，数量: \(books.count)")
                            continuation.yield(books)
                        }
                    }
                    print("DEBUG MODEL: 所有书源搜索任务结束")
                    continuation.finish()
                }
            }
        }
    }
    
    private func searchSingleSource(keyword: String, source: BookSource) async -> [Book] {
        guard source.enabled, let searchUrlRaw = source.ruleSearch?.searchUrl else { return [] }
        
        print("DEBUG MODEL: 正在处理源 -> \(source.bookSourceName)")
        
        do {
            let request = try await UrlAnalyzer.getRequest(urlStr: searchUrlRaw, keyword: keyword, source: source)
            
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 10
            let session = URLSession(configuration: config)
            
            let (data, _) = try await session.data(for: request)
            
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                print("DEBUG MODEL: \(source.bookSourceName) 编码失败")
                return []
            }
            
            print("DEBUG MODEL: \(source.bookSourceName) 请求成功, 长度: \(html.count)")
            
            let ruleEngine = RuleEngine(source: source)
            let listRule = source.ruleSearch?.bookList ?? ""
            let elements = ruleEngine.elements(content: html, ruleStr: listRule)
            
            var books: [Book] = []
            for element in (elements as? [Element] ?? []) {
                let name = ruleEngine.text(element: element, ruleStr: source.ruleSearch?.name ?? "")
                let author = ruleEngine.text(element: element, ruleStr: source.ruleSearch?.author ?? "")
                let bookUrl = ruleEngine.text(element: element, ruleStr: source.ruleSearch?.bookUrl ?? "")
                
                if name.isEmpty || bookUrl.isEmpty { continue }
                
                let fullBookUrl = normalizeUrl(bookUrl, baseUrl: source.bookSourceUrl)
                var coverUrl = ruleEngine.text(element: element, ruleStr: source.ruleSearch?.coverUrl ?? "")
                if !coverUrl.isEmpty { coverUrl = normalizeUrl(coverUrl, baseUrl: source.bookSourceUrl) }
                
                books.append(Book(
                    name: name,
                    author: author,
                    coverUrl: coverUrl.isEmpty ? nil : coverUrl,
                    bookUrl: fullBookUrl,
                    origin: source.bookSourceUrl,
                    originName: source.bookSourceName
                ))
            }
            return books
        } catch {
            print("DEBUG MODEL: \(source.bookSourceName) 异常: \(error.localizedDescription)")
            return []
        }
    }
    
    private func normalizeUrl(_ url: String, baseUrl: String) -> String {
        if url.lowercased().hasPrefix("http") { return url }
        if let base = URL(string: baseUrl), let full = URL(string: url, relativeTo: base) {
            return full.absoluteString
        }
        return baseUrl + url
    }
}