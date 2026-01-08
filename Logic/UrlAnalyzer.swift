import Foundation
import CoreFoundation

struct UrlAnalyzer {
    
    // MARK: - Constants
    private static let paramPattern = try! NSRegularExpression(pattern: "\\s*,\\s*(?=\\{)")
    private static let jsPattern = try! NSRegularExpression(pattern: "\\{\\{@js\\:(.*?)\\}\\}\\}|@js\\:(.*?)$|<js>(.*?)</js>", options: [.caseInsensitive, .dotMatchesLineSeparators])
    
    // MARK: - Core Function
    
    /// Parses a Legado URL string and returns a configured URLRequest.
    /// - Parameters:
    ///   - urlStr: The raw URL string from the rule (e.g., "http://example.com,{'method':'POST'}")
    ///   - keyword: The search keyword (optional). If provided, {{key}} will be replaced.
    ///   - source: The book source context
    /// - Returns: A configured URLRequest
    static func getRequest(urlStr: String, keyword: String? = nil, source: BookSource) async throws -> URLRequest {
        print("DEBUG: 准备解析 URL 规则: \(urlStr)")
        
        var ruleUrl = urlStr
        
        // 1. JS Pre-processing (Placeholder)
        ruleUrl = await processJs(url: ruleUrl)
        
        // 2. Variable Replacement (Simple)
        ruleUrl = replaceVariables(url: ruleUrl, source: source)
        
        // 3. Split URL and Options
        let (baseUrlRaw, options) = splitUrlAndOptions(ruleUrl)
        
        // 4. Keyword Replacement
        var finalBaseUrl = baseUrlRaw
        if let keyword = keyword {
            let charset = options?.charset ?? "utf-8"
            let requestCharset = getEncoding(charset: charset)
            let encodedKey = encode(keyword: keyword, encoding: requestCharset)
            
            finalBaseUrl = finalBaseUrl.replacingOccurrences(of: "{{key}}", with: encodedKey)
                                       .replacingOccurrences(of: "{key}", with: encodedKey)
        }
        
        // 5. Construct URL
        guard let url = URL(string: finalBaseUrl) else {
            print("DEBUG: URL 构建失败，请检查规则或编码")
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        
        // 6. Apply Options
        if let options = options {
            // Method
            if let method = options.method?.uppercased() {
                request.httpMethod = method
            }
            
            // Headers
            if let headers = options.headers {
                for (key, value) in headers {
                    request.addValue(String(describing: value), forHTTPHeaderField: key)
                }
            }
            
            // Body (for POST)
            if request.httpMethod == "POST", let body = options.body {
                // Determine content type
                if let contentType = request.value(forHTTPHeaderField: "Content-Type") {
                     // If specific encoding is needed (like GBK), it would happen here.
                     // For now, we assume UTF-8 for JSON/String bodies.
                    request.httpBody = body.data(using: .utf8)
                } else {
                    // Default behavior: if body looks like JSON, set JSON header?
                    // Legado checks if body is JSON/XML.
                    // For simplicity, we just set the body.
                    request.httpBody = body.data(using: .utf8)
                }
                
                // If the body contains {{key}}, replace it too?
                // Legado does replacement in body too.
                // Assuming `body` in `options` has NOT been replaced yet if it came from JSON parsing of the rule string?
                // Actually `splitUrlAndOptions` parses the JSON part.
                // If the JSON string contained {{key}}, it is now in `options.body`.
                // We should probably replace it there too if needed.
                // But for now, focusing on URL as per prompt.
            }
        }
        
        // User Agent fallback
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        }
        
        return request
    }
    
    // MARK: - Helper Methods
    
