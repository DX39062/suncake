import Foundation
import SwiftSoup

class ContentProcessor {
    static let shared = ContentProcessor()
    
    func process(content: String, source: BookSource) -> String {
        var processed = content
        
        // 1. Handle replaceRegex from source (Pre-processing)
        if let replaceRegex = source.ruleContent?.replaceRegex, !replaceRegex.isEmpty {
            let rules = replaceRegex.components(separatedBy: "\n")
            for rule in rules {
                processed = applyReplacement(content: processed, rule: rule)
            }
        }
        
        // 2. HTML Tag to Newline Conversion
        // Use a unique token that survives HTML parsing and whitespace normalization
        let newlineToken = "[[_NEWLINE_]]"
        
        // Replace <br> variants
        processed = processed.replacingOccurrences(of: "(?i)<br\\s*/?>", with: newlineToken, options: .regularExpression)
        // Replace </p> (end of paragraph implies newline)
        processed = processed.replacingOccurrences(of: "(?i)</p>", with: newlineToken, options: .regularExpression)
        // Replace </div> (often used for lines)
        processed = processed.replacingOccurrences(of: "(?i)</div>", with: newlineToken, options: .regularExpression)
        
        // 3. Strip remaining HTML tags using SwiftSoup
        if let doc = try? SwiftSoup.parse(processed) {
            if let text = try? doc.text() {
                processed = text
            }
        }
        
        // 4. Restore newlines
        processed = processed.replacingOccurrences(of: newlineToken, with: "\n")
        
        // 5. Cleanup
        // Handle common entities if not already handled (SwiftSoup handles most)
        // Convert Non-Breaking Space to normal space
        processed = processed.replacingOccurrences(of: "\u{00A0}", with: " ")
        
        // 6. Reformat for Reading (Typesetting)
        let lines = processed.components(separatedBy: .newlines)
        let formattedLines = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : "\u{3000}\u{3000}" + trimmed
        }
        
        return formattedLines.joined(separator: "\n")
    }
    
    private func applyReplacement(content: String, rule: String) -> String {
        let cleanRule = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanRule.isEmpty { return content }
        
        let parts = cleanRule.components(separatedBy: "##")
        guard !parts.isEmpty else { return content }
        
        let pattern = parts[0]
        if pattern.isEmpty { return content } // Skip empty patterns
        
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
