import Foundation
import SwiftSoup
import CoreFoundation

class RuleEngine {
    let source: BookSource
    
    init(source: BookSource) {
        self.source = source
    }
    
    // MARK: - Core Methods
    
    /// Parses content (HTML/String) and extracts a list of elements based on the rule.
    /// - Parameters:
    ///   - content: The raw content string (HTML, JSON, or plain text).
    ///   - rule: The extraction rule (CSS, XPath, JSON, or Regex).
    /// - Returns: A list of result objects (SwiftSoup.Element for HTML, String for Regex/Text).
    func elements(content: String, ruleStr: String) -> [Any] {
        // Debug Log
        print("--- RuleEngine Debug ---")
        print("Rule: \(ruleStr)")
        print("Content (first 500): \(content.prefix(500))")
        
        guard !ruleStr.isEmpty else { return [] }
        
        let (type, cleanRule) = detectRuleType(ruleStr)
        var results: [Any] = []
        
        switch type {
        case .css, .jsoup:
            results = extractByCss(content: content, rule: cleanRule, isCssOnly: type == .css)
        case .regex:
            results = extractByRegex(content: content, rule: cleanRule)
        case .json:
            print("TODO: JSONPath not supported yet: \(cleanRule)")
            results = []
        case .xpath:
            print("TODO: XPath not supported yet: \(cleanRule)")
            results = []
        }
        
        print("Elements found: \(results.count)")
        print("------------------------")
        
        return results
    }
    
    /// Extracts a string value (text, attribute, url) from a single element.
    /// - Parameters:
    ///   - element: The element to extract from (SwiftSoup.Element or String).
    ///   - rule: The extraction rule (e.g., "text", "href", "src", or a sub-selector).
    /// - Returns: The extracted string.
    func text(element: Any, ruleStr: String) -> String {
        // Pre-processing: Check for JS
        if ruleStr.contains("@js:") || ruleStr.hasPrefix("<js>") {
            print("Log: JS execution required for rule: \(ruleStr). (JSRuntime pending)")
            // TODO: Execute JS. For now, return empty or strip JS? 
            // We'll proceed with the non-js part if possible or just return empty if it's purely JS.
            if ruleStr.starts(with: "@js:") { return "" }
        }
        
        // Handle multi-part rules (e.g. "div@text")
        let parts = ruleStr.components(separatedBy: "@")
        // If the rule is complex (has @), we might need to drill down first
        // But for `text` function, usually the last part is the action.
        // Legado logic: if rule has multiple parts, the first Church N-1 are selectors, last is action.
        
        var currentElement = element
        var action = ruleStr
        
        if parts.count > 1 {
            // Apply selectors for all but last part
            // This is a simplification. Legado does full analysis.
            // Here we assume simple "selector@action" or "action"
            // If it's "selector@selector@action", we need to loop.
            
            // TODO: Implement full recursive drill-down for `text` context.
            // For now, let's assume the element is already the target or the rule is simple.
            // We'll take the last part as the 'action' and previous as selectors if valid.
            
            // If the element is a SwiftSoup Element, we can drill down.
            if let soupEl = currentElement as? Element {
                // Try to select down
                // For simplicity in this task, we'll implement basic "select and take first" logic
                // matching Legado's behavior of "getString" which joins or takes first.
                
                // Let's rely on the fact that `elements` extraction usually gets us to the list items,
                // and `text` rules usually are just "text", "href", or "a@text".
                
                // If parts > 1, we treat N-1 as selectors
                let subSelector = parts.dropLast().joined(separator: "@")
                action = parts.last ?? ""
                
                if let subEl = try? soupEl.select(subSelector).first() {
                    currentElement = subEl
                } else if !subSelector.isEmpty {
                     // Selector found nothing
                     return ""
                }
            } else {
                 // String element, can't drill down with CSS
                 action = parts.last ?? ""
            }
        }
        
        // Execute Action
        if let soupEl = currentElement as? Element {
            return extractFromElement(soupEl, action: action)
        } else if let strEl = currentElement as? String {
            // If it's a string, maybe the rule is a regex to extract substring?
            // Or just return the string if rule is "text" or empty.
            if action == "text" || action.isEmpty {
                return strEl
            }
            // If rule is regex, apply it
            // Simple regex match for now
            if let match = extractByRegex(content: strEl, rule: action).first as? String {
                return match
            }
            return strEl
        }
        
        return ""
    }
    
    /// Extracts a URL from a single element and resolves it against the book source URL.
    /// - Parameters:
    ///   - element: The element to extract from.
    ///   - ruleStr: The extraction rule.
    /// - Returns: A fully qualified URL string.
    func url(element: Any, ruleStr: String) -> String {
        let extracted = text(element: element, ruleStr: ruleStr)
        if extracted.isEmpty { return "" }
        
        if extracted.lowercased().hasPrefix("http") {
            return extracted
        }
        
        // Resolve relative URL
        if let baseUrl = URL(string: source.bookSourceUrl),
           let fullUrl = URL(string: extracted, relativeTo: baseUrl) {
            return fullUrl.absoluteString
        }
        
        // Fallback simple join
        return source.bookSourceUrl + extracted
    }
    
