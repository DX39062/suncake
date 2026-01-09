import Foundation
import SwiftSoup
import CoreFoundation

class RuleEngine {
    let source: BookSource
    var baseUrl: String
    private let jsRuntime = JSRuntime()
    
    init(source: BookSource) {
        self.source = source
        self.baseUrl = source.bookSourceUrl
    }
    
    // MARK: - Core Methods
    
    /// 解析列表元素
    func elements(content: String, ruleStr: String) -> [Any] {
        guard !ruleStr.isEmpty else { return [] }
        
        // 处理 || 优先级 (Fallback)
        let subRules = ruleStr.components(separatedBy: "||")
        for subRule in subRules {
            let result = elementsInternal(content: content, ruleStr: subRule.trimmingCharacters(in: .whitespacesAndNewlines))
            if !result.isEmpty {
                return result
            }
        }
        return []
    }
    
    private func elementsInternal(content: String, ruleStr: String) -> [Any] {
        if isJsRule(ruleStr) {
            return evalJSList(ruleStr, result: content)
        }
        
        // 1. 检测是否是 XPath
        if isXPath(ruleStr) {
            return evaluateXPath(content: content, xpath: ruleStr)
        }
        
        // 2. CSS/JSoup 解析逻辑
        do {
            var currentContent = content
            let (cleanRule, regexRule) = splitRegexRule(ruleStr)
            if let regex = regexRule {
                currentContent = applyRegex(content: currentContent, regexStr: regex)
            }
            
            let doc = try SwiftSoup.parse(currentContent, source.bookSourceUrl)
            var currentElements: [Element] = [doc]
            
            let steps = cleanRule.components(separatedBy: "@")
            for step in steps {
                let cleanStep = step.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanStep.isEmpty { continue }
                
                if isJsRule(cleanStep) {
                    let combinedHtml = currentElements.map { (try? $0.outerHtml()) ?? "" }.joined(separator: "\n")
                    return evalJSList(cleanStep, result: combinedHtml)
                }
                
                var nextElements: [Element] = []
                for el in currentElements {
                    let found = selectElements(from: el, rule: cleanStep)
                    nextElements.append(contentsOf: found)
                }
                currentElements = nextElements
                if currentElements.isEmpty { break }
            }
            return currentElements
        } catch {
            print("RuleEngine Error (elements): \(error.localizedDescription)")
            return []
        }
    }
    
    /// 解析具体字段
    func text(element: Any, ruleStr: String) -> String {
        let rule = ruleStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if rule.isEmpty {
            if element is String { return "" }
            return elementToText(element)
        }
        
        // 处理 || 优先级
        let subRules = rule.components(separatedBy: "||")
        for subRule in subRules {
            let result = textInternal(element: element, ruleStr: subRule.trimmingCharacters(in: .whitespacesAndNewlines))
            if !result.isEmpty {
                return result
            }
        }
        return ""
    }
    
    private func textInternal(element: Any, ruleStr: String) -> String {
        if isJsRule(ruleStr) {
            return evalJSText(ruleStr, element: element)
        }
        
        // 处理 XPath
        if isXPath(ruleStr) {
            return evaluateXPathText(element: element, xpath: ruleStr)
        }
        
        let (cleanRule, regexRule) = splitRegexRule(ruleStr)
        let steps = cleanRule.components(separatedBy: "@")
        var current: Any = element
        
        // 自动转换 HTML 字符串为 Element
        if let html = current as? String {
            if let doc = try? SwiftSoup.parse(html, source.bookSourceUrl) {
                current = doc
            }
        }
        
        for (index, step) in steps.enumerated() {
            let cleanStep = step.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanStep.isEmpty { continue }
            
            let isLast = index == steps.count - 1
            if isLast {
                let extracted = handleActionOrExtract(current, action: cleanStep)
                return regexRule != nil ? applyRegex(content: extracted, regexStr: regexRule!) : extracted
            } else {
                if let el = current as? Element {
                    if let next = selectElements(from: el, rule: cleanStep).first {
                        current = next
                    } else { return "" }
                }
            }
        }
        
        let finalText = elementToText(current)
        return regexRule != nil ? applyRegex(content: finalText, regexStr: regexRule!) : finalText
    }

