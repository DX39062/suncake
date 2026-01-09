import Foundation
import CoreFoundation

struct UrlAnalyzer {
    static let shared = UrlAnalyzer()
    private init() {}

    func fetchHtml(url urlStr: String, source: BookSource? = nil) async throws -> String {
        let request: URLRequest
        if let source = source {
            request = try await UrlAnalyzer.getRequest(urlStr: urlStr, source: source)
        } else {
            guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
            request = URLRequest(url: url)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        
        // 尝试解析编码
        var encoding = String.Encoding.utf8
        if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String {
            if contentType.lowercased().contains("gbk") || contentType.lowercased().contains("gb2312") {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringConvertIANACharSetNameToEncoding("GBK" as CFString)))
            }
        }
        
        if let html = String(data: data, encoding: encoding) {
            return html
        } else if let html = String(data: data, encoding: .utf8) {
            return html
        }
        
        throw URLError(.cannotDecodeContentData)
    }

    static func getRequest(urlStr: String, keyword: String? = nil, source: BookSource) async throws -> URLRequest {
        print("DEBUG ANALYZER: 收到规则 -> \(urlStr)")
        var ruleUrl = urlStr
        
        if let keyword = keyword {
            let encodedKey = UrlAnalyzer.encode(keyword: keyword, encoding: String.Encoding.utf8)
            ruleUrl = ruleUrl.replacingOccurrences(of: "{{key}}", with: encodedKey)
                             .replacingOccurrences(of: "{key}", with: encodedKey)
        }
        
        ruleUrl = ruleUrl.replacingOccurrences(of: "{{baseUrl}}", with: source.bookSourceUrl)
        ruleUrl = ruleUrl.replacingOccurrences(of: "{{page}}", with: "1")

        let (baseUrlRaw, options) = UrlAnalyzer.splitUrlAndOptions(ruleUrl)
        let cleanUrlStr = baseUrlRaw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard let url = URL(string: cleanUrlStr) else {
            print("DEBUG ANALYZER: URL 构建非法 -> [\(cleanUrlStr)]")
            throw URLError(.badURL)
        }
        
        print("DEBUG ANALYZER: 最终请求 URL -> \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        
        if let options = options {
            if let method = options.method?.uppercased() { request.httpMethod = method }
            if let headers = options.headers {
                for (key, value) in headers { request.addValue(value.description, forHTTPHeaderField: key) }
            }
            if request.httpMethod == "POST", let body = options.body {
                request.httpBody = body.data(using: String.Encoding.utf8)
            }
        }
        
        if request.value(forHTTPHeaderField: "User-Agent") == nil {
            request.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        }
        return request
    }
    
    private static func encode(keyword: String, encoding: String.Encoding) -> String {
        return keyword.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? keyword
    }

    static func splitUrlAndOptions(_ urlStr: String) -> (String, UrlOption?) {
        let nsString = urlStr as NSString
        let range = nsString.range(of: ",\\s*\\{", options: .regularExpression)
        if range.location != NSNotFound {
            let urlPart = nsString.substring(to: range.location)
            let jsonPart = nsString.substring(from: range.location + 1)
            if let data = jsonPart.data(using: String.Encoding.utf8) {
                do {
                    let options = try JSONDecoder().decode(UrlOption.self, from: data)
                    return (urlPart, options)
                } catch { print("DEBUG ANALYZER: JSON 解析失败: \(error)") }
            }
            return (urlPart, nil)
        }
        return (urlStr, nil)
    }
}

// 确保以下模型在文件中定义，解决“Cannot find type in scope”问题
struct UrlOption: Codable {
    var method: String?
    var charset: String?
    var headers: [String: StringOrInt]?
    var body: String?
    
    enum CodingKeys: String, CodingKey { case method, charset, headers, body }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        charset = try container.decodeIfPresent(String.self, forKey: .charset)
        headers = try container.decodeIfPresent([String: StringOrInt].self, forKey: .headers)
        if let bodyString = try? container.decode(String.self, forKey: .body) { body = bodyString }
        else if let bodyDict = try? container.decode([String: AnyCodable].self, forKey: .body) {
            let data = try JSONEncoder().encode(bodyDict)
            body = String(data: data, encoding: .utf8)
        }
    }
}

enum StringOrInt: Codable, CustomStringConvertible {
    case string(String), int(Int)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) { self = .int(x) }
        else { self = .string(try container.decode(String.self)) }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self { case .string(let x): try container.encode(x); case .int(let x): try container.encode(x) }
    }
    var description: String { switch self { case .string(let s): return s; case .int(let i): return String(i) } }
}

struct AnyCodable: Codable {
    var value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) { value = x }
        else if let x = try? container.decode(String.self) { value = x }
        else { value = "" }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let x = value as? Int { try container.encode(x) }
        else { try container.encode("\(value)") }
    }
}