import Foundation
import SwiftSoup

class ContentProcessor {
    static let shared = ContentProcessor()
    
    func process(content: String, source: BookSource) -> String {
        var processed = content
        
        // 1. Handle replaceRegex from source
        if let replaceRegex = source.ruleContent?.replaceRegex, !replaceRegex.isEmpty {
            let rules = replaceRegex.components(separatedBy: "\n")
            for rule in rules {
                processed = applyReplacement(content: processed, rule: rule)
            }
        }
        
        // 2. Common HTML/Text cleanup
        // Normalize line breaks
        processed = processed.replacingOccurrences(of: "<br>", with: "\n")
        processed = processed.replacingOccurrences(of: "<br/>", with: "\n")
        processed = processed.replacingOccurrences(of: "<br />", with: "\n")
        processed = processed.replacingOccurrences(of: "<p>", with: "\n")
        processed = processed.replacingOccurrences(of: "</p>", with: "")
        
        // Strip remaining HTML tags using SwiftSoup
        if let doc = try? SwiftSoup.parse(processed) {
            if let text = try? doc.text() {
                processed = text
            }
        }
        
        // Handle common entities if not already handled (SwiftSoup handles most, but just in case)
        processed = processed.replacingOccurrences(of: "&nbsp;", with: " ")
        
        return processed
    }
    
    private func applyReplacement(content: String, rule: String) -> String {
        let cleanRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanRule.isEmpty { return content }
        
        let parts = cleanRule.components(separatedBy: "##")
        guard !parts.isEmpty else { return content }
        
        let pattern = parts[0]
        let template = parts.count > 1 ? parts[1] : ""
        
        // Legado replacement might use $1, $2 for groups, which works with NSRegularExpression
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
            let range = NSRange(content.startIndex..., in: content)
            return regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: template)
        } catch {
            print("ContentProcessor Regex Error: \(error) for pattern: \(pattern)")
            return content
        }
    }
}
