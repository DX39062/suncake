import Foundation

struct BookSource: Codable, Identifiable, Hashable {
    var id: String { bookSourceUrl }
    
    // 地址，包括 http/https
    var bookSourceUrl: String
    // 名称
    var bookSourceName: String
    // 分组
    var bookSourceGroup: String?
    // 类型，0 文本，1 音频, 2 图片, 3 文件
    var bookSourceType: Int
    // 详情页url正则
    var bookUrlPattern: String?
    // 手动排序编号
    var customOrder: Int
    // 是否启用
    var enabled: Bool
    // 启用发现
    var enabledExplore: Bool
    // js库
    var jsLib: String?
    // 启用okhttp CookieJAr 自动保存每次请求的cookie
    var enabledCookieJar: Bool?
    // 并发率
    var concurrentRate: String?
    // 请求头
    var header: String?
    // 登录地址
    var loginUrl: String?
    // 登录UI
    var loginUi: String?
    // 登录检测js
    var loginCheckJs: String?
    // 封面解密js
    var coverDecodeJs: String?
    // 注释
    var bookSourceComment: String?
    // 自定义变量说明
    var variableComment: String?
    // 最后更新时间，用于排序
    var lastUpdateTime: Int64
    // 响应时间，用于排序
    var respondTime: Int64
    // 智能排序的权重
    var weight: Int
    // 发现url
    var exploreUrl: String?
    // 发现筛选规则
    var exploreScreen: String?
    // 搜索url
    var searchUrl: String?
    
    // Rules
    var ruleExplore: BookListRule?
    var ruleSearch: BookListRule?
    var ruleBookInfo: BookInfoRule?
    var ruleToc: TocRule?
    var ruleContent: ContentRule?

    init(
        bookSourceUrl: String = "",
        bookSourceName: String = "",
        bookSourceGroup: String? = nil,
        bookSourceType: Int = 0,
        bookUrlPattern: String? = nil,
        customOrder: Int = 0,
        enabled: Bool = true,
        enabledExplore: Bool = true,
        jsLib: String? = nil,
        enabledCookieJar: Bool? = true,
        concurrentRate: String? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        coverDecodeJs: String? = nil,
        bookSourceComment: String? = nil,
        variableComment: String? = nil,
        lastUpdateTime: Int64 = 0,
        respondTime: Int64 = 180000,
        weight: Int = 0,
        exploreUrl: String? = nil,
        exploreScreen: String? = nil,
        searchUrl: String? = nil,
        ruleExplore: BookListRule? = nil,
        ruleSearch: BookListRule? = nil,
        ruleBookInfo: BookInfoRule? = nil,
        ruleToc: TocRule? = nil,
        ruleContent: ContentRule? = nil
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.bookUrlPattern = bookUrlPattern
        self.customOrder = customOrder
        self.enabled = enabled
        self.enabledExplore = enabledExplore
        self.jsLib = jsLib
        self.enabledCookieJar = enabledCookieJar
        self.concurrentRate = concurrentRate
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.coverDecodeJs = coverDecodeJs
        self.bookSourceComment = bookSourceComment
        self.variableComment = variableComment
        self.lastUpdateTime = lastUpdateTime
        self.respondTime = respondTime
        self.weight = weight
        self.exploreUrl = exploreUrl
        self.exploreScreen = exploreScreen
        self.searchUrl = searchUrl
        self.ruleExplore = ruleExplore
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
    }
    
    // MARK: - Nested Rules
    
    struct BookListRule: Codable, Hashable {
        var bookList: String?
        var name: String?
        var author: String?
        var intro: String?
        var kind: String?
        var lastChapter: String?
        var updateTime: String?
        var coverUrl: String?
        var bookUrl: String?
        var wordCount: String?
        var checkKeyWord: String?
    }
    
    struct BookInfoRule: Codable, Hashable {
        var `init`: String?
        var name: String?
        var author: String?
        var intro: String?
        var kind: String?
        var lastChapter: String?
        var updateTime: String?
        var coverUrl: String?
        var tocUrl: String?
        var wordCount: String?
        var canReName: String?
        var downloadUrls: String?
    }
    
    struct TocRule: Codable, Hashable {
        var chapterList: String?
        var chapterName: String?
        var chapterUrl: String?
        var isVolume: String?
        var preUpdateJs: String?
        var formatJs: String?
        var updateTime: String?
        var nextTocUrl: String?
    }
    
    struct ContentRule: Codable, Hashable {
        var content: String?
        var nextContentUrl: String?
        var webJs: String?
        var sourceRegex: String?
        var replaceRegex: String?
        var imageStyle: String?
        var payAction: String?
    }
}
