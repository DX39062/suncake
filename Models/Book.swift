import Foundation

struct Book: Identifiable, Hashable, Codable {
    var id: String { bookUrl + origin }
    
    var name: String
    var author: String
    var coverUrl: String?
    var bookUrl: String
    var origin: String
    var originName: String
    var intro: String?
    var kind: String?
    var latestChapterTitle: String?
}
