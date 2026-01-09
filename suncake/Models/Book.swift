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

extension Book {
    // 增加详情相关字段（可根据需要添加更多）
    struct Details {
        var intro: String = ""
        var lastChapter: String = ""
        var kind: String = "" // 分类/标签
        var tocUrl: String = "" // 目录链接（有时与 bookUrl 不同）
    }
    
    // 目录项模型
    struct Chapter: Identifiable {
        let id = UUID()
        let title: String
        let url: String
        let index: Int
        var isVolume: Bool = false
    }
}