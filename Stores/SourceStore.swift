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
        }
    }
    
    // MARK: - Core Methods
    
    /// Loads sources from the local file system.
    func loadSources() {
        guard let url = getDocumentsDirectory()?.appendingPathComponent(fileName) else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            sources = try decoder.decode([BookSource].self, from: data)
            print("Loaded \(sources.count) sources.")
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
        
        // Merge with existing sources
        var currentSourcesDict = Dictionary(uniqueKeysWithValues: sources.map { ($0.bookSourceUrl, $0) })
        
        for source in newSources {
            currentSourcesDict[source.bookSourceUrl] = source
        }
        
        // Convert back to array and sort by customOrder or other criteria if needed
        // For now, we just update the list.
        // To maintain some order, we might want to keep original order + new ones, but dictionary loses order.
        // Let's implement a more careful merge to preserve order if possible, or just append new ones and replace old ones in place.
        
        // Strategy: 
        // 1. Identify indices of existing sources to update.
        // 2. Append new sources that don't exist.
        
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
