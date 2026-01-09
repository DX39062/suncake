import Foundation

struct Book: Identifiable, Hashable, Codable {
    var id: String { bookUrl } // Primary key is bookUrl
    
    // Core Info
    var bookUrl: String
    var tocUrl: String
    var origin: String
    var originName: String
    var name: String
    var author: String
    var kind: String?
    var customTag: String?
    var coverUrl: String?
    var customCoverUrl: String?
    var intro: String?
    var customIntro: String?
    var charset: String?
    var type: Int = 0 // 0: text, 1: audio
    var group: Int = 0
    
    // Updates
    var latestChapterTitle: String?
    var latestChapterTime: Int64 = 0
    var lastCheckTime: Int64 = 0
    var lastCheckCount: Int = 0
    var totalChapterNum: Int = 0
    
    // Progress
    var durChapterTitle: String?
    var durChapterIndex: Int = 0
    var durChapterPos: Int = 0
    var durChapterTime: Int64 = 0
    
    // Other
    var wordCount: String?
    var canUpdate: Bool = true
    var order: Int = 0
    var originOrder: Int = 0
    var variable: String?
    
    // Helper accessors
    var displayCover: String { customCoverUrl ?? coverUrl ?? "" }
    var displayIntro: String { customIntro ?? intro ?? "" }
    
    init(
        bookUrl: String,
        tocUrl: String = "",
        origin: String = "",
        originName: String = "",
        name: String = "",
        author: String = "",
        kind: String? = nil,
        customTag: String? = nil,
        coverUrl: String? = nil,
        customCoverUrl: String? = nil,
        intro: String? = nil,
        customIntro: String? = nil,
        charset: String? = nil,
        type: Int = 0,
        group: Int = 0,
        latestChapterTitle: String? = nil,
        latestChapterTime: Int64 = 0,
        lastCheckTime: Int64 = 0,
        lastCheckCount: Int = 0,
        totalChapterNum: Int = 0,
        durChapterTitle: String? = nil,
        durChapterIndex: Int = 0,
        durChapterPos: Int = 0,
        durChapterTime: Int64 = 0,
        wordCount: String? = nil,
        canUpdate: Bool = true,
        order: Int = 0,
        originOrder: Int = 0,
        variable: String? = nil
    ) {
        self.bookUrl = bookUrl
        self.tocUrl = tocUrl.isEmpty ? bookUrl : tocUrl
        self.origin = origin
        self.originName = originName
        self.name = name
        self.author = author
        self.kind = kind
        self.customTag = customTag
        self.coverUrl = coverUrl
        self.customCoverUrl = customCoverUrl
        self.intro = intro
        self.customIntro = customIntro
        self.charset = charset
        self.type = type
        self.group = group
        self.latestChapterTitle = latestChapterTitle
        self.latestChapterTime = latestChapterTime
        self.lastCheckTime = lastCheckTime
        self.lastCheckCount = lastCheckCount
        self.totalChapterNum = totalChapterNum
        self.durChapterTitle = durChapterTitle
        self.durChapterIndex = durChapterIndex
        self.durChapterPos = durChapterPos
        self.durChapterTime = durChapterTime
        self.wordCount = wordCount
        self.canUpdate = canUpdate
        self.order = order
        self.originOrder = originOrder
        self.variable = variable
    }
}

extension Book {
    // 目录项模型
    struct Chapter: Identifiable, Codable, Hashable {
        var id: String { url }
        let title: String
        let url: String
        let index: Int
        var isVolume: Bool = false
    }
}