import Foundation
import SwiftSoup
import CoreFoundation

class RuleEngine {
    let source: BookSource
    private let jsRuntime = JSRuntime() // 必须打通 JSRuntime.swift
    
    init(source: BookSource) {
        self.source = source
    }
    
    // MARK: - Core Methods
    
    /// 解析列表元素（如搜索结果列表）
    func elements(content: String, ruleStr: String) -> [Any] {
        guard !ruleStr.isEmpty else { return [] }
        
        // 1. 处理顶级 JS 规则
        if isJsRule(ruleStr) {
            return evalJSList(ruleStr, result: content)
        }
        
        do {
            // 解析初始文档
            let doc = try SwiftSoup.parse(content, source.bookSourceUrl)
            var currentElements = Elements([doc])
            
            // 处理 @ 分隔的级联规则
            let steps = ruleStr.components(separatedBy: "@")
            for step in steps {
                let cleanStep = step.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanStep.isEmpty { continue }
                
                // 级联中的 JS 转换
                if isJsRule(cleanStep) {
                    let combinedHtml = currentElements.map { (try? $0.outerHtml()) ?? "" }.joined(separator: "\n")
                    return evalJSList(cleanStep, result: combinedHtml)
                }
                
                // 转换并执行 CSS 选择
                let selector = mapLegadoSelectorToCss(cleanStep)
                currentElements = try currentElements.select(selector)
            }
            return currentElements.array()
        } catch {
            print("RuleEngine Error: \(error.localizedDescription)")
            return []
        }
    }
    
    /// 解析具体字段（如书名、链接）
    func text(element: Any, ruleStr: String) -> String {
        let rule = ruleStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.isEmpty { return elementToText(element) }
        
        // 1. 处理 JS 规则
        if isJsRule(rule) {
            return evalJSText(rule, element: element)
        }
        
        // 2. 处理复合规则 (如 class.title@text)
        let parts = rule.components(separatedBy: "@")
        var current: Any = element
        
        for (index, part) in parts.enumerated() {
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if p.isEmpty { continue }
            
            let isLast = index == parts.count - 1
            if isLast {
                // 最后一级：提取 Action 或 最终选择器
                return handleActionOrExtract(current, action: p)
            } else {
                // 中间级：向下钻取
                if let el = current as? Element {
                    let selector = mapLegadoSelectorToCss(p)
                    if let next = try? el.select(selector).first() {
                        current = next
                    } else { return "" }
                }
            }
        }
        return elementToText(current)
    }

    // MARK: - Helper Methods
    
    private func isJsRule(_ rule: String) -> Bool {
        return rule.contains("@js:") || rule.hasPrefix("<js>") || rule.contains("{{")
    }

    /// 将 Legado 的伪 CSS 转换为标准 CSS
    private func mapLegadoSelectorToCss(_ part: String) -> String {
        var p = part
        if p.hasPrefix("class.") { p = "." + p.dropFirst(6) }
        else if p.hasPrefix("id.") { p = "#" + p.dropFirst(3) }
        else if p.hasPrefix("tag.") { p = String(p.dropFirst(4)) }
        return p
    }

    private func handleActionOrExtract(_ current: Any, action: String) -> String {
        guard let el = current as? Element else {
            return (current as? String) ?? ""
        }
        
        switch action {
        case "text": return (try? el.text()) ?? ""
        case "ownText": return el.ownText()
        case "html": return (try? el.outerHtml()) ?? ""
        case "href", "src":
            let attr = (try? el.attr(action)) ?? ""
            return normalizeUrl(attr)
        case "abs:href", "abs:src":
            return (try? el.attr(action)) ?? ""
        default:
            // 如果 action 是选择器，则提取该选择器的 text
            let selector = mapLegadoSelectorToCss(action)
            if let target = try? el.select(selector).first() {
                return (try? target.text()) ?? ""
            }
            // 尝试提取任意属性
            return (try? el.attr(action)) ?? ""
        }
    }

    private func elementToText(_ element: Any) -> String {
        if let el = element as? Element { return (try? el.text()) ?? "" }
        return (element as? String) ?? ""
    }

    private func normalizeUrl(_ url: String) -> String {
        if url.isEmpty || url.lowercased().hasPrefix("http") { return url }
        guard let base = URL(string: source.bookSourceUrl) else { return url }
        return URL(string: url, relativeTo: base)?.absoluteString ?? url
    }

    // MARK: - JS Execution (需确保 JSRuntime.swift 实现 extractAndEval)
    
    private func evalJSList(_ jsStr: String, result: String) -> [Any] {
        let context = ["result": result, "baseUrl": source.bookSourceUrl]
        let output = jsRuntime.extractAndEval(text: jsStr, with: context)
        return output as? [Any] ?? (output != nil ? ["\(output!)"] : [])
    }
    
    private func evalJSText(_ jsStr: String, element: Any) -> String {
        let resultValue = (try? (element as? Element)?.outerHtml()) ?? (element as? String) ?? ""
        let context: [String: Any] = ["result": resultValue, "baseUrl": source.bookSourceUrl]
        return "\(jsRuntime.extractAndEval(text: jsStr, with: context) ?? "")"
    }
}

// MARK: - Search Support

class WebBook {
    static func searchBook(source: BookSource, keyword: String) async throws -> [Book] {
        guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else { return [] }
        let request = try await UrlAnalyzer.getRequest(urlStr: searchUrl, keyword: keyword, source: source)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { return [] }
        
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding("GBK" as CFString)))) else { return [] }
        
        let engine = RuleEngine(source: source)
        let elements = engine.elements(content: html, ruleStr: source.ruleSearch?.bookList ?? "")
        
        var books: [Book] = []
        for element in elements {
            let name = engine.text(element: element, ruleStr: source.ruleSearch?.name ?? "")
            if name.isEmpty { continue }
            books.append(Book(
                name: name,
                author: engine.text(element: element, ruleStr: source.ruleSearch?.author ?? ""),
                coverUrl: engine.text(element: element, ruleStr: source.ruleSearch?.coverUrl ?? ""),
                bookUrl: engine.text(element: element, ruleStr: source.ruleSearch?.bookUrl ?? ""),
                origin: source.bookSourceUrl,
                originName: source.bookSourceName,
                intro: engine.text(element: element, ruleStr: source.ruleSearch?.intro ?? ""),
                kind: engine.text(element: element, ruleStr: source.ruleSearch?.kind ?? ""),
                latestChapterTitle: engine.text(element: element, ruleStr: source.ruleSearch?.lastChapter ?? "")
            ))
        }
        return books
    }
}

class SearchModel {
    func search(keyword: String, sources: [BookSource]) async -> AsyncStream<[Book]> {
        AsyncStream { continuation in
            let task = Task {
                await withTaskGroup(of: [Book].self) { group in
                    for source in sources {
                        group.addTask {
                            do { return try await WebBook.searchBook(source: source, keyword: keyword) }
                            catch { return [] }
                        }
                    }
                    for await results in group {
                        if !results.isEmpty { continuation.yield(results) }
                    }
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}