import Foundation
import JavaScriptCore
import CryptoKit

class JSRuntime {
    
    private let context: JSContext
    
    init() {
        self.context = JSContext() ?? JSContext(virtualMachine: JSVirtualMachine())
        setupContext()
    }
    
    // MARK: - Setup
    
    private func setupContext() {
        // Exception Handling
        context.exceptionHandler = { context, exception in
            if let ex = exception {
                print("JS Error: \(ex.toString() ?? "Unknown error")")
            }
        }
        
        // Inject 'java' object
        let javaShim = JavaShim()
        context.setObject(javaShim, forKeyedSubscript: "java" as NSString)
    }
    
    // MARK: - Execution
    
    /// Evaluates JavaScript code with dynamic bindings.
    /// - Parameters:
    ///   - code: The JavaScript code to execute.
    ///   - bindings: A dictionary of variables to inject into the JS context (e.g., ["baseUrl": "...", "result": ...]).
    /// - Returns: The result of the execution.
    func eval(_ code: String, with bindings: [String: Any] = [:]) -> Any? {
        // Inject bindings
        for (key, value) in bindings {
            context.setObject(value, forKeyedSubscript: key as NSString)
        }
        
        // Execute
        let result = context.evaluateScript(code)
        
        // Return native object
        return result?.toObject()
    }
    
    /// Helper to extract and execute code wrapped in {{js: ... }}, <js> ... </js>, or @js:
    /// - Parameters:
    ///   - text: The text containing JS patterns.
    ///   - bindings: Variables to inject.
    /// - Returns: The result of the JS execution if found, otherwise nil (or original text if logic dictates).
    /// Note: This function currently assumes the whole text might be a JS block or contains one.
    /// In Legado, {{js:}} is often used for replacement. 
    /// If the intention is to process a rule string that *is* JS, this handles parsing it.
    func extractAndEval(text: String, with bindings: [String: Any]) -> Any? {
        var script = text
        var isJs = false
        
        // Check for {{js: ... }}
        if let range = text.range(of: "\\{\\{js:(.*?)\\}\\}", options: .regularExpression) {
            let match = text[range]
            // Extract inner group. The regex above matches the whole block.
            // Let's use NSRegularExpression for precise group extraction if needed,
            // or just simple string manipulation since the pattern is known.
            // Simplified: remove {{js: and }}
            // Note: This logic assumes the *entire* rule is the JS block or we are extracting just one.
            // If the rule is "prefix {{js: code }} suffix", this simple check might need to be a replacement loop.
            // For this task, we assume we are evaluating a JS rule found in `RuleEngine`.
            
            // Re-implement with regex to capture group 1
            if let regex = try? NSRegularExpression(pattern: "\\{\\{js:(.*?)\\}\\}", options: [.dotMatchesLineSeparators]) {
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let range = Range(match.range(at: 1), in: text) {
                        script = String(text[range])
                        isJs = true
                    }
                }
            }
        } else if text.hasPrefix("@js:") {
            script = String(text.dropFirst(4))
            isJs = true
        } else if text.hasPrefix("<js>") && text.hasSuffix("</js>") {
            script = String(text.dropFirst(4).dropLast(5))
            isJs = true
        }
        
        // If no wrapper found, but we were called, maybe treat as raw JS?
        // Or return nil to indicate no JS processing needed.
        if !isJs {
            // Check if user explicitly wants to eval raw JS or only wrapped.
            // The prompt says: "Identify rules... extract... execute".
            // If it's not wrapped, we might assume it's not JS for this specific helper.
            return nil 
        }
        
        return eval(script, with: bindings)
    }
}

// MARK: - Java Shim

@objc protocol JavaShimExport: JSExport {
    func log(_ msg: Any)
    func md5(_ str: String) -> String
    func base64Encode(_ str: String) -> String
    func base64Decode(_ str: String) -> String
    // Add other Legado common functions here as needed
}

class JavaShim: NSObject, JavaShimExport {
    
    func log(_ msg: Any) {
        print("[JS Log]: \(msg)")
    }
    
    func md5(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else { return "" }
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    func base64Encode(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else { return "" }
        return data.base64EncodedString()
    }
    
    func base64Decode(_ str: String) -> String {
        guard let data = Data(base64Encoded: str) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
