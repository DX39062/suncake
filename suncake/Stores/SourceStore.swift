import Foundation
import Combine
internal import SwiftUI

class SourceStore: ObservableObject {
    @Published var sources: [BookSource] = []
    
    private let fileName = "bookSources.json"
    
    // MARK: - Initialization
    
    init() {
        loadSources()
        if sources.isEmpty {
            loadDefaultSources()
        } else {
            // Auto-repair: If we have the default "示例书源" but it lacks searchUrl, regenerate it.
            // This handles the case where the user ran the app with the broken default generation code.
            if let defaultSource = sources.first(where: { $0.bookSourceName == "示例书源" }),
               (defaultSource.searchUrl == nil || defaultSource.searchUrl!.isEmpty) {
                print("DEBUG SOURCE: Detected broken default source. Regenerating...")
                loadDefaultSources() // This overwrites sources and saves
            }
        }
    }
    
    // MARK: - Core Methods
    
    /// Loads sources from the local file system.
    func loadSources() {
        guard let url = getDocumentsDirectory()?.appendingPathComponent(fileName) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            
            // Diagnostic: Print raw JSON of the first source
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]], let firstJson = jsonObject.first {
                print("DEBUG SOURCE JSON: First source keys: \(firstJson.keys.sorted())")
                print("DEBUG SOURCE JSON: searchUrl value in JSON: \(String(describing: firstJson["searchUrl"]))")
                if let ruleSearch = firstJson["ruleSearch"] as? [String: Any] {
                     print("DEBUG SOURCE JSON: ruleSearch keys: \(ruleSearch.keys.sorted())")
                }
            }
            
            let decoder = JSONDecoder()
            sources = try decoder.decode([BookSource].self, from: data)
            print("Loaded \(sources.count) sources.")
            
            if let first = sources.first {
                print("DEBUG SOURCE: First source name: \(first.bookSourceName)")
                print("DEBUG SOURCE: searchUrl: \(String(describing: first.searchUrl))")
                
                let countWithSearchUrl = sources.filter { $0.searchUrl != nil && !$0.searchUrl!.isEmpty }.count
                print("DEBUG SOURCE: Sources with searchUrl: \(countWithSearchUrl) / \(sources.count)")
            }
            
        } catch {
            print("Error loading sources: \(error)")
        }
    }
    
    /// Saves the current list of sources to the local file system.
    func saveSources() {
        guard let url = getDocumentsDirectory()?.appendingPathComponent(fileName) else { return }
        
        do {
            let encoder = JSONEncoder()
            // Pretty print for debugging capability, though it takes more space
            encoder.outputFormatting = .prettyPrinted 
            let data = try encoder.encode(sources)
            try data.write(to: url)
            print("Saved \(sources.count) sources.")
        } catch {
            print("Error saving sources: \(error)")
        }
    }
    
    /// Imports sources from a JSON string (supports single object or array).
    /// Duplicates (by bookSourceUrl) will be overwritten.
    func importSource(from json: String) {
        guard let data = json.data(using: .utf8) else {
            print("Invalid JSON string")
            return
        }
        
        let decoder = JSONDecoder()
        var newSources: [BookSource] = []
        
        // Try decoding as Array first
        if let list = try? decoder.decode([BookSource].self, from: data) {
            newSources = list
        } 
        // Try decoding as Single Object
        else if let single = try? decoder.decode(BookSource.self, from: data) {
            newSources = [single]
        } 
        else {
            print("Failed to decode JSON as BookSource or [BookSource]")
            return
        }
        
        guard !newSources.isEmpty else { return }
        
        // Helper set for fast lookup of new URLS
        let newSourceMap = Dictionary(uniqueKeysWithValues: newSources.map { ($0.bookSourceUrl, $0) })
        
        // Update existing in place
        for i in 0..<sources.count {
            if let updated = newSourceMap[sources[i].bookSourceUrl] {
                sources[i] = updated
            }
        }
        
        // Append completely new ones
        let existingUrls = Set(sources.map { $0.bookSourceUrl })
        let trulyNewSources = newSources.filter { !existingUrls.contains($0.bookSourceUrl) }
        sources.append(contentsOf: trulyNewSources)
        
        saveSources()
    }
    
    /// Deletes sources at specific offsets (for SwiftUI List).
    func deleteSource(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        saveSources()
    }
    
    /// Deletes all sources.
    func deleteAll() {
        sources.removeAll()
        saveSources()
    }
    
    /// Toggles the enabled state of a source.
    func toggleSource(_ source: BookSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            sources[index].enabled.toggle()
            saveSources()
        }
    }
    
    // MARK: - Search
    
    /// Filters sources based on a keyword.
    func search(keyword: String) -> [BookSource] {
        guard !keyword.isEmpty else { return sources }
        
        let key = keyword.lowercased()
        return sources.filter { source in
            source.bookSourceName.lowercased().contains(key) ||
            source.bookSourceUrl.lowercased().contains(key) ||
            (source.bookSourceGroup?.lowercased().contains(key) ?? false)
        }
    }
    
    // MARK: - Defaults
    
    /// Loads default sources if none exist.
    private func loadDefaultSources() {
        // Sample default source (similar to Legado's minimal example or a placeholder)
        // Since we don't have the assets file, we create a simple one in code.
        let defaultSource = BookSource(
            bookSourceUrl: "https://www.example.com",
            bookSourceName: "示例书源",
            bookSourceGroup: "默认",
            bookSourceType: 0,
            enabled: true,
            searchUrl: "https://www.example.com/search?keyword={{key}}",
            ruleSearch: .init(
                bookList: "class.book-list",
                name: "class.name@text",
                author: "class.author@text",
                intro: "class.intro@text",
                bookUrl: "a@href"
            ),
            ruleContent: .init(content: "id.content@text")
        )
        
        sources = [defaultSource]
        saveSources()
    }
    
    // MARK: - Helpers
    
    private func getDocumentsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
}