    private static func getEncoding(charset: String) -> String.Encoding {
        if charset.lowercased().contains("gb") { // gbk, gb2312, gb18030
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        return .utf8
    }
    
    private static func encode(keyword: String, encoding: String.Encoding) -> String {
        if encoding == .utf8 {
             return keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        } else {
             guard let data = keyword.data(using: encoding) else { return keyword }
             
             // URLEncoder logic: alphanumeric and -_.* are allowed. Others are %XX.
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
    
    private static func processJs(url: String) async -> String {
        // TODO: Integrate JSRuntime here.
        // Identify {{js:...}}, @js:..., <js>...</js>
        // For now, we simply return the url as is or strip JS if needed to prevent crash
        // but user asked to just "annotate", so we keep it.
        return url
    }
    
    private static func replaceVariables(url: String, source: BookSource) -> String {
        var result = url
        
        // Simple replacements
        // In a real app, these values would come from the current context (book, chapter, page index)
        // Since we only have 'source' here, we can't replace dynamic values like {{page}} accurately without more context.
        // However, we will implement the logic structure.
        
        // Example: {{baseUrl}} -> source.bookSourceUrl
        result = result.replacingOccurrences(of: "{{baseUrl}}", with: source.bookSourceUrl)
        
        // TODO: Handle {{page}}, {{key}}, {{bookName}} when those contexts are available.
        
        return result
    }
    
    static func splitUrlAndOptions(_ urlStr: String) -> (String, UrlOption?) {
        let nsString = urlStr as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        // Find the first comma followed by a {
        if let match = paramPattern.firstMatch(in: urlStr, options: [], range: range) {
            let splitIndex = match.range.location
            let urlPart = nsString.substring(to: splitIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let jsonPart = nsString.substring(from: match.range.location + match.range.length - 1) // -1 to include the '{' (regex lookahead didn't consume it? actually regex is (?=\{) so it didn't consume {)
            // Wait, regex is \s*,\s*(?=\{)
            // It matches the comma and surrounding spaces. It does NOT consume the {.
            // So `match.range` covers the comma. The `{` starts at `match.range.upperBound`.
            
            let realJsonStart = match.range.upperBound
            let realJsonPart = nsString.substring(from: realJsonStart)
            // But we need to verify the regex logic.
            // paramPattern matches ", " in "url, {json}"
            // So we take everything before match as URL, and everything from match.upperBound as JSON.
            
            if let data = realJsonPart.data(using: .utf8) {
                do {
                    let options = try JSONDecoder().decode(UrlOption.self, from: data)
                    return (urlPart, options)
                } catch {
                    print("UrlAnalyzer: Failed to decode options: \(error)")
                }
            }
            return (urlPart, nil)
        }
        
        return (urlStr, nil)
    }
}

// MARK: - Supporting Models

struct UrlOption: Codable {
    var method: String?
    var charset: String?
    var headers: [String: StringOrInt]?
    var body: String? // Simplification: assume body is string or we convert it
    
    enum CodingKeys: String, CodingKey {
        case method
        case charset
        case headers
        case body
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        charset = try container.decodeIfPresent(String.self, forKey: .charset)
        headers = try container.decodeIfPresent([String: StringOrInt].self, forKey: .headers)
        
        // Body can be String or JSON Object/Array
        if let bodyString = try? container.decode(String.self, forKey: .body) {
            body = bodyString
        } else if let bodyDict = try? container.decode([String: AnyCodable].self, forKey: .body) {
            // Convert back to JSON string
            let data = try JSONEncoder().encode(bodyDict)
            body = String(data: data, encoding: .utf8)
        } else if let bodyArray = try? container.decode([AnyCodable].self, forKey: .body) {
             let data = try JSONEncoder().encode(bodyArray)
             body = String(data: data, encoding: .utf8)
        }
    }
}

// Helper for loose typing in JSON
enum StringOrInt: Codable, CustomStringConvertible {
    case string(String)
    case int(Int)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        throw DecodingError.typeMismatch(StringOrInt.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for StringOrInt"))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let x):
            try container.encode(x)
        case .int(let x):
            try container.encode(x)
        }
    }
    
    var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        }
    }
}

// Helper for AnyCodable structure since 'body' can be anything
struct AnyCodable: Codable {
    var value: Any
    
    struct CodingKeys: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
    }
    
    init(value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) { value = x; return }
        if let x = try? container.decode(String.self) { value = x; return }
        if let x = try? container.decode(Bool.self) { value = x; return }
        if let x = try? container.decode(Double.self) { value = x; return }
        if let x = try? container.decode([String: AnyCodable].self) { value = x.mapValues { $0.value }; return }
        if let x = try? container.decode([AnyCodable].self) { value = x.map { $0.value }; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let x = value as? Int { try container.encode(x) }
        else if let x = value as? String { try container.encode(x) }
        else if let x = value as? Bool { try container.encode(x) }
        else if let x = value as? Double { try container.encode(x) }
        else if let x = value as? [String: Any] { 
            let mapped = x.mapValues { AnyCodable(value: $0) }
            try container.encode(mapped) 
        }
        else if let x = value as? [Any] {
            let mapped = x.map { AnyCodable(value: $0) }
            try container.encode(mapped)
        }
        else { throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Invalid JSON value")) }
    }
}