    // MARK: - XPath Support
    
    private func isXPath(_ rule: String) -> Bool {
        return rule.hasPrefix("//") || rule.hasPrefix("./") || rule.hasPrefix("/")
    }
    
    private func evaluateXPath(content: String, xpath: String) -> [Any] {
        #if os(macOS)
        do {
            // 使用 XMLDocument 解析 HTML (TidyHTML 模式)
            let options = XMLNode.Options(rawValue: UInt(XMLDocument.ContentKind.html.rawValue) | XMLNode.Options.documentTidyHTML.rawValue)
            let doc = try XMLDocument(xmlString: content, options: options)
            return try doc.nodes(forXPath: xpath)
        } catch {
            print("DEBUG RuleEngine: XPath Error -> \(error)")
            return []
        }
        #else
        return [] // iOS 暂不支持原生 XMLDocument，需后续引入第三方库
        #endif
    }
    
    private func evaluateXPathText(element: Any, xpath: String) -> String {
        #if os(macOS)
        let targetNode: XMLNode?
        if let node = element as? XMLNode {
            targetNode = node
        } else {
            let html: String?
            if let el = element as? Element {
                html = try? el.outerHtml()
            } else if let els = element as? Elements {
                html = try? els.outerHtml()
            } else {
                html = element as? String
            }
            
            if let htmlStr = html {
                let options = XMLNode.Options(rawValue: UInt(XMLDocument.ContentKind.html.rawValue) | XMLNode.Options.documentTidyHTML.rawValue)
                targetNode = try? XMLDocument(xmlString: htmlStr, options: options)
            } else {
                targetNode = nil
            }
        }
        
        if let node = targetNode, let results = try? node.nodes(forXPath: xpath) {
            return results.compactMap { $0.stringValue }.joined(separator: "\n")
        }
        #endif
        return ""
    }

    // MARK: - Helper Methods
    
    private func isJsRule(_ rule: String) -> Bool {
        return rule.contains("@js:") || rule.hasPrefix("<js>") || rule.contains("{{")
    }
    
    private func splitRegexRule(_ rule: String) -> (String, String?) {
        if let range = rule.range(of: "##") {
            let clean = String(rule[..<range.lowerBound])
            let regex = String(rule[range.lowerBound...])
            return (clean, regex)
        }
        return (rule, nil)
    }
    
