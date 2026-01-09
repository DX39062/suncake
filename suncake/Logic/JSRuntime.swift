import Foundation
import JavaScriptCore
import CryptoKit
import CommonCrypto

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
    func md5Encode(_ str: String) -> String
    func base64Encode(_ str: String) -> String
    func base64Decode(_ str: String) -> String
    func aesBase64DecodeToString(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String
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
    
    func md5Encode(_ str: String) -> String {
        return md5(str)
    }
    
    func base64Encode(_ str: String) -> String {
        guard let data = str.data(using: .utf8) else { return "" }
        return data.base64EncodedString()
    }
    
    func base64Decode(_ str: String) -> String {
        guard let data = Data(base64Encoded: str) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    func aesBase64DecodeToString(_ data: String, _ key: String, _ transformation: String, _ iv: String) -> String {
        // Basic AES CBC/PKCS7 decryption matching Legado's likely usage
        guard let dataData = Data(base64Encoded: data),
              let keyData = key.data(using: .utf8),
              let ivData = iv.data(using: .utf8) else {
            print("[JS] AES Decode Args Error")
            return ""
        }
        
        // Ensure Key is correct length (16/24/32 bytes). Legado usually ensures this via MD5 substring.
        // IV should be 16 bytes for AES.
        
        let operation = CCOperation(kCCDecrypt)
        let algorithm = CCAlgorithm(kCCAlgorithmAES)
        // options: kCCOptionPKCS7Padding (PKCS5 is subset/alias here)
        // If 'transformation' contains "NoPadding", we'd remove this.
        // Assuming PKCS5Padding/PKCS7Padding as default from Java logic.
        let options = CCOptions(kCCOptionPKCS7Padding)
        
        var numBytesOut: size_t = 0
        let dataBytes = [UInt8](dataData)
        let keyBytes = [UInt8](keyData)
        let ivBytes = [UInt8](ivData)
        
        // Output buffer
        let outLength = dataBytes.count + kCCBlockSizeAES128
        var outBytes = [UInt8](repeating: 0, count: outLength)
        
        let cryptStatus = CCCrypt(
            operation,
            algorithm,
            options,
            keyBytes, keyBytes.count,
            ivBytes,
            dataBytes, dataBytes.count,
            &outBytes, outLength,
            &numBytesOut
        )
        
        if cryptStatus == kCCSuccess {
            let resultData = Data(bytes: outBytes, count: numBytesOut)
            return String(data: resultData, encoding: .utf8) ?? ""
        } else {
            print("[JS] AES Decrypt Failed: \(cryptStatus)")
            return ""
        }
    }
}