    // MARK: - Helpers
    
    private enum RuleType {
        case css    // Explicit @css: or starting with .
        case jsoup  // Legado default (split by @, supports tag., class., etc)
        case xpath  // @xpath: or //
        case json   // @json: or $
        case regex  // default fallback
    }
    
    private func detectRuleType(_ rule: String) -> (RuleType, String) {
        var r = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if r.hasPrefix("@css:") {
            return (.css, String(r.dropFirst(5)))
        }
        if r.hasPrefix("@xpath:") {
            return (.xpath, String(r.dropFirst(7)))
        }
        if r.hasPrefix("@json:") {
            return (.json, String(r.dropFirst(6)))
        }
        if r.hasPrefix("@js:") {
             // Treat JS as a special case, but usually JS rules are handled inside elements/text.
             // If the whole rule is JS, we might need a .js type?
             // For elements extraction, JS usually returns a list. 
             // Legado often embeds JS in {{ }}.
             // For now fallback to regex/text handling or handle within specific methods.
             // But here we are classifying the SELECTOR type.
        }
        
        // Heuristics per prompt & Legado
        if r.hasPrefix(".") { return (.css, r) } // Prompt: "Start with ." -> CSS
        if r.hasPrefix("//") { return (.xpath, r) }
        if r.hasPrefix("$") { return (.json, r) }
        
        // Legado "Default" Jsoup logic vs Regex
        // If it looks like "div@p" or "class.a" or just "div", it's Jsoup.
        // If it looks like "Chapter \d+", it's Regex.
        // We will default to Jsoup if it contains standard separators or tags, else Regex?
        // Actually, if we use SwiftSoup for everything non-regex-looking, it's safer for HTML.
        // But "Chapter \d+" would fail in SwiftSoup.
        // Let's check for standard Regex characters that are invalid in CSS identifiers?
        // \, ?, *, +, +, ^, $ (at end), [], ()
        // CSS uses ., #, :, >, ~, +, [, ], (, ) (for nth-child).
        // It's ambiguous.
        // Strategy: strict adherence to prompt for "CSS" (. or @css).
        // Everything else -> "Regex/Text" per prompt ("其他视为正则表达式或普通文本").
        // BUT, I will add a "Jsoup" fallback for `tag.`, `class.`, `id.` or `children` prefixes
        // because those are Legado-specific Jsoup aliases that don't start with `.`.
        
        if r.hasPrefix("tag.") || r.hasPrefix("class.") || r.hasPrefix("id.") || r.hasPrefix("children") {
            return (.jsoup, r)
        }
        
        // If it contains "@", it's likely a Legado split rule (Jsoup).
        if r.contains("@") && !r.contains(":") { // : might be in regex or css pseudo-class
             // Heuristic: Legado rules use @ to separate levels.
             return (.jsoup, r)
        }
        
        return (.regex, r)
    }
    
    private func extractByCss(content: String, rule: String, isCssOnly: Bool) -> [Element] {
        do {
            let doc = try SwiftSoup.parse(content)
            
            if isCssOnly {
                // Pure CSS selector
                return try doc.select(rule).array()
            } else {
                // Legado Jsoup logic (split by @, handle custom tags)
                return try extractByLegadoJsoup(root: doc, rule: rule)
            }
        } catch {
            print("CSS Parse Error: \(error)")
            return []
        }
    }
    
    private func extractByLegadoJsoup(root: Element, rule: String) throws -> [Element] {
        let parts = rule.components(separatedBy: "@")
        var currentElements = [root]
        
        for part in parts {
            var nextElements = [Element]()
            
            for el in currentElements {
                // Handle Legado specific selectors: tag.x, class.x, id.x
                // Or standard CSS
                let selector = mapLegadoSelectorToCss(part)
                
                // Handle Indexing [1:3], !0, etc.
                // TODO: Implement full Legado indexing parser.
                // For now, we strip indexing and just select.
                // e.g. "div.content!0" -> selector "div.content", index 0 (exclude?)
                // Simplified: Just use the selector part.
                
                let (cleanSelector, indexRule) = splitSelectorAndIndex(selector)
                
                let results = try el.select(cleanSelector)
                
                // Apply Indexing if present
                if let indexRule = indexRule {
                    // Supported: :0, :last, etc?
                    // Legado: !0 (exclude 0), 0 (include 0), -1 (last), 0:2 (range)
                    // Simplified implementation:
                    nextElements.append(contentsOf: applyIndex(elements: results.array(), rule: indexRule))
                } else {
                    nextElements.append(contentsOf: results.array())
                }
            }
            currentElements = nextElements
            if currentElements.isEmpty { break }
        }
        
        return currentElements
    }
    
    private func mapLegadoSelectorToCss(_ part: String) -> String {
        // Legado allows "tag.div", "class.intro", "id.main"
        if part.hasPrefix("tag.") { return part.replacingOccurrences(of: "tag.", with: "") }
        if part.hasPrefix("class.") { return part.replacingOccurrences(of: "class.", with: ".") }
        if part.hasPrefix("id.") { return part.replacingOccurrences(of: "id.", with: "#") }
        if part == "children" { return "*" } // Approximation
        return part
    }
    