    private func applyRegex(content: String, regexStr: String) -> String {
        let parts = regexStr.components(separatedBy: "##").filter { !$0.isEmpty }
        guard parts.count >= 1 else { return content }
        let pattern = parts[0]
        let replacement = parts.count > 1 ? parts[1] : ""
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(content.startIndex..., in: content)
            return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: replacement)
        } catch {
            return content
        }
    }

    private func selectElements(from container: Element, rule: String) -> [Element] {
        var cleanRule = rule
        if rule.uppercased().hasPrefix("@CSS:") {
            cleanRule = String(rule.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let parts = cleanRule.components(separatedBy: ".")
        guard !parts.isEmpty else { return [] }
        
        var selector = ""
        var indexStr: String? = nil
        
        if parts[0] == "class" && parts.count >= 2 {
            selector = "." + parts[1]
            if parts.count > 2 { indexStr = parts[2] }
        } else if parts[0] == "id" && parts.count >= 2 {
            selector = "#" + parts[1]
            if parts.count > 2 { indexStr = parts[2] }
        } else if parts[0] == "tag" && parts.count >= 2 {
            selector = parts[1]
            if parts.count > 2 { indexStr = parts[2] }
        } else if parts[0] == "text" && parts.count >= 2 {
            // Support for text.someText selector
            let textToFind = parts[1]
            // Try to find elements that directly contain the text (more precise)
            do {
                var found = try container.select("*:containsOwn(\(textToFind))").array()
                if found.isEmpty {
                    // Fallback to any element containing the text
                    found = try container.select("*:contains(\(textToFind))").array()
                }
                if parts.count > 2 { indexStr = parts[2] }
                if let idx = indexStr {
                    return applyIndex(found, indexStr: idx)
                }
                return found
            } catch {
                return []
            }
        } else if parts[0] == "children" {
            let children = container.children().array()
            if parts.count > 1 { return applyIndex(children, indexStr: parts[1]) }
            return children
        } else {
            if parts.count > 1, let last = parts.last, isPureIndex(last) {
                selector = parts.dropLast().joined(separator: ".")
                indexStr = last
            } else {
                selector = cleanRule
            }
        }
        
        do {
            let elements = try container.select(selector).array()
            if let idx = indexStr {
                return applyIndex(elements, indexStr: idx)
            }
            return elements
        } catch {
            return []
        }
    }
    
    private func isPureIndex(_ s: String) -> Bool {
        if s.isEmpty { return false }
        if s.hasPrefix("-") { return Int(s.dropFirst()) != nil }
        return Int(s) != nil
    }
    
    private func applyIndex(_ elements: [Element], indexStr: String) -> [Element] {
        guard !elements.isEmpty else { return [] }
        let len = elements.count
        if let idx = Int(indexStr) {
            let targetIdx = idx < 0 ? len + idx : idx
            if targetIdx >= 0 && targetIdx < len {
                return [elements[targetIdx]]
            }
        }
        return elements
    }

    private func handleActionOrExtract(_ current: Any, action: String) -> String {
        // 如果是 XMLNode (XPath 结果)
        #if os(macOS)
        if let node = current as? XMLNode {
            if action == "text" || action == "ownText" { return node.stringValue ?? "" }
            if action == "html" { return node.xmlString }
            if let el = node as? XMLElement {
                return el.attribute(forName: action)?.stringValue ?? ""
            }
            return node.stringValue ?? ""
        }
        #endif

        let target: Any
        if let array = current as? [Any], let first = array.first {
            target = first
        } else {
            target = current
        }

        guard let el = target as? Element else {
            return (target as? String) ?? ""
        }
        
        switch action {
        case "text": return (try? el.text()) ?? ""
        case "ownText": return el.ownText()
        case "textNodes":
            return el.textNodes().map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case "html": return (try? el.outerHtml()) ?? ""
        case "href", "src":
            let attr = (try? el.attr(action)) ?? ""
            return normalizeUrl(attr)
        case "abs:href", "abs:src":
            return (try? el.attr(action)) ?? ""
        default:
            let attr = (try? el.attr(action)) ?? ""
            if !attr.isEmpty {
                if action == "href" || action == "src" { return normalizeUrl(attr) }
                return attr
            }
            if let found = try? el.select(action).first() {
                return (try? found.text()) ?? ""
            }
            return ""
        }
    }

    private func elementToText(_ element: Any) -> String {
        #if os(macOS)
        if let node = element as? XMLNode { return node.stringValue ?? "" }
        #endif
        if let el = element as? Element { return (try? el.text()) ?? "" }
        return (element as? String) ?? ""
    }

    private func normalizeUrl(_ url: String) -> String {
        if url.isEmpty || url.lowercased().hasPrefix("http") { return url }
        guard let base = URL(string: baseUrl) else { return url }
        return URL(string: url, relativeTo: base)?.absoluteString ?? url
    }

    // MARK: - JS Execution
    
    private func evalJSList(_ jsStr: String, result: String) -> [Any] {
        let context = ["result": result, "baseUrl": self.baseUrl]
        let output = jsRuntime.extractAndEval(text: jsStr, with: context)
        return output as? [Any] ?? (output != nil ? ["\(output!)"] : [])
    }
    
    private func evalJSText(_ jsStr: String, element: Any) -> String {
        let resultValue = (try? (element as? Element)?.outerHtml()) ?? (element as? String) ?? ""
        let context: [String: Any] = ["result": resultValue, "baseUrl": self.baseUrl]
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
                bookUrl: engine.text(element: element, ruleStr: source.ruleSearch?.bookUrl ?? ""),
                origin: source.bookSourceUrl,
                originName: source.bookSourceName,
                name: name,
                author: engine.text(element: element, ruleStr: source.ruleSearch?.author ?? ""),
                kind: engine.text(element: element, ruleStr: source.ruleSearch?.kind ?? ""),
                coverUrl: engine.text(element: element, ruleStr: source.ruleSearch?.coverUrl ?? ""),
                intro: engine.text(element: element, ruleStr: source.ruleSearch?.intro ?? ""),
                latestChapterTitle: engine.text(element: element, ruleStr: source.ruleSearch?.lastChapter ?? "")
            ))
        }
        return books
    }
    
    static func getContent(source: BookSource, chapterUrl: String, nextChapterUrl: String? = nil) async throws -> String {
        print("DEBUG RULE: Fetching content from \(chapterUrl)")
        
        var currentUrl = chapterUrl
        var fullContent = ""
        var pageCount = 0
        let maxPages = 30 // Safety limit to prevent infinite loops
        var visitedUrls = Set<String>()
        visitedUrls.insert(chapterUrl)
        
        while pageCount < maxPages {
            let html = try await UrlAnalyzer.shared.fetchHtml(url: currentUrl, source: source)
            
            let engine = RuleEngine(source: source)
            engine.baseUrl = currentUrl
            
            // 1. 获取正文内容
            var contentRule = source.ruleContent?.content ?? ""
            
            if !contentRule.isEmpty && !contentRule.contains("@") && !contentRule.contains("js:") {
                contentRule += "@html"
            }
            
            let pageContent = engine.text(element: html, ruleStr: contentRule)
            
            if !pageContent.isEmpty {
                if !fullContent.isEmpty {
                    fullContent += "\n"
                }
                fullContent += pageContent
            }
            
            pageCount += 1
            
            // 2. 检查是否有下一页
            guard let nextUrlRule = source.ruleContent?.nextContentUrl, !nextUrlRule.isEmpty else {
                print("DEBUG RULE: No nextContentUrl rule defined.")
                break
            }
            
            print("DEBUG RULE: Next page rule: \(nextUrlRule)")
            
            var nextUrl = engine.text(element: html, ruleStr: nextUrlRule)
            
            // Normalize URL
            if !nextUrl.isEmpty && !nextUrl.lowercased().hasPrefix("http") {
                if let base = URL(string: currentUrl) {
                    nextUrl = URL(string: nextUrl, relativeTo: base)?.absoluteString ?? nextUrl
                }
            }
            
            print("DEBUG RULE: Extracted next page url: '\(nextUrl)'")
            
            // Validation
            if nextUrl.isEmpty { 
                print("DEBUG RULE: Next page url is empty.")
                break 
            }
            
            if let nextChapterUrl = nextChapterUrl, nextUrl == nextChapterUrl {
                print("DEBUG RULE: Next page matches next chapter URL. Stopping.")
                break
            }
            
            if visitedUrls.contains(nextUrl) || nextUrl == currentUrl {
                print("DEBUG RULE: Next page loop detected. Stopping.")
                break
            }
            
            print("DEBUG RULE: Found next page: \(nextUrl)")
            currentUrl = nextUrl
            visitedUrls.insert(nextUrl)
            
            try await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        }
        
        if fullContent.isEmpty && source.ruleContent?.content == nil {
             print("DEBUG RULE: Content empty and no rule.")
        }
        
        return fullContent
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