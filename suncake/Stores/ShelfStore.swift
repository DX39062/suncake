import Foundation
import Combine
internal import SwiftUI

class ShelfStore: ObservableObject {
    @Published var books: [Book] = []
    
    private let fileName = "books.json"
    
    init() {
        loadBooks()
    }
    
    // MARK: - Persistence
    
    private func getDocumentsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
    
    private func getFileUrl() -> URL? {
        getDocumentsDirectory()?.appendingPathComponent(fileName)
    }
    
    func loadBooks() {
        guard let url = getFileUrl() else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            books = try decoder.decode([Book].self, from: data)
            // Sort by durChapterTime desc by default (Recent read)
            books.sort { $0.durChapterTime > $1.durChapterTime }
        } catch {
            print("ShelfStore: Error loading books: \(error)")
        }
    }
    
    func saveBooks() {
        guard let url = getFileUrl() else { return }
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(books)
            try data.write(to: url)
        } catch {
            print("ShelfStore: Error saving books: \(error)")
        }
    }
    
    // MARK: - CRUD
    
    func addBook(_ book: Book) {
        if let index = books.firstIndex(where: { $0.bookUrl == book.bookUrl }) {
            // Already exists, maybe update?
            books[index] = book
        } else {
            var newBook = book
            newBook.order = books.count
            newBook.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
            books.insert(newBook, at: 0)
        }
        saveBooks()
    }
    
    func deleteBook(_ book: Book) {
        books.removeAll { $0.bookUrl == book.bookUrl }
        saveBooks()
    }
    
    func deleteBooks(at offsets: IndexSet) {
        books.remove(atOffsets: offsets)
        saveBooks()
    }
    
    func inShelf(_ bookUrl: String) -> Bool {
        return books.contains { $0.bookUrl == bookUrl }
    }
    
    func getBook(_ bookUrl: String) -> Book? {
        return books.first { $0.bookUrl == bookUrl }
    }
    
    // MARK: - Progress Update
    
    func updateProgress(bookUrl: String, index: Int, pos: Int, title: String? = nil) {
        if let idx = books.firstIndex(where: { $0.bookUrl == bookUrl }) {
            books[idx].durChapterIndex = index
            books[idx].durChapterPos = pos
            if let t = title {
                books[idx].durChapterTitle = t
            }
            books[idx].durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
            
            // Re-sort
            books.sort { $0.durChapterTime > $1.durChapterTime }
            saveBooks()
        }
    }
    
    // MARK: - Info Update
    
    func updateBookInfo(_ book: Book) {
        if let idx = books.firstIndex(where: { $0.bookUrl == book.bookUrl }) {
            books[idx] = book
            saveBooks()
        }
    }
}