    private func splitSelectorAndIndex(_ selector: String) -> (String, String?) {
        // Legado indexing: tag.div!0:2  or tag.div[1,2]
        // Regex to find ! or : at the end?
        // Simplified: Check for ! or : that are not part of CSS (like :nth-child)
        // This is complex. For now, assume basic CSS.
        // If we see `!`, it's likely Legado exclusion.
        if let idx = selector.lastIndex(of: "!") {
             let sel = String(selector[..<idx])
             let rule = String(selector[selector.index(after: idx)...])
             return (sel, "!" + rule)
        }
        // Check for `:number` at the end (custom Legado index, not pseudo-class)
        // Risky collision with :nth-child. Legado uses `.` for most things.
        // We'll skip complex index parsing for this iteration.
        return (selector, nil)
    }
    
    private func applyIndex(elements: [Element], rule: String) -> [Element] {
        // Stub for index logic
        // rule might be "!0" -> exclude 0
        // rule might be "0" -> only 0
        // rule might be "-1" -> last
        
        if rule.hasPrefix("!") {
            if let idx = Int(rule.dropFirst()), idx >= 0, idx < elements.count {
                var res = elements
                res.remove(at: idx)
                return res
            }
        } else if let idx = Int(rule) {
            if idx >= 0 && idx < elements.count {
                return [elements[idx]]
            } else if idx < 0 && abs(idx) <= elements.count {
                return [elements[elements.count + idx]]
            }
        }
        return elements
    }
    
    private func extractByRegex(content: String, rule: String) -> [String] {
        do {
            let regex = try NSRegularExpression(pattern: rule, options: [])
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            let matches = regex.matches(in: content, options: [], range: range)
            
            return matches.map { match in
                if let r = Range(match.range, in: content) {
                    return String(content[r])
                }
                return ""
            }
        } catch {
            print("Regex Error: \(error)")
            return []
        }
    }
    
    private func extractFromElement(_ element: Element, action: String) -> String {
        do {
            switch action {
            case "text", "":
                return try element.text()
            case "html":
                return try element.outerHtml()
            case "ownText":
                return element.ownText()
            default:
                // Attribute
                return try element.attr(action)
            }
        } catch {
            return ""
        }
    }
}

class SearchModel {
    
    // MARK: - API
    
    /// Searches for books across multiple sources concurrently.
    /// Returns an async stream of results as they become available.
    func search(keyword: String, sources: [BookSource]) async -> AsyncStream<[Book]> {
        return AsyncStream { continuation in
            Task {
                await withTaskGroup(of: [Book].self) { group in
                    for source in sources {
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
        // Detect charset from options
        let (_, options) = UrlAnalyzer.splitUrlAndOptions(searchUrlRaw)
        let charset = options?.charset ?? "utf-8"
        
        // Encode keyword
        let encodedKey = encode(keyword: keyword, charset: charset)
        
        // Replace {{key}} with encoded keyword
        let urlStr = searchUrlRaw.replacingOccurrences(of: "{{key}}", with: encodedKey)
                                 .replacingOccurrences(of: "{key}", with: encodedKey)
        
        // TODO: Handle page replacement {{page}} -> 1 for search
        let finalUrlStr = urlStr.replacingOccurrences(of: "{{page}}", with: "1")
        
        do {
            let request = try await UrlAnalyzer.getRequest(urlStr: finalUrlStr, source: source)
            
            // 2. Fetch Data
            // Use URLSession with default configuration
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return [] }
            
            // Handle Encoding (Legado might define charset in rule, but for now try UTF-8 or ISO-8859-1 fallback)
            // Ideally UrlAnalyzer detects charset from headers/meta.
            // Simplified: UTF-8 or ISO-8859-1. TODO: use detected charset for decoding too?
            var content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            
            // 3. Parse Data
            if content.isEmpty { return [] }
            
            let ruleEngine = RuleEngine(source: source)
            
            // Book List Rule
            let listRule = searchRule.bookList ?? ""
            guard !listRule.isEmpty else { return [] }
            
            let elements = ruleEngine.elements(content: content, ruleStr: listRule)
            
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
    
    private func encode(keyword: String, charset: String) -> String {
        let encoding: String.Encoding
        if charset.lowercased() == "gbk" {
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        } else {
            encoding = .utf8
        }
        
        if encoding == .utf8 {
             return keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        } else {
             guard let data = keyword.data(using: encoding) else { return keyword }
             
             // URLEncoder logic: alphanumeric and -_.* are allowed. Others are %XX.
             // Space is + in form-urlencoded, but %20 in path/query usually. Legado uses URLEncoder.encode which produces + for space?
             // Swift .urlQueryAllowed includes ? / etc. 
             // We want strict encoding for query value.
             
             let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.*"))
             
             var result = ""
             for byte in data {
                 let scalar = UnicodeScalar(byte)
                 if byte < 128, allowed.contains(scalar) {
                     result.append(Character(scalar))
                 } else {
                     result.append(String(format: "%%%02X", byte))
                 }
             }
             return result
        }
    }
}